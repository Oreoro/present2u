// Validates a Manifest and returns a list of Diagnostic. Schema and semantic
// checks plus a slide-density budget, so agents get actionable feedback rather
// than an exception. Port of p2u/validator.rb.

import { Manifest } from "./manifest";
import type { Slide } from "./manifest";
import { Diagnostic } from "./diagnostic";
import { isBlank, isPresent, presence } from "./util";
import { layoutKey, fetchLayout, layoutKeys } from "./layouts";
import type { LayoutDefinition } from "./layouts";
import { blockKey, fetchBlock, blockKeys, ENGINES } from "./blocks";
import { VERSION } from "./version";

export const THEMES = ["writebook", "black", "blue", "green", "magenta", "orange", "violet", "white"];
export const ASPECTS = ["16:9", "4:3", "16:10"];

export const DENSITY = {
  words: 220,
  bullets: 12,
  codeLines: 40,
  wordsPerSlideTarget: 90,
};

export class Validator {
  private readonly manifest: Manifest;
  private diagnostics: Diagnostic[] = [];

  constructor(manifest: Manifest) {
    this.manifest = manifest;
  }

  static validate(manifest: Manifest): Diagnostic[] {
    return new Validator(manifest).validate();
  }

  validate(): Diagnostic[] {
    this.validateVersion();
    this.validateDeck();
    this.validateSlides();
    return this.diagnostics;
  }

  private error(code: string, message: string, options: Record<string, unknown> = {}): void {
    this.add("error", code, message, options);
  }
  private warn(code: string, message: string, options: Record<string, unknown> = {}): void {
    this.add("warning", code, message, options);
  }
  private info(code: string, message: string, options: Record<string, unknown> = {}): void {
    this.add("info", code, message, options);
  }

  private add(severity: string, code: string, message: string, options: Record<string, unknown>): void {
    this.diagnostics.push(
      new Diagnostic(severity, code, message, {
        slide: options.slide as string | undefined,
        path: options.path as string | undefined,
        hint: options.hint as string | undefined,
      }),
    );
  }

  private validateVersion(): void {
    const version = this.manifest.version;

    if (isBlank(version)) {
      this.warn("missing_version", `No \`p2u\` version declared; assuming ${VERSION}.`, { path: "p2u" });
    } else if (version !== VERSION) {
      this.error("unsupported_version", `Unsupported p2u version ${JSON.stringify(version)}.`, {
        path: "p2u",
        hint: `This compiler implements P2U/${VERSION}.`,
      });
    }
  }

  private validateDeck(): void {
    const deck = this.manifest.deck;

    if (!deck || typeof deck !== "object") {
      this.error("invalid_deck", "`deck` must be a mapping.", { path: "deck" });
      return;
    }

    if (isBlank(deck.title)) {
      this.warn("missing_title", "Deck has no `title`; it will be published as “Untitled deck”.", {
        path: "deck.title",
      });
    }
    this.validateTheme(deck.theme);
    this.validateAspect(deck.aspect);
    this.validateDefaults(deck.defaults);
  }

  private validateTheme(theme: unknown): void {
    const name = theme && typeof theme === "object" ? (theme as any).preset : theme;
    if (isBlank(name)) return;

    if (!THEMES.includes(String(name))) {
      this.error("unknown_theme", `Unknown theme ${JSON.stringify(name)}.`, {
        path: "deck.theme",
        hint: `Known themes: ${THEMES.join(", ")}.`,
      });
    }
  }

  private validateAspect(aspect: unknown): void {
    if (isBlank(aspect) || ASPECTS.includes(String(aspect))) return;

    this.error("unknown_aspect", `Unknown aspect ratio ${JSON.stringify(aspect)}.`, {
      path: "deck.aspect",
      hint: `Known ratios: ${ASPECTS.join(", ")}.`,
    });
  }

  private validateDefaults(defaults: unknown): void {
    if (!defaults || typeof defaults !== "object") return;

    const layout = (defaults as any).layout;
    if (isPresent(layout) && !layoutKey(layout)) {
      this.error("unknown_layout", `Unknown default layout ${JSON.stringify(layout)}.`, {
        path: "deck.defaults.layout",
        hint: `Known layouts: ${layoutKeys().join(", ")}.`,
      });
    }
  }

  private validateSlides(): void {
    const slides = this.manifest.slides;

    if (slides.length === 0) {
      this.error("no_slides", "The manifest has no slides.", { path: "slides" });
      return;
    }

    const seen = new Set<string>();
    slides.forEach((slide, index) => {
      if (!slide || typeof slide !== "object") {
        this.error("invalid_slide", "Slide must be a mapping.", { path: `slides[${index}]` });
        return;
      }

      const slideId = slide.id as string;
      if (seen.has(slideId)) {
        this.error("duplicate_slide_id", `Slide id ${JSON.stringify(slideId)} is used more than once.`, {
          slide: slideId,
          path: `slides[${index}].id`,
        });
      }
      seen.add(slideId);

      this.validateSlide(slide, index);
    });
  }

  private validateSlide(slide: Slide, index: number): void {
    const slideId = slide.id;
    const layout = slide.layout;

    if (!layoutKey(layout)) {
      this.error("unknown_layout", `Unknown layout ${JSON.stringify(layout)}.`, {
        slide: slideId,
        path: `slides[${index}].layout`,
        hint: `Known layouts: ${layoutKeys().join(", ")}.`,
      });
      return;
    }

    const definition = fetchLayout(layout);
    this.validateRequiredFields(slide, definition, index);
    this.validateContent(slide, definition, index);
    this.validateSlots(slide, definition, index);
    this.validateBlocks(slide, definition, index);
    this.validateDensity(slide, index);
  }

  private validateRequiredFields(slide: Slide, definition: LayoutDefinition, index: number): void {
    for (const field of definition.required ?? []) {
      if (isPresent(slide[field])) continue;

      this.error("missing_field", `Layout ${JSON.stringify(slide.layout)} requires \`${field}\`.`, {
        slide: slide.id,
        path: `slides[${index}].${field}`,
      });
    }
  }

  private validateContent(slide: Slide, definition: LayoutDefinition, index: number): void {
    if (definition.content !== "required") return;

    const hasBody = isPresent(slide.body);
    const hasBlocks = (slide.blocks ?? []).some((block) => serializeCandidate(block));

    if (!hasBody && !hasBlocks) {
      this.error("missing_content", `Layout ${JSON.stringify(slide.layout)} requires \`body\` or \`blocks\`.`, {
        slide: slide.id,
        path: `slides[${index}]`,
      });
    }
  }

  private validateSlots(slide: Slide, definition: LayoutDefinition, index: number): void {
    for (const slot of definition.slots ?? []) {
      if (isPresent(slide[slot])) continue;

      this.error("missing_slot", `Layout ${JSON.stringify(slide.layout)} requires slot \`${slot}\`.`, {
        slide: slide.id,
        path: `slides[${index}].${slot}`,
      });
    }
  }

  private validateBlocks(slide: Slide, definition: LayoutDefinition, index: number): void {
    const blocks = slide.blocks;
    if (isBlank(blocks)) return;

    if (!Array.isArray(blocks)) {
      this.error("invalid_blocks", "`blocks` must be a list.", {
        slide: slide.id,
        path: `slides[${index}].blocks`,
      });
      return;
    }

    const allowed = definition.allowedBlocks;
    if (definition.requireBlock && !blocks.some((block) => serializeCandidate(block))) {
      this.error("missing_block", `Layout ${JSON.stringify(slide.layout)} requires at least one block.`, {
        slide: slide.id,
        path: `slides[${index}].blocks`,
      });
    }

    blocks.forEach((block, blockIndex) => {
      const path = `slides[${index}].blocks[${blockIndex}]`;

      if (!block || typeof block !== "object" || Array.isArray(block)) {
        this.error("invalid_block", "Block must be a mapping.", { slide: slide.id, path });
        return;
      }

      const kind = String((block as any).kind ?? "");
      if (!blockKey(kind)) {
        this.error("unknown_block", `Unknown block kind ${JSON.stringify(kind)}.`, {
          slide: slide.id,
          path: `${path}.kind`,
          hint: `Known blocks: ${blockKeys().join(", ")}.`,
        });
        return;
      }

      if (allowed && !allowed.includes(kind)) {
        this.error("block_not_allowed", `Layout ${JSON.stringify(slide.layout)} does not allow a ${JSON.stringify(kind)} block.`, {
          slide: slide.id,
          path: `${path}.kind`,
          hint: `Allowed here: ${allowed.join(", ")}.`,
        });
      }

      this.validateBlock(block as Record<string, unknown>, kind, path);
    });
  }

  private validateBlock(block: Record<string, unknown>, kind: string, path: string): void {
    const definition = fetchBlock(kind);

    for (const field of definition.required ?? []) {
      if (isPresent(block[field])) continue;

      this.error("missing_block_field", `Block ${JSON.stringify(kind)} requires \`${field}\`.`, {
        path: `${path}.${field}`,
      });
    }

    if (definition.any && !definition.any.some((field) => isPresent(block[field]))) {
      this.error("missing_block_field", `Block ${JSON.stringify(kind)} requires one of ${definition.any.join(", ")}.`, {
        path,
      });
    }

    if (kind === "diagram") {
      const engine = String(presence(block.lang) ?? presence(block.engine) ?? "d2");
      if (!ENGINES.includes(engine)) {
        this.error("unknown_engine", `Unknown diagram engine ${JSON.stringify(engine)}.`, {
          path: `${path}.lang`,
          hint: `Known engines: ${ENGINES.join(", ")}.`,
        });
      }
    }
  }

  private validateDensity(slide: Slide, index: number): void {
    const text = this.densityText(slide);
    const words = (text.match(/\S+/g) ?? []).length;
    const bullets = (text.match(/^\s*(?:[-*+]|\d+\.)\s+/gm) ?? []).length;
    const codeLines = this.codeLineCount(slide);

    if (words > DENSITY.words) {
      this.warn("slide_density", `Slide has ${words} words (budget ${DENSITY.words}).`, {
        slide: slide.id,
        path: `slides[${index}]`,
        hint: "Consider splitting into two slides.",
      });
    }

    if (bullets > DENSITY.bullets) {
      this.warn("too_many_bullets", `Slide has ${bullets} bullet points (budget ${DENSITY.bullets}).`, {
        slide: slide.id,
        path: `slides[${index}]`,
      });
    }

    if (codeLines > DENSITY.codeLines) {
      this.warn("code_density", `Slide has ${codeLines} lines of code (budget ${DENSITY.codeLines}).`, {
        slide: slide.id,
        path: `slides[${index}]`,
        hint: "Consider a `full-code` slide or splitting the listing.",
      });
    }
  }

  private densityText(slide: Slide): string {
    const parts = [String(slide.body ?? "")];
    for (const block of slide.blocks ?? []) {
      if (!block || typeof block !== "object") continue;

      parts.push(String((block as any).body ?? ""));
      parts.push(String((block as any).text ?? ""));
      if (String((block as any).kind ?? "") === "markdown") parts.push(String((block as any).source ?? ""));
    }
    return parts.join("\n");
  }

  private codeLineCount(slide: Slide): number {
    let total = 0;
    for (const block of slide.blocks ?? []) {
      if (!block || typeof block !== "object") continue;
      if (String((block as any).kind ?? "") !== "code") continue;

      total += lineCount(String((block as any).source ?? ""));
    }
    return total;
  }
}

function serializeCandidate(block: unknown): boolean {
  if (!block || typeof block !== "object") return false;
  const value = block as Record<string, unknown>;
  return isPresent(value.body) || isPresent(value.source) || isPresent(value.kind);
}

/** Ruby String#lines.size — counts a trailing line without a final newline too. */
function lineCount(source: string): number {
  if (source.length === 0) return 0;
  const lines = source.split(/\r?\n/).length;
  return source.endsWith("\n") ? lines - 1 : lines;
}