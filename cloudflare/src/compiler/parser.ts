// Turns a manifest source string into a Manifest. Supports three surfaces that
// compile to the same AST:
//
//   JSON      — machine / tool-call friendly
//   YAML      — canonical, human and agent friendly
//   Markdown  — front matter for deck meta, `---` between slides
//
// Port of p2u/parser.rb.

import { parse as parseYaml } from "yaml";
import { Manifest } from "./manifest";
import { ParseError } from "./diagnostic";
import { isBlank, presence } from "./util";
import { VERSION } from "./version";

export type Format = "json" | "yaml" | "markdown";

const MARKDOWN_SEPARATOR = /\n[ \t]*---[ \t]*\n/;
const FORMATS = ["json", "yaml", "yml", "markdown", "md"];

export class Parser {
  private readonly source: string;
  private readonly format?: string;

  constructor(source: unknown, format?: string | null) {
    this.source = typeof source === "string" ? source : JSON.stringify(source);
    this.format = presence(format)?.toLowerCase();
  }

  static parse(source: unknown, format?: string | null): Manifest {
    return new Parser(source, format).parse();
  }

  parse(): Manifest {
    if (isBlank(this.source)) throw new ParseError("Manifest source is empty");

    const format = this.format ?? detectFormat(this.source);
    try {
      switch (format) {
        case "json":
          return parseJson(this.source);
        case "yaml":
        case "yml":
          return parseYamlDocument(this.source);
        case "markdown":
        case "md":
          return parseMarkdown(this.source);
        default:
          throw new ParseError(`Unsupported format: ${JSON.stringify(format)} (expected one of ${FORMATS.join(", ")})`);
      }
    } catch (error) {
      if (error instanceof ParseError) throw error;
      throw new ParseError(`Could not parse ${format} manifest: ${(error as Error).message}`);
    }
  }
}

function detectFormat(source: string): Format {
  const stripped = source.replace(/^\s+/, "");
  if (stripped.startsWith("{") || stripped.startsWith("[")) return "json";
  if (markdownFrontMatter(stripped)) return "markdown";
  if (MARKDOWN_SEPARATOR.test(source) && !yamlLike(stripped)) return "markdown";
  return "yaml";
}

/** A Markdown document has front matter delimited by a second `---`. */
function markdownFrontMatter(text: string): boolean {
  return text.startsWith("---") && /^---[ \t]*\r?\n[\s\S]*?\r?\n---[ \t]*(\r?\n|$)/.test(text);
}

function yamlLike(text: string): boolean {
  return /^(p2u|version|deck|slides)\s*:/.test(text);
}

function parseJson(source: string): Manifest {
  return new Manifest(JSON.parse(source));
}

function parseYamlDocument(source: string): Manifest {
  return new Manifest(parseYaml(source) ?? {});
}

function parseMarkdown(source: string): Manifest {
  let text = source;
  let meta: Record<string, any> = {};

  if (text.startsWith("---")) {
    const rest = text.replace(/^---\s*\n/, "");
    const match = rest.match(/\n---\s*\n/);
    if (match && match.index !== undefined) {
      const front = rest.slice(0, match.index);
      const body = rest.slice(match.index + match[0].length);
      const parsed = parseYaml(front);
      meta = parsed && typeof parsed === "object" ? parsed : {};
      text = body;
    }
  }

  const deck = meta.deck && typeof meta.deck === "object" ? meta.deck : omit(meta, ["p2u", "version", "slides"]);
  const slides = text
    .split(MARKDOWN_SEPARATOR)
    .map((chunk) => markdownSlide(chunk))
    .filter((slide): slide is Record<string, unknown> => slide !== null);

  return new Manifest({ p2u: meta.p2u ?? meta.version ?? VERSION, deck, slides });
}

function markdownSlide(chunk: string): Record<string, unknown> | null {
  const text = chunk.trim();
  if (isBlank(text)) return null;

  if (text.startsWith("# ")) {
    const { heading, body } = splitHeading(text);
    return compact({ layout: "section", title: heading, body: presence(body) });
  }
  if (text.startsWith("## ")) {
    const { heading, body } = splitHeading(text);
    return compact({ layout: "content", title: heading, body: presence(body) });
  }
  return { layout: "content", body: text };
}

function splitHeading(text: string): { heading: string; body: string } {
  const lines = text.split("\n");
  const heading = (lines[0] ?? "").replace(/^#{1,6}\s*/, "").trim();
  const body = lines.slice(1).join("\n").trim();
  return { heading, body };
}

function omit(source: Record<string, any>, keys: string[]): Record<string, any> {
  const out: Record<string, any> = {};
  for (const [key, value] of Object.entries(source)) {
    if (!keys.includes(key)) out[key] = value;
  }
  return out;
}

function compact(source: Record<string, unknown>): Record<string, unknown> {
  const out: Record<string, unknown> = {};
  for (const [key, value] of Object.entries(source)) {
    if (value !== undefined && value !== null) out[key] = value;
  }
  return out;
}