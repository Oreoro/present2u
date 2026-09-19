require "net/http"
require "json"
require "uri"
require "open-uri"
require "resolv"
require "ipaddr"

# Thin client for the Context.dev web context API.
#
# Used to pull imagery into slides: images referenced by a page, full-page
# screenshots, and brand assets. Configure with the CONTEXT_DEV_API_KEY
# environment variable. See https://docs.context.dev.
class ContextDev
  class Error < StandardError; end

  BASE_URL = "https://api.context.dev/v1"
  OPEN_TIMEOUT = 5
  READ_TIMEOUT = 45
  MAX_IMAGE_BYTES = 25.megabytes

  class << self
    def api_key
      ENV["CONTEXT_DEV_API_KEY"].presence
    end

    def configured?
      api_key.present?
    end

    # Images referenced by a page. Each result is a hash with "src", "alt",
    # "width", "height", "mimetype" and "kind" keys, preferring the
    # Context.dev-hosted copy when one is available.
    def images(url:)
      response = get("/web/scrape/images", {
        url: url,
        "enrichment[hostedUrl]" => "true",
        "enrichment[resolution]" => "true",
        "enrichment[classification]" => "true",
        "dedupe" => "true"
      })

      Array(response["images"]).filter_map { |image| normalize_image(image) }
    end

    def screenshot(url:, width: 1920, height: 1080, full_page: false, color_scheme: nil)
      params = {
        url: url,
        fullScreenshot: full_page.to_s,
        "viewport[width]" => width,
        "viewport[height]" => height
      }
      params["colorScheme"] = color_scheme if color_scheme.present?

      response = get("/web/scrape/screenshot", params)

      {
        "src" => response["screenshot"],
        "alt" => "Screenshot of #{url}",
        "width" => response["width"],
        "height" => response["height"],
        "kind" => "screenshot"
      }
    end

    def brand(domain:)
      post("/brand/retrieve", { type: "by_domain", domain: domain })["brand"]
    end

    # Fetches a remote image for Active Storage. Returns io/filename/content_type.
    def download_image(url)
      uri = validate_image_url!(url)

      io = uri.open("rb", read_timeout: READ_TIMEOUT, open_timeout: OPEN_TIMEOUT)
      bytes = io.read(MAX_IMAGE_BYTES + 1)
      io.close

      raise Error, "Image is larger than #{MAX_IMAGE_BYTES / 1.megabyte}MB" if bytes.bytesize > MAX_IMAGE_BYTES

      {
        io: StringIO.new(bytes),
        filename: File.basename(uri.path).presence || "slide-image",
        content_type: Marcel::MimeType.for(StringIO.new(bytes), name: File.basename(uri.path))
      }
    end

    private
      def normalize_image(image)
        hosted = image.dig("enrichment", "url").presence
        source = hosted || (image["type"] == "url" ? image["src"].presence : nil)
        return if source.blank? || !source.start_with?("http")

        {
          "src" => source,
          "alt" => image["alt"],
          "width" => image.dig("enrichment", "width"),
          "height" => image.dig("enrichment", "height"),
          "mimetype" => image.dig("enrichment", "mimetype"),
          "kind" => image.dig("enrichment", "type")
        }
      end

      def validate_image_url!(url)
        uri = URI.parse(url.to_s)
        raise Error, "Only http(s) image URLs are supported" unless uri.is_a?(URI::HTTP) && uri.host.present?
        raise Error, "Refusing to fetch a local address" if private_host?(uri.host)

        uri
      rescue URI::InvalidURIError
        raise Error, "That image URL is not valid"
      end

      def private_host?(host)
        host = host.downcase
        return true if host == "localhost" || host.end_with?(".local")

        resolved = begin
          Resolv.getaddresses(host)
        rescue StandardError
          []
        end
        resolved.any? do |address|
          ip = IPAddr.new(address) rescue nil
          ip && (ip.loopback? || ip.private? || ip.link_local?)
        end
      end

      def get(path, params)
        uri = URI("#{BASE_URL}#{path}")
        uri.query = URI.encode_www_form(params)
        perform(uri, Net::HTTP::Get.new(uri))
      end

      def post(path, body)
        uri = URI("#{BASE_URL}#{path}")
        request = Net::HTTP::Post.new(uri)
        request["Content-Type"] = "application/json"
        request.body = body.to_json
        perform(uri, request)
      end

      def perform(uri, request)
        raise Error, "Context.dev is not configured. Set CONTEXT_DEV_API_KEY." unless configured?

        request["Authorization"] = "Bearer #{api_key}"
        request["Accept"] = "application/json"

        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = uri.scheme == "https"
        http.open_timeout = OPEN_TIMEOUT
        http.read_timeout = READ_TIMEOUT

        response = http.request(request)
        payload = JSON.parse(response.body.presence || "{}")

        unless response.is_a?(Net::HTTPSuccess)
          raise Error, payload["message"].presence || "Context.dev request failed (#{response.code})"
        end

        payload
      rescue JSON::ParserError
        raise Error, "Context.dev returned an unreadable response"
      rescue Timeout::Error, Errno::ECONNREFUSED, SocketError => e
        raise Error, "Could not reach Context.dev: #{e.message}"
      end
  end
end
