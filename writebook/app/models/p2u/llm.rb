require "net/http"
require "json"
require "uri"

module P2u
  # Minimal OpenAI-compatible chat client used by P2u::Composer. Configure with
  # P2U_LLM_API_KEY (or OPENAI_API_KEY), and optionally P2U_LLM_BASE_URL and
  # P2U_LLM_MODEL. When unconfigured, the composer falls back to a deterministic
  # outline so the feature still works offline.
  module LLM
    class Error < StandardError; end

    OPEN_TIMEOUT = 10
    READ_TIMEOUT = 90

    class << self
      def api_key
        ENV["P2U_LLM_API_KEY"].presence || ENV["OPENAI_API_KEY"].presence
      end

      def base_url
        ENV.fetch("P2U_LLM_BASE_URL", "https://api.openai.com/v1").chomp("/")
      end

      def model
        ENV.fetch("P2U_LLM_MODEL", "gpt-4o-mini")
      end

      def configured? = api_key.present?

      # Returns the assistant message content as a string.
      def complete(system:, user:, temperature: 0.2)
        raise Error, "No LLM API key configured (set P2U_LLM_API_KEY or OPENAI_API_KEY)" unless configured?

        uri = URI("#{base_url}/chat/completions")
        request = Net::HTTP::Post.new(uri)
        request["Authorization"] = "Bearer #{api_key}"
        request["Content-Type"] = "application/json"
        request.body = {
          model: model,
          temperature: temperature,
          messages: [
            { role: "system", content: system },
            { role: "user", content: user }
          ]
        }.to_json

        response = perform(uri, request)
        payload = JSON.parse(response.body.presence || "{}")
        payload.dig("choices", 0, "message", "content").to_s
      rescue JSON::ParserError
        raise Error, "LLM returned an unreadable response"
      rescue Timeout::Error, Errno::ECONNREFUSED, SocketError => e
        raise Error, "Could not reach the LLM: #{e.message}"
      end

      private
        def perform(uri, request)
          http = Net::HTTP.new(uri.host, uri.port)
          http.use_ssl = uri.scheme == "https"
          http.open_timeout = OPEN_TIMEOUT
          http.read_timeout = READ_TIMEOUT

          response = http.request(request)
          return response if response.is_a?(Net::HTTPSuccess)

          message = begin
            JSON.parse(response.body).dig("error", "message")
          rescue JSON::ParserError
            nil
          end
          raise Error, message.presence || "LLM request failed (#{response.code})"
        end
    end
  end
end
