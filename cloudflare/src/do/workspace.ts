// Per-user Durable Object: the "local memory" layer. One instance per user
// holds the working set (parsed deck + last plan) in memory, debounces writes to
// D1, and serialises apply so concurrent agents cannot interleave
// create/update/delete. See CLOUD.md §6.

import type { Env } from "../types";
import type { Action, SlideAttributes } from "../compiler";
import { listSlides } from "../store/db";
import { applyPlan } from "../store/apply";

interface CachedDeck {
  slides: unknown[];
  updatedAt: number;
}

export class Workspace implements DurableObject {
  private readonly state: DurableObjectState;
  private readonly env: Env;
  private readonly cache = new Map<number, CachedDeck>();
  private queue: Promise<unknown> = Promise.resolve();

  constructor(state: DurableObjectState, env: Env) {
    this.state = state;
    this.env = env;
  }

  async fetch(request: Request): Promise<Response> {
    const url = new URL(request.url);

    switch (url.pathname) {
      case "/state":
        return Response.json({ decks: this.cache.size });
      case "/invalidate": {
        const deckId = Number(url.searchParams.get("deck"));
        this.cache.delete(deckId);
        return Response.json({ ok: true });
      }
      case "/apply":
        return this.serialize(() => this.apply(request));
      default:
        return new Response("Not found", { status: 404 });
    }
  }

  /** Runs work strictly in order — the serialisation guarantee for apply. */
  private serialize<T>(work: () => Promise<T>): Promise<Response> {
    const next = this.queue.then(work).then(
      (value) => Response.json(value as unknown as Record<string, unknown>),
      (error) => Response.json({ error: String(error) }, { status: 500 }),
    );
    this.queue = next;
    return next;
  }

  private async apply(request: Request): Promise<Record<string, unknown>> {
    const body = (await request.json()) as {
      deckId: number;
      actions?: Action[];
      desired?: Record<string, SlideAttributes>;
    };
    if (!body?.deckId) throw new Error("deckId is required");

    // The route planned against the snapshot it fetched; the DO guarantees only
    // one apply mutates a given deck at a time, then executes the plan by id.
    const result = await applyPlan(this.env, body.deckId, body.actions ?? [], body.desired ?? {});
    this.cache.delete(body.deckId);
    return result as unknown as Record<string, unknown>;
  }

  /** Reads a deck's slides through the per-user cache. */
  async slides(deckId: number): Promise<unknown[]> {
    const cached = this.cache.get(deckId);
    if (cached) return cached.slides;

    const slides = await listSlides(this.env, deckId);
    this.cache.set(deckId, { slides, updatedAt: Date.now() });
    return slides;
  }
}