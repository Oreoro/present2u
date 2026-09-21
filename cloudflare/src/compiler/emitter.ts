// Compiles a Manifest into the legacy slide shape the presentation runtime
// already understands. Typed blocks are serialised back into Markdown fences so
// the existing renderer (d2, d2-sketch, latex, Rouge) renders them with no
// changes. Port of p2u/emitter.rb.

import { Manifest } from "./manifest";
import type { Slide, Block } from "./manifest";
import { asBool, deepStringify, presence } from "./util";

export interface DeckAttributes {
  title: string;
  subtitle?: string | null;
  author?: string | null;
  theme?: string;
}

export interface SlideAttributes {
  id: string;
  layout: string;
  title: string;
  notes?: string | null;
  sketch: boolean;
  type: string;
  body?: string | null;
  source?: string | null;
  theme?: string | null;
  caption?: string | null;
  image_url?: string | null;
}

export class Emitter {
  private readonly manifest: Manifest;

  constructor(manifest: Manifest | unknown) {
    this.manifest = manifest instanceof Manifest ? manifest : new Manifest(manifest);
  }

  get deckAttributes(): DeckAttributes {
    const deck = this.manifest.deck;
    return {
      title: presence(deck.title) ?? "Untitled deck",
      subtitle: deck.subtitle ?? null,
      author: deck.author ?? null,
      theme: themeName(deck.theme),
    };
  }

  get slides(): SlideAttributes[] {
    const format = this.deckFormat;
    return this.manifest.slides.map((slide) => this.slideAttributes(slide, format));
  }

  get manifestOutput(): { deck: DeckAttributes & { slides: SlideAttributes[] } } {
    return { deck: { ...this.deckAttributes, slides: this.slides } };
  }

  private get deckFormat(): string {
    return String(presence(this.manifest.deck.format) ?? presence(this.manifest.deck.engine) ?? "markdown");
  }

  private slideAttributes(slide: Slide, deckFormat: string): SlideAttributes {
    const layout = String(slide.layout);
    const base: SlideAttributes = {
      id: slide.id,
      layout,
      title: this.titleFor(slide, layout),
      notes: presence(slide.notes) ?? null,
      sketch: asBool(slide.sketch),
      type: "content",
    };

    const format = String(presence(slide.format) ?? deckFormat);
    if (format === "typst") return { ...base, type: "typst", source: String(slide.body ?? "") };

    if (layout === "section" || layout === "title") {
      return {
        ...base,
        type: "section",
        body: presence(slide.body) ?? String(slide.title ?? ""),
        theme: (presence(slide.theme) as string | undefined) ?? null,
      };
    }

    if (layout === "image" || layout === "image-grid") {
      const image = firstImage(slide);
      return {
        ...base,
        type: "image",
        caption: presence(slide.caption) ?? presence(image.caption) ?? null,
        image_url:
          presence(image.url) ?? presence(image.src) ?? presence(image.image_url) ?? presence(slide.image_url) ?? null,
      };
    }

    return { ...base, type: "content", body: this.bodyFor(slide) };
  }

  private titleFor(slide: Slide, layout: string): string {
    const explicit = presence(slide.title);
    if (explicit) return explicit;

    const typst = typstHeading(slide);
    if (typst) return typst;

    if (layout === "section" || layout === "title") return "Section slide";
    if (layout === "image" || layout === "image-grid") return "Image slide";
    return "Untitled";
  }

  private bodyFor(slide: Slide): string {
    if (presence(slide.body)) return String(slide.body);

    const blocks = (slide.blocks ?? []).map((block) => serializeBlock(block));
    const slots = ["left", "right", "code", "prose"]
      .map((slot) => serializeSlot(slide[slot]))
      .filter((value): value is string => value !== null);
    return [...blocks, ...slots].filter((part) => part.trim().length > 0).join("\n\n");
  }
}

function typstHeading(slide: Slide): string | undefined {
  const body = String(slide.body ?? "");
  const heading = body.match(/^[ \t]*=[ \t]+(.+?)[ \t]*$/m);
  if (heading && heading[1]) return heading[1].trim();

  const helper = body.match(/#p2u-title\(\s*"([^"]+)"/);
  return helper?.[1];
}

function firstImage(slide: Slide): Record<string, any> {
  const found = (slide.blocks ?? []).find(
    (block) => block && typeof block === "object" && String((block as any).kind ?? "") === "image",
  );
  return (found as Record<string, any>) ?? {};
}

function serializeSlot(value: unknown): string | null {
  if (value && typeof value === "object" && !Array.isArray(value)) {
    const record = value as Record<string, unknown>;
    return presence(record.kind) ? serializeBlock(record as Block) : serializeBlock({ ...record, kind: "markdown" });
  }
  if (typeof value === "string") return value;
  return null;
}

export function serializeBlock(block: Block | unknown): string {
  if (!block || typeof block !== "object") return String(block ?? "");

  const value = deepStringify(block) as Record<string, any>;

  switch (String(value.kind ?? "")) {
    case "markdown":
      return String(value.body ?? "");
    case "code":
      return fenced(presence(value.lang) ?? "text", value.source);
    case "diagram":
      return fenced(presence(value.lang) ?? "d2", value.source);
    case "equation":
      return fenced("latex", value.source);
    case "image":
      return `![${presence(value.alt) ?? presence(value.caption) ?? ""}](${presence(value.url) ?? presence(value.src) ?? presence(value.image_url) ?? ""})`;
    case "quote":
      return quoteMarkdown(value);
    case "callout":
      return `> **${presence(value.tone) ?? "Note"}:** ${value.body}`;
    case "metric":
      return `**${value.label}:** ${value.value}`;
    case "definition":
      return `**${value.term}** — ${value.body}`;
    case "references":
      return Array.isArray(value.items) ? value.items.map((item: unknown) => `- ${item}`).join("\n") : "";
    case "table":
      return tableMarkdown(value);
    case "video":
      return `[${presence(value.title) ?? "Video"}](${value.url})`;
    case "notes-only":
      return "";
    case "spacer":
      return "---";
    default:
      return String(value.body ?? "");
  }
}

function quoteMarkdown(block: Record<string, any>): string {
  const lines = [`> ${block.text}`];
  if (presence(block.attribution)) lines.push(`> — ${block.attribution}`);
  return lines.join("\n");
}

function tableMarkdown(block: Record<string, any>): string {
  if (presence(block.markdown)) return String(block.markdown);
  if (!Array.isArray(block.columns) || !Array.isArray(block.rows)) return "";

  const header = `| ${block.columns.join(" | ")} |`;
  const divider = `| ${block.columns.map(() => "---").join(" | ")} |`;
  const rows = block.rows.map((row: unknown) => `| ${(Array.isArray(row) ? row : []).join(" | ")} |`);
  return [header, divider, ...rows].join("\n");
}

function fenced(language: string, source: unknown): string {
  return "```" + language + "\n" + String(source ?? "") + "\n```";
}

function themeName(theme: unknown): string | undefined {
  const name = theme && typeof theme === "object" ? (theme as any).preset : theme;
  return presence(name);
}