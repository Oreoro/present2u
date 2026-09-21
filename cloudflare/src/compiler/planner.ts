// Declarative plan/apply. Compares a desired manifest with an existing deck
// (matched by stable slide `p2u_id`, with a positional fallback) and produces an
// ordered list of create/update/delete/reorder actions. Port of p2u/planner.rb.
//
// The diff is pure; `apply` is left to the store layer (D1) so this module stays
// testable without a database.

import { Manifest } from "./manifest";
import type { Slide } from "./manifest";
import { Diagnostic } from "./diagnostic";
import { Validator } from "./validator";
import { Emitter } from "./emitter";
import type { SlideAttributes } from "./emitter";
import { layoutKey, resolveLayout } from "./layouts";

export interface ExistingSlide {
  id: number;
  p2u_id: string | null;
  title: string | null;
  notes: string | null;
  sketch: boolean;
  layout: string | null;
  kind: string;
  body: string | null;
  source: string | null;
  caption: string | null;
  theme?: string | null;
}

export type ActionName = "create" | "update" | "delete" | "reorder";

export interface Action {
  action: ActionName;
  slide?: string;
  leaf_id?: number;
  changes?: Record<string, [unknown, unknown]>;
  slides?: string[];
}

export interface PlanResult {
  valid: boolean;
  deck: { id?: number; title?: string; slug?: string };
  summary: Record<string, number>;
  actions: Action[];
  diagnostics: Diagnostic[];
}

export class Planner {
  private readonly manifest: Manifest;
  private readonly existing: ExistingSlide[];
  private readonly desired: Record<string, SlideAttributes>;
  private matches: Record<string, ExistingSlide> = {};

  constructor(
    manifest: Manifest | unknown,
    existing: ExistingSlide[],
    deck: { id?: number; title?: string; slug?: string } = {},
  ) {
    this.manifest = manifest instanceof Manifest ? manifest : new Manifest(manifest);
    this.existing = existing;
    this.deck = deck;
    this.desired = Object.fromEntries(new Emitter(this.manifest).slides.map((slide) => [slide.id, slide]));
  }

  private readonly deck: { id?: number; title?: string; slug?: string };

  plan(): PlanResult {
    const diagnostics = Validator.validate(this.manifest);
    const actions = diagnostics.some((diagnostic) => diagnostic.isError) ? [] : this.buildActions();

    const summary: Record<string, number> = {};
    for (const action of actions) summary[action.action] = (summary[action.action] ?? 0) + 1;

    return {
      valid: !diagnostics.some((diagnostic) => diagnostic.isError),
      deck: this.deck,
      summary,
      actions,
      diagnostics,
    };
  }

  /** The ordered write plan the store layer should execute. */
  get writePlan(): Action[] {
    return this.plan().actions;
  }

  private computeMatches(): Record<string, ExistingSlide> {
    const desiredSlides = this.manifest.slides;
    const matched: Record<string, ExistingSlide> = {};

    for (const slide of this.existing) {
      if (!slide.p2u_id) continue;
      if (desiredSlides.some((desired) => desired.id === slide.p2u_id)) matched[slide.p2u_id] = slide;
    }

    const unmatchedDesired = desiredSlides.filter((slide) => !(slide.id in matched));
    const matchedIds = new Set(Object.values(matched).map((slide) => slide.id));
    const unmatchedExisting = this.existing.filter((slide) => !matchedIds.has(slide.id));

    unmatchedDesired.forEach((slide, index) => {
      const candidate = unmatchedExisting[index];
      if (candidate) matched[slide.id] = candidate;
    });

    return matched;
  }

  private buildActions(): Action[] {
    this.matches = this.computeMatches();
    const actions: Action[] = [];

    for (const slide of this.manifest.slides) {
      const existing = this.matches[slide.id];
      if (existing) {
        const changes = this.changesFor(existing, this.desired[slide.id]!);
        if (Object.keys(changes).length > 0) {
          actions.push({ action: "update", slide: slide.id, leaf_id: existing.id, changes });
        }
      } else {
        actions.push({ action: "create", slide: slide.id });
      }
    }

    const matchedIds = new Set(Object.values(this.matches).map((slide) => slide.id));
    for (const slide of this.existing) {
      if (matchedIds.has(slide.id)) continue;
      actions.push({ action: "delete", slide: slide.p2u_id ?? slide.title ?? undefined, leaf_id: slide.id });
    }

    if (this.reorderNeeded()) {
      actions.push({ action: "reorder", slides: this.manifest.slides.map((slide) => slide.id) });
    }

    return actions;
  }

  private reorderNeeded(): boolean {
    if (this.manifest.slides.some((slide) => !this.matches[slide.id])) return true;

    const matchedIds = new Set(Object.values(this.matches).map((slide) => slide.id));
    const current = this.existing.filter((slide) => matchedIds.has(slide.id)).map((slide) => slide.id);
    const expected = this.manifest.slides
      .map((slide) => this.matches[slide.id]?.id)
      .filter((id): id is number => id !== undefined);
    return current.join(",") !== expected.join(",");
  }

  private changesFor(existing: ExistingSlide, desired: SlideAttributes): Record<string, [unknown, unknown]> {
    const changes: Record<string, [unknown, unknown]> = {};
    compare(changes, "title", existing.title, desired.title);
    compare(changes, "notes", existing.notes, desired.notes);
    compare(changes, "sketch", existing.sketch, desired.sketch);
    compare(changes, "layout", existing.layout ?? resolveLayout(existing.kind), desired.layout);
    this.compareLeafable(changes, existing, desired);
    return changes;
  }

  private compareLeafable(
    changes: Record<string, [unknown, unknown]>,
    existing: ExistingSlide,
    desired: SlideAttributes,
  ): void {
    // `kind` is the runtime slide type produced by the Emitter:
    // content | section | image | typst.
    switch (String(existing.kind)) {
      case "content":
        compare(changes, "body", existing.body, desired.body);
        break;
      case "section":
        compare(changes, "body", existing.body, desired.body);
        compare(changes, "theme", existing.theme, desired.theme ?? null);
        break;
      case "image":
        compare(changes, "caption", existing.caption, desired.caption);
        break;
      case "typst":
        compare(changes, "source", existing.source, desired.source);
        break;
    }
  }
}

function compare(changes: Record<string, [unknown, unknown]>, field: string, current: unknown, desired: unknown): void {
  if (String(current ?? "").trim() === String(desired ?? "").trim()) return;
  changes[field] = [current ?? null, desired ?? null];
}

/** Re-export so callers can check a layout name without importing layouts. */
export { layoutKey };