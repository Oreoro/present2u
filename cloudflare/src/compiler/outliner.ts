// Turns a manifest into an outline with per-slide metrics and a density budget,
// so a person or agent can see how many slides a talk will need and where it
// overflows before rendering anything. Port of p2u/outliner.rb.

import { Manifest } from "./manifest";
import type { Slide } from "./manifest";
import { DENSITY } from "./validator";
import { presence } from "./util";

export const ESTIMATED_SECONDS_PER_SLIDE = 45;

export interface SlideSummary {
  index: number;
  id: string;
  layout: string;
  title: string;
  words: number;
  bullets: number;
  code_lines: number;
  warnings: string[];
}

export interface Outline {
  title: string;
  slide_count: number;
  words: number;
  estimated_minutes: number;
  slides: SlideSummary[];
}

export function outline(manifest: Manifest | unknown): Outline {
  const parsed = manifest instanceof Manifest ? manifest : new Manifest(manifest);

  const slides = parsed.slides.map((slide, index) => slideSummary(slide, index));
  const words = slides.reduce((sum, slide) => sum + slide.words, 0);

  return {
    title: presence(parsed.deck.title) ?? "Untitled deck",
    slide_count: slides.length,
    words,
    estimated_minutes: Math.round((slides.length * ESTIMATED_SECONDS_PER_SLIDE) / 60),
    slides,
  };
}

function slideSummary(slide: Slide, index: number): SlideSummary {
  const text = textFor(slide);
  const words = (text.match(/\S+/g) ?? []).length;
  const bullets = (text.match(/^\s*(?:[-*+]|\d+\.)\s+/gm) ?? []).length;
  const codeLines = codeLinesFor(slide);

  return {
    index: index + 1,
    id: slide.id,
    layout: slide.layout,
    title: presence(slide.title) ?? "Untitled",
    words,
    bullets,
    code_lines: codeLines,
    warnings: warningsFor(words, bullets, codeLines),
  };
}

function textFor(slide: Slide): string {
  const parts = [String(slide.body ?? "")];
  for (const block of slide.blocks ?? []) {
    if (!block || typeof block !== "object") continue;

    parts.push(String((block as any).body ?? ""));
    parts.push(String((block as any).text ?? ""));
    if (String((block as any).kind ?? "") === "markdown") parts.push(String((block as any).source ?? ""));
  }
  return parts.join("\n");
}

function codeLinesFor(slide: Slide): number {
  let total = 0;
  for (const block of slide.blocks ?? []) {
    if (!block || typeof block !== "object") continue;
    if (String((block as any).kind ?? "") !== "code") continue;

    const source = String((block as any).source ?? "");
    total += source.length === 0 ? 0 : source.endsWith("\n") ? source.split(/\r?\n/).length - 1 : source.split(/\r?\n/).length;
  }
  return total;
}

function warningsFor(words: number, bullets: number, codeLines: number): string[] {
  const warnings: string[] = [];
  if (words > DENSITY.words) warnings.push(`dense (${words} words)`);
  if (bullets > DENSITY.bullets) warnings.push(`many bullets (${bullets})`);
  if (codeLines > DENSITY.codeLines) warnings.push(`long code (${codeLines} lines)`);
  return warnings;
}