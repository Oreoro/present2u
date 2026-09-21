// Renders a manifest to distributable artifacts: a self-contained HTML deck,
// speaker notes as Markdown, and a PDF (via the render container's headless
// Chrome). Port of p2u/exporter.rb — `toHtml` delegates to Render::Document,
// which is scaffolded in src/render/document.ts.

import { Manifest } from "./manifest";
import { presence } from "./util";
import { renderDocument } from "../render/document";
import type { DocumentSlide } from "../render/document";
import { renderSlide } from "../render/slide";
import type { Env } from "../types";

/** Layouts that already render their own title, so no separate kicker is drawn. */
export const TITLED_LAYOUTS = [
  "title",
  "section",
  "content",
  "two-column",
  "compare",
  "code-split",
  "metric-row",
  "image",
  "image-grid",
  "references",
  "recap",
  "qa",
  "end",
];

export class Exporter {
  private readonly manifest: Manifest;

  constructor(manifest: Manifest | unknown) {
    this.manifest = manifest instanceof Manifest ? manifest : new Manifest(manifest);
  }

  get deckTitle(): string {
    return presence(this.manifest.deck.title) ?? "Untitled deck";
  }

  async toHtml(env: Env, assetStore?: (request: any) => Promise<string>): Promise<string> {
    return renderDocument(env, {
      deck: this.manifest.deck,
      slides: await this.slideEntries(assetStore),
      title: this.deckTitle,
    });
  }

  toNotes(): string {
    const lines = [`# ${this.deckTitle}`, ""];

    this.manifest.slides.forEach((slide, index) => {
      lines.push(`## ${index + 1}. ${presence(slide.title) ?? "Untitled"}`);
      lines.push("");
      lines.push(presence(slide.notes) ?? "_No speaker notes._");
      lines.push("");
    });

    return lines.join("\n");
  }

  async toPdf(env: Env, assetStore?: (request: any) => Promise<string>): Promise<ArrayBuffer> {
    const html = await this.toHtml(env, assetStore);
    const { renderPdf } = await import("../render/container");
    return renderPdf(env, html);
  }

  filename(extension: string): string {
    const base = this.deckTitle
      .toLowerCase()
      .replace(/[^a-z0-9]+/g, "-")
      .replace(/^-+|-+$/g, "");
    return `${base || "deck"}.${extension}`;
  }

  private get deckDark(): boolean {
    const theme = this.manifest.deck.theme;
    const name = theme && typeof theme === "object" ? String((theme as any).preset ?? "") : String(theme ?? "");
    return name !== "white";
  }

  private get deckFormat(): string {
    return String(presence(this.manifest.deck.format) ?? presence(this.manifest.deck.engine) ?? "markdown");
  }

  private async slideEntries(assetStore?: (request: any) => Promise<string>): Promise<DocumentSlide[]> {
    const dark = this.deckDark;
    const format = this.deckFormat;

    const entries: DocumentSlide[] = [];
    for (const slide of this.manifest.slides) {
      const layout = String(slide.layout);
      const typst = String(presence(slide.format) ?? format) === "typst";
      entries.push({
        html: await renderSlide(slide, { dark, format: typst ? "typst" : "markdown", assetStore }),
        layout,
        kicker: typst || TITLED_LAYOUTS.includes(layout) ? null : (presence(slide.title) ?? null),
        notes: (slide.notes as string | undefined) ?? null,
      });
    }
    return entries;
  }
}