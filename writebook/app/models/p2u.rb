require "json"

# P2U/1 — a declarative presentation manifest language.
#
# A deck is source: a versioned manifest (YAML, JSON or Markdown) compiled by
# P2u::Compiler through parse -> validate -> plan -> emit. Agents drive it via
# the JSON API (/api/compile, /api/schema, /api/toolchain) and bin/p2u.
#
#   P2u.compile(File.read("deck.p2u")).to_h
module P2u
  VERSION = "1".freeze
  SCHEMA_PATH = Rails.root.join("config/schemas/p2u-1.schema.json")

  class Error < StandardError; end
  class ParseError < Error; end

  # Parse a manifest source string (or Hash) into a P2u::Manifest.
  def self.parse(source, format: nil)
    Parser.parse(source, format: format)
  end

  # Parse, validate and (optionally) render a manifest. Returns P2u::Compiler::Result.
  def self.compile(source, format: nil, render: false)
    Compiler.compile(source, format: format, render: render)
  end

  def self.schema
    JSON.parse(File.read(SCHEMA_PATH))
  end

  # Normalises Hashes (including ActionController::Parameters) and Arrays into
  # plain string-keyed structures so the compiler never depends on Rails params.
  def self.deep_stringify(value)
    case value
    when Date, Time, DateTime
      value.iso8601
    when Hash
      value.each_with_object({}) { |(key, val), memo| memo[key.to_s] = deep_stringify(val) }
    when Array
      value.map { |item| deep_stringify(item) }
    else
      if value.respond_to?(:to_unsafe_h)
        deep_stringify(value.to_unsafe_h)
      elsif value.respond_to?(:to_h) && !value.is_a?(String)
        deep_stringify(value.to_h)
      else
        value
      end
    end
  end
end
