// Rebuilds a P2U/1 manifest from stored deck + slide rows, so a deck can be
// re-exported without its original source. The inverse of the Emitter's mapping.

import type { Env, DeckRow } from "../types";
import { getDeck, listSlides } from "./db";

export async function deckManifest(env: Env, deckId: number): Promise<Record<string, unknown> | null> {
  const deck = await env.DB.prepare("SELECT * FROM decks WHERE id = ?").bind(deckId).first<DeckRow>();
  if (!deck) return null;

  const slides = await listSlides(env, deckId);

  return {
    p2u: 1,
    deck: {
      title: deck.title,
      subtitle: deck.subtitle ?? undefined,
      author: deck.author ?? undefined,
      theme: deck.theme ?? undefined,
      aspect: deck.aspect,
      format: deck.format,
    },
    slides: slides.map((slide) => {
      const base: Record<string, unknown> = {
        id: slide.p2u_id ?? `slide-${slide.id}`,
        layout: slide.layout,
        title: slide.title ?? undefined,
        notes: slide.notes ?? undefined,
      };

      if (slide.kind === "typst") {
        base.format = "typst";
        base.body = slide.source ?? "";
      } else if (slide.kind === "section") {
        base.body = slide.body ?? slide.title ?? "";
        base.theme = slide.theme ?? undefined;
      } else if (slide.kind === "image") {
        base.image_url = slide.image_url ?? undefined;
        base.caption = slide.caption ?? undefined;
      } else {
        base.body = slide.body ?? "";
      }

      return base;
    }),
  };
}

export async function deckExists(env: Env, userId: number, deckId: number): Promise<boolean> {
  return !!(await getDeck(env, userId, deckId));
}