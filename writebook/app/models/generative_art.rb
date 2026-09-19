require "digest"

# Deterministic generative cover art. Given a seed (a deck slug or template key)
# it composes an abstract Bauhaus-style SVG — circles, rings, bars and triangles
# over a colour field — so every deck has its own unique artwork. Pure function:
# the same seed always yields the same composition.
class GenerativeArt
  WIDTH = 160
  HEIGHT = 90

  PALETTES = {
    "blue" => %w[#2383e2 #529cca #e9e9e7],
    "violet" => %w[#9065b0 #2383e2 #f7f7f5],
    "magenta" => %w[#c14c8a #9065b0 #2383e2],
    "orange" => %w[#d9730d #cb912f #9065b0],
    "green" => %w[#448361 #529cca #2383e2],
    "black" => %w[#191919 #2383e2 #529cca],
    "white" => %w[#f7f7f5 #e9e9e7 #2383e2]
  }.freeze

  def self.svg(seed:, theme: "violet", width: WIDTH, height: HEIGHT)
    digest = Digest::MD5.hexdigest(seed.to_s)
    rng = Random.new(digest[0, 12].to_i(16))
    colors = PALETTES[theme.to_s] || PALETTES["violet"]
    uid = digest[0, 6]

    shapes = [
      circle(rng, colors, rng.rand(34..58)),
      ring(rng, colors),
      bar(rng, colors),
      triangle(rng, colors),
      circle(rng, colors, rng.rand(8..16)),
      bar(rng, colors),
      ring(rng, colors)
    ].shuffle(random: rng).join

    <<~SVG
      <svg viewBox="0 0 #{width} #{height}" preserveAspectRatio="xMidYMid slice" xmlns="http://www.w3.org/2000/svg" aria-hidden="true" focusable="false">
        <defs>
          <linearGradient id="bg#{uid}" x1="0" y1="0" x2="1" y2="1">
            <stop offset="0" stop-color="#{colors[0]}"/>
            <stop offset="1" stop-color="#{colors[1]}"/>
          </linearGradient>
          <radialGradient id="glow#{uid}" cx="0.28" cy="0.24" r="0.9">
            <stop offset="0" stop-color="#{colors[2]}" stop-opacity="0.85"/>
            <stop offset="1" stop-color="#{colors[2]}" stop-opacity="0"/>
          </radialGradient>
        </defs>
        <rect width="#{width}" height="#{height}" fill="url(#bg#{uid})"/>
        <rect width="#{width}" height="#{height}" fill="url(#glow#{uid})"/>
        #{shapes}
      </svg>
    SVG
  end

  def self.circle(rng, colors, radius)
    %(<circle cx="#{rng.rand(-10..WIDTH + 10)}" cy="#{rng.rand(-6..HEIGHT + 6)}" r="#{radius}" fill="#{colors.sample(random: rng)}" opacity="#{opacity(rng, 0.3, 0.85)}"/>)
  end

  def self.ring(rng, colors)
    %(<circle cx="#{rng.rand(0..WIDTH)}" cy="#{rng.rand(0..HEIGHT)}" r="#{rng.rand(10..32)}" fill="none" stroke="#{colors.sample(random: rng)}" stroke-width="#{rng.rand(2..5)}" opacity="#{opacity(rng, 0.5, 0.95)}"/>)
  end

  def self.bar(rng, colors)
    x = rng.rand(-24..WIDTH)
    y = rng.rand(-8..HEIGHT)
    width = rng.rand(34..118)
    height = rng.rand(3..9)
    rotation = rng.rand(-38..38)

    %(<rect x="#{x}" y="#{y}" width="#{width}" height="#{height}" rx="#{height / 2}" fill="#{colors.sample(random: rng)}" opacity="#{opacity(rng, 0.55, 0.95)}" transform="rotate(#{rotation} #{x} #{y})"/>)
  end

  def self.triangle(rng, colors)
    x = rng.rand(8..WIDTH - 8)
    y = rng.rand(14..HEIGHT - 8)
    size = rng.rand(14..34)

    %(<polygon points="#{x},#{y} #{x + size},#{y} #{x + size / 2},#{y - size}" fill="#{colors.sample(random: rng)}" opacity="#{opacity(rng, 0.5, 0.85)}"/>)
  end

  def self.opacity(rng, min, max)
    (min + (rng.rand * (max - min))).round(2)
  end
  private_class_method :opacity
end
