// Executes a P2u::Planner plan against D1. Unlike a blind replace, this applies
// create/update/delete by stable `p2u_id`, so slide ids survive and repeated
// applies are idempotent — the same guarantee the Ruby Planner gives.

import type { Env } from "../types";
import type { Action, SlideAttributes } from "../compiler";

/** A generous starting position for freshly created slides; fixed by the reorder pass. */
const NEW_POSITION_BASE = 1_000_000;

export interface ApplyResult {
  applied: boolean;
  created: number;
  updated: number;
  deleted: number;
  reordered: boolean;
}

export async function applyPlan(
  env: Env,
  deckId: number,
  actions: Action[],
  desired: Record<string, SlideAttributes>,
): Promise<ApplyResult> {
  const mutations: D1PreparedStatement[] = [];
  const counts = { created: 0, updated: 0, deleted: 0, reordered: false };

  actions.forEach((action, index) => {
    switch (action.action) {
      case "create": {
        const slide = desired[action.slide!];
        if (!slide) return;
        mutations.push(insertSlide(env, deckId, slide, NEW_POSITION_BASE + index));
        counts.created += 1;
        break;
      }
      case "update": {
        const slide = desired[action.slide!];
        if (!slide || action.leaf_id === undefined) return;
        mutations.push(updateSlide(env, action.leaf_id, slide));
        counts.updated += 1;
        break;
      }
      case "delete": {
        if (action.leaf_id === undefined) return;
        mutations.push(env.DB.prepare("DELETE FROM slides WHERE id = ? AND deck_id = ?").bind(action.leaf_id, deckId));
        counts.deleted += 1;
        break;
      }
      case "reorder":
        counts.reordered = true;
        break;
    }
  });

  if (mutations.length > 0) await env.DB.batch(mutations);

  // Rewrite positions in manifest order so the deck reflects the plan exactly.
  const order = actions.find((action) => action.action === "reorder")?.slides;
  if (order?.length) {
    const positions = order.map((p2uId, index) =>
      env.DB.prepare("UPDATE slides SET position = ? WHERE deck_id = ? AND p2u_id = ?").bind(index, deckId, p2uId),
    );
    await env.DB.batch(positions);
  }

  return { applied: true, ...counts };
}

function insertSlide(env: Env, deckId: number, slide: SlideAttributes, position: number): D1PreparedStatement {
  return env.DB.prepare(
    `INSERT INTO slides (deck_id, p2u_id, position, layout, title, notes, sketch, kind, theme, body, source, caption, image_url)
     VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
  ).bind(
    deckId,
    slide.id,
    position,
    slide.layout,
    slide.title ?? null,
    slide.notes ?? null,
    slide.sketch ? 1 : 0,
    slide.type,
    slide.theme ?? null,
    slide.body ?? null,
    slide.source ?? null,
    slide.caption ?? null,
    slide.image_url ?? null,
  );
}

function updateSlide(env: Env, leafId: number, slide: SlideAttributes): D1PreparedStatement {
  return env.DB.prepare(
    `UPDATE slides SET
       p2u_id = ?, layout = ?, title = ?, notes = ?, sketch = ?, kind = ?, theme = ?,
       body = ?, source = ?, caption = ?, image_url = ?, updated_at = datetime('now')
     WHERE id = ?`,
  ).bind(
    slide.id,
    slide.layout,
    slide.title ?? null,
    slide.notes ?? null,
    slide.sketch ? 1 : 0,
    slide.type,
    slide.theme ?? null,
    slide.body ?? null,
    slide.source ?? null,
    slide.caption ?? null,
    slide.image_url ?? null,
    leafId,
  );
}