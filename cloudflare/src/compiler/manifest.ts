// A parsed, structurally-normalised manifest. Normalisation is intentionally
// lenient about the legacy type/body shape so every existing deck and API
// payload keeps compiling; the Validator still reports on the result.
// Port of p2u/manifest.rb.

import { deepStringify, parameterize, presence } from "./util";
import { resolveLayout, DEFAULT } from "./layouts";

export interface Slide {
  layout: string;
  id: string;
  blocks?: Block[];
  [key: string]: unknown;
}

export interface Block {
  kind: string;
  [key: string]: unknown;
}

export class Manifest {
  readonly data: Record<string, any>;

  constructor(data: unknown) {
    this.data = normalize(data);
  }

  get version(): string | undefined {
    return presence(this.data.p2u ?? this.data.version);
  }

  get deck(): Record<string, any> {
    return (this.data.deck as Record<string, any>) ?? {};
  }

  get slides(): Slide[] {
    return Array.isArray(this.data.slides) ? this.data.slides : [];
  }

  dig(...keys: string[]): unknown {
    let cursor: any = this.data;
    for (const key of keys) {
      if (cursor == null || typeof cursor !== "object") return undefined;
      cursor = cursor[key];
    }
    return cursor;
  }

  toJSON(): Record<string, any> {
    return this.data;
  }
}

function normalize(data: unknown): Record<string, any> {
  let hash = deepStringify(data);
  if (!hash || typeof hash !== "object" || Array.isArray(hash)) hash = {};

  const deck = hash.deck && typeof hash.deck === "object" && !Array.isArray(hash.deck) ? hash.deck : {};
  let slides = hash.slides ?? deck.slides;
  if (!Array.isArray(slides)) slides = [];

  hash.deck = deck;
  hash.slides = slides.map((slide: unknown, index: number) => normalizeSlide(slide, index));
  return hash;
}

function normalizeSlide(slide: unknown, index: number): Slide {
  let value = deepStringify(slide);
  if (!value || typeof value !== "object" || Array.isArray(value)) value = {};

  value.layout = resolveLayout(presence(value.layout) ?? presence(value.type) ?? DEFAULT);
  value.id = presence(value.id) ?? deriveId(value, index);
  if ("blocks" in value) value.blocks = normalizeBlocks(value.blocks);
  return value as Slide;
}

function normalizeBlocks(blocks: unknown): unknown {
  if (!Array.isArray(blocks)) return blocks;

  return blocks.map((block) => {
    let value = deepStringify(block);
    if (!value || typeof value !== "object" || Array.isArray(value)) value = {};
    value.kind = String(presence(value.kind) ?? presence(value.type) ?? "markdown").trim().toLowerCase();
    return value;
  });
}

function deriveId(slide: Record<string, any>, index: number): string {
  const base = presence(slide.title) ?? presence(slide.layout) ?? "slide";
  return `${parameterize(base) || "slide"}-${index + 1}`;
}