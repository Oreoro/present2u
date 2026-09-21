// Renders a single P2U slide (layout + typed blocks) to HTML. Markdown is
// rendered server-side with markdown-it/highlight.js (see markdown.ts); diagrams
// and equations resolve to content-addressed SVG URLs. Port of
// p2u/render/slide.rb.

import type { Slide, Block } from "../compiler/manifest";
import { presence } from "../compiler/util";
import { markdownToHtml } from "./markdown";

export interface SlideRenderOptions {
  dark?: boolean;
  format?: string;
  assetStore?: AssetResolver;
}

export type AssetResolver = (request: {
  slide: string;
  kind: "d2" | "latex" | "typst";
  source: string;
  options: Record<string, unknown>;
}) => Promise<string>;

export async function renderSlide(slide: Slide, options: SlideRenderOptions = {}): Promise<string> {
  const layout = presence(slide.layout) ?? "content";
  const title = String(slide.title ?? "");
  const body = String(slide.body ?? "");
  const blocks = (slide.blocks ?? []) as Block[];

  let inner: string;

  switch (layout) {
    case "title":
    case "section":
      inner = titleLayout(title, presence(slide.subtitle) ?? presence(body));
      break;
    case "two-column":
      inner = columns("two-column", await slot(slide, "left", options), await slot(slide, "right", options), title);
      break;
    case "compare":
      inner = columns("compare", await slot(slide, "left", options), await slot(slide, "right", options), title);
      break;
    case "code-split":
      inner = columns("code-split", await slot(slide, "code", options), await slot(slide, "prose", options), title);
      break;
    case "full-code":
    case "diagram":
    case "equation":
    case "table":
      inner = await blockHtml(slide, blocks[0], options);
      break;
    case "metric-row":
      inner = metricRow(title, blocks);
      break;
    case "image":
    case "image-grid":
      inner = images(title, layout, blocks);
      break;
    case "quote":
      inner = quoteLayout(title, blocks);
      break;
    default:
      inner = await contentLayout(slide, options);
  }

  return `<div class="p2u-slide__inner p2u-slide__inner--${layout}">${inner}</div>`;
}

function titleLayout(title: string, subtitle?: string): string {
  const parts = [`<h1 class="p2u-title">${h(title)}</h1>`];
  if (subtitle) parts.push(`<p class="p2u-subtitle">${h(subtitle)}</p>`);
  return parts.join("");
}

async function contentLayout(slide: Slide, options: SlideRenderOptions): Promise<string> {
  const parts: string[] = [];
  const title = String(slide.title ?? "");
  if (showHeading(title)) parts.push(`<h2 class="p2u-heading">${h(title)}</h2>`);
  if (presence(slide.body)) parts.push(await markdownHtml(String(slide.body), options));
  for (const block of (slide.blocks ?? []) as Block[]) {
    parts.push(await blockHtml(slide, block, options));
  }
  return parts.join("");
}

function columns(kind: string, left: string, right: string, title: string): string {
  const parts: string[] = [];
  if (showHeading(title)) parts.push(`<h2 class="p2u-heading">${h(title)}</h2>`);
  parts.push(
    `<div class="p2u-columns p2u-columns--${kind}"><div class="p2u-column">${left}</div><div class="p2u-column">${right}</div></div>`,
  );
  return parts.join("");
}

function metricRow(title: string, blocks: Block[]): string {
  const cards = blocks
    .filter((block) => String(block.kind) === "metric")
    .map((block) => metricCard(block));
  const parts: string[] = [];
  if (showHeading(title)) parts.push(`<h2 class="p2u-heading">${h(title)}</h2>`);
  parts.push(`<div class="p2u-metrics">${cards.join("")}</div>`);
  return parts.join("");
}

function images(title: string, layout: string, blocks: Block[]): string {
  const grid = blocks
    .filter((block) => String(block.kind) === "image")
    .map((block) => imageHtml(block))
    .join("");
  const parts: string[] = [];
  if (showHeading(title)) parts.push(`<h2 class="p2u-heading">${h(title)}</h2>`);
  parts.push(`<div class="p2u-images p2u-images--${layout}">${grid}</div>`);
  return parts.join("");
}

function quoteLayout(title: string, blocks: Block[]): string {
  const block = blocks.find((candidate) => String(candidate.kind) === "quote");
  return block ? quoteBlock(block) : "";
}

async function slot(slide: Slide, name: string, options: SlideRenderOptions): Promise<string> {
  const value = slide[name];
  if (value && typeof value === "object" && !Array.isArray(value)) {
    const record = value as Record<string, unknown>;
    if (presence(record.kind)) return blockHtml(slide, record as Block, options);
    return markdownHtml(String(record.body ?? ""), options);
  }
  if (typeof value === "string") return markdownHtml(value, options);
  return "";
}

async function blockHtml(slide: Slide, block: Block | undefined, options: SlideRenderOptions): Promise<string> {
  if (!block || typeof block !== "object") return "";

  switch (String(block.kind)) {
    case "markdown":
      return markdownHtml(String(block.body ?? ""), options);
    case "code":
      return markdownHtml(fenced(presence(block.lang) ?? "text", block.source), options);
    case "diagram":
      return diagramHtml(slide, block, options);
    case "equation":
      return equationHtml(block);
    case "image":
      return imageHtml(block);
    case "quote":
      return quoteBlock(block);
    case "callout":
      return `<div class="p2u-callout p2u-callout--${h(presence(block.tone) ?? "note")}">${await markdownHtml(String(block.body ?? ""), options)}</div>`;
    case "metric":
      return metricCard(block);
    case "definition":
      return `<dl class="p2u-definition"><dt>${h(block.term)}</dt><dd>${await markdownHtml(String(block.body ?? ""), options)}</dd></dl>`;
    case "references":
      return markdownHtml(
        Array.isArray(block.items) ? block.items.map((item) => `- ${item}`).join("\n") : "",
        options,
      );
    case "table":
      return tableHtml(block);
    case "video":
      return `<div class="p2u-video"><a href="${h(block.url)}">${h(presence(block.title) ?? "Video")}</a></div>`;
    case "spacer":
      return `<hr class="p2u-spacer">`;
    case "notes-only":
      return "";
    default:
      return markdownHtml(String(block.body ?? ""), options);
  }
}

async function diagramHtml(slide: Slide, block: Block, options: SlideRenderOptions): Promise<string> {
  const source = String(block.source ?? "");
  if (!source.trim()) return "";

  const engine = String(presence(block.lang) ?? presence(block.engine) ?? "d2");
  const sketch = engine === "d2-sketch" || !!slide.sketch;
  const theme = options.dark ? 200 : 301;

  if (!options.assetStore) return clientDiagram(engine, source, sketch);

  try {
    if (engine === "d2" || engine === "d2-sketch" || engine === "tala") {
      const url = await options.assetStore({
        slide: String(slide.id),
        kind: "d2",
        source,
        options: { layout: "tala", theme, sketch },
      });
      return `<div class="p2u-diagram${sketch ? " p2u-diagram--sketch" : ""}"><img src="${h(url)}" alt=""></div>`;
    }

    if (engine === "typst" || engine === "typ") {
      const url = await options.assetStore({ slide: String(slide.id), kind: "typst", source, options: {} });
      return `<div class="p2u-diagram p2u-diagram--typst"><img src="${h(url)}" alt=""></div>`;
    }
  } catch {
    // Server renderer unavailable — fall back to client-side rendering.
    return clientDiagram(engine, source, sketch);
  }

  return markdownHtml(fenced(engine, source), options);
}

// Client-renderable markup. The exported document loads D2 (WASM) and KaTeX, so
// diagrams and equations work even when the render container is unavailable.
function clientDiagram(engine: string, source: string, sketch: boolean): string {
  if (engine === "d2" || engine === "d2-sketch" || engine === "tala") {
    return `<div class="p2u-d2" data-sketch="${sketch ? "true" : "false"}">${h(source)}</div>`;
  }
  if (engine === "typst" || engine === "typ") {
    return `<div class="p2u-typst" data-render="1">${h(source)}</div>`;
  }
  return `<pre class="p2u-code"><code>${h(source)}</code></pre>`;
}

function equationHtml(block: Block): string {
  const source = String(block.source ?? "");
  if (!source.trim()) return "";

  // Equations render client-side with KaTeX (display math), so no server render
  // is needed and they always appear.
  return `<div class="p2u-equation p2u-tex">\\[${h(source)}\\]</div>`;
}

function metricCard(block: Block): string {
  return `<div class="p2u-metric"><span class="p2u-metric__value">${h(block.value)}</span><span class="p2u-metric__label">${h(block.label)}</span></div>`;
}

function quoteBlock(block: Block): string {
  const attribution = presence(block.attribution);
  return `<blockquote class="p2u-quote"><p>${h(block.text)}</p>${attribution ? `<cite>— ${h(attribution)}</cite>` : ""}</blockquote>`;
}

function imageHtml(block: Block): string {
  const url = presence(block.url) ?? presence(block.src) ?? presence(block.image_url);
  if (!url) return "";

  const caption = presence(block.caption) ?? presence(block.alt);
  const figure = `<img src="${h(url)}" alt="${h(presence(block.alt) ?? caption ?? "")}" loading="lazy">`;
  return caption ? `<figure>${figure}<figcaption>${h(caption)}</figcaption></figure>` : figure;
}

function tableHtml(block: Block): string {
  if (presence(block.markdown)) return `<div class="p2u-md">${h(block.markdown)}</div>`;
  if (!Array.isArray(block.columns)) return "";

  const head = block.columns.map((column) => `<th>${h(column)}</th>`).join("");
  const rows = (Array.isArray(block.rows) ? block.rows : [])
    .map((row) => `<tr>${(Array.isArray(row) ? row : []).map((cell) => `<td>${h(cell)}</td>`).join("")}</tr>`)
    .join("");
  return `<table class="p2u-table"><thead><tr>${head}</tr></thead><tbody>${rows}</tbody></table>`;
}

function markdownHtml(text: string, options: SlideRenderOptions): Promise<string> {
  return markdownToHtml(text, { dark: options.dark, assetStore: options.assetStore });
}

function fenced(language: string, source: unknown): string {
  return "```" + language + "\n" + String(source ?? "") + "\n```";
}

function showHeading(title: string): boolean {
  return title.length > 0 && title !== "Untitled";
}

function h(value: unknown): string {
  return String(value ?? "")
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#39;");
}