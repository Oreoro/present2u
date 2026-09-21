// Deck API: list, read, import, plan and apply. Mirrors the Ruby Api::Decks
// controller and the declarative plan/apply endpoints.

import { Hono } from "hono";
import type { Env, User, SlideRow } from "../types";
import { authenticate } from "../auth/tokens";
import { Emitter, Parser, Planner, outline } from "../compiler";
import type { ExistingSlide, SlideAttributes } from "../compiler";
import { createDeck, getDeck, listDecks, listSlides, updateDeck, uniqueSlug } from "../store/db";
import { createExport } from "../store/exports";
import { replaceSlides } from "../store/db";
import { parameterize } from "../compiler/util";

export const deckRoutes = new Hono<{ Bindings: Env; Variables: { user: User } }>();

deckRoutes.use("*", async (c, next) => {
  const user = await authenticate(c.env, c.req.raw);
  if (!user) return c.json({ error: "Unauthorized" }, 401);
  c.set("user", user);
  await next();
});

deckRoutes.get("/", async (c) => {
  const decks = await listDecks(c.env, c.get("user").id);
  return c.json({
    decks: decks.map((deck) => ({
      id: deck.id,
      slug: deck.slug,
      title: deck.title,
      subtitle: deck.subtitle,
      theme: deck.theme,
      url: `${new URL(c.req.url).origin}/decks/${deck.slug}`,
    })),
  });
});

deckRoutes.post("/import", async (c) => {
  const user = c.get("user");
  const body = await c.req.json<{ source?: unknown; format?: string; slug?: string }>();
  const manifest = Parser.parse(body.source, body.format);
const emitter = new Emitter(manifest);
  const deck = emitter.deckAttributes;
  const slug = await uniqueSlug(c.env, user.id, body.slug ?? parameterize(deck.title));

  const deckId = await createDeck(c.env, user.id, {
    slug,
    title: deck.title,
    subtitle: deck.subtitle ?? null,
    author: deck.author ?? null,
    theme: deck.theme ?? null,
    format: String(manifest.deck.format ?? "markdown"),
  });

  await replaceSlides(c.env, deckId, toSlideRows(emitter.slides));

  return c.json({ id: deckId, slug, title: deck.title }, 201);
});

deckRoutes.get("/:id", async (c) => {
  const user = c.get("user");
  const deck = await getDeck(c.env, user.id, Number(c.req.param("id")));
  if (!deck) return c.json({ error: "Not found" }, 404);

  const slides = await listSlides(c.env, deck.id);
  return c.json({
    id: deck.id,
    slug: deck.slug,
    title: deck.title,
    slides: slides.map((slide) => ({
      id: slide.id,
      p2u_id: slide.p2u_id,
      layout: slide.layout,
      title: slide.title,
    })),
  });
});

deckRoutes.post("/:id/plan", async (c) => {
  const user = c.get("user");
  const deckId = Number(c.req.param("id"));
  const deck = await getDeck(c.env, user.id, deckId);
  if (!deck) return c.json({ error: "Not found" }, 404);

  const body = await c.req.json<{ source?: unknown; format?: string }>();
  const manifest = Parser.parse(body.source, body.format);
  const existing = await existingSlides(c.env, deckId);
  const planner = new Planner(manifest, existing, { id: deck.id, title: deck.title, slug: deck.slug });
  return c.json(planner.plan());
});

deckRoutes.post("/:id/apply", async (c) => {
  const user = c.get("user");
  const deckId = Number(c.req.param("id"));
  const deck = await getDeck(c.env, user.id, deckId);
  if (!deck) return c.json({ error: "Not found" }, 404);

  const body = await c.req.json<{ source?: unknown; format?: string }>();
  const manifest = Parser.parse(body.source, body.format);
  const emitter = new Emitter(manifest);
  const existing = await existingSlides(c.env, deckId);
  const plan = new Planner(manifest, existing, { id: deck.id, title: deck.title, slug: deck.slug }).plan();

  if (!plan.valid) {
    return c.json(
      { error: "invalid_manifest", diagnostics: plan.diagnostics.map((diagnostic) => diagnostic.toJSON()) },
      422,
    );
  }

  const desired = Object.fromEntries(emitter.slides.map((slide) => [slide.id, slide]));

  // Serialise per user through the Workspace DO so concurrent applies can't
  // interleave. The DO executes the plan by p2u_id, so ids survive and applies
  // are idempotent.
  const workspace = c.env.WORKSPACE.get(c.env.WORKSPACE.idFromName(String(user.id)));
  const response = await workspace.fetch("https://workspace/apply", {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ deckId, actions: plan.actions, desired }),
  });
  const result = await response.json();

  await updateDeck(c.env, deckId, {
    title: emitter.deckAttributes.title,
    subtitle: emitter.deckAttributes.subtitle ?? null,
    author: emitter.deckAttributes.author ?? null,
    theme: emitter.deckAttributes.theme ?? null,
  });

  return c.json({ applied: true, deck_id: deckId, summary: plan.summary, result, outline: outline(manifest) });
});

const EXPORT_FORMATS = ["html", "notes", "pdf"];

deckRoutes.post("/:id/export", async (c) => {
  const user = c.get("user");
  const deckId = Number(c.req.param("id"));
  const deck = await getDeck(c.env, user.id, deckId);
  if (!deck) return c.json({ error: "Not found" }, 404);

  const body = await c.req.json<{ format?: string }>().catch(() => ({ format: undefined }));
  const format = body.format ?? "html";
  if (!EXPORT_FORMATS.includes(format)) {
    return c.json({ error: `format must be one of ${EXPORT_FORMATS.join(", ")}` }, 400);
  }

  const id = await createExport(c.env, deckId, format);
  await c.env.EXPORTS.send({ exportId: id, deckId, format });

  return c.json({ id, status: "pending", url: `/api/exports/${id}` }, 202);
});

function toSlideRows(slides: SlideAttributes[]): Partial<SlideRow>[] {
  return slides.map((slide) => ({
    p2u_id: slide.id,
    layout: slide.layout,
    title: slide.title,
    notes: slide.notes ?? null,
    sketch: slide.sketch ? 1 : 0,
    kind: slide.type,
    theme: slide.theme ?? null,
    body: slide.body ?? null,
    source: slide.source ?? null,
    caption: slide.caption ?? null,
    image_url: slide.image_url ?? null,
  }));
}

async function existingSlides(env: Env, deckId: number): Promise<ExistingSlide[]> {
  const slides = await listSlides(env, deckId);
  return slides.map((slide) => ({
    id: slide.id,
    p2u_id: slide.p2u_id,
    title: slide.title,
    notes: slide.notes,
    sketch: slide.sketch === 1,
    layout: slide.layout,
    kind: slide.kind,
    theme: slide.theme,
    body: slide.body,
    source: slide.source,
    caption: slide.caption,
  }));
}