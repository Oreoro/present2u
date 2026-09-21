// Export job status and artifact download.

import { Hono } from "hono";
import type { Env, User } from "../types";
import { authenticate } from "../auth/tokens";
import { getDeck } from "../store/db";
import { exportContentType, getExport } from "../store/exports";

export const exportRoutes = new Hono<{ Bindings: Env; Variables: { user: User } }>();

exportRoutes.use("*", async (c, next) => {
  const user = await authenticate(c.env, c.req.raw);
  if (!user) return c.json({ error: "Unauthorized" }, 401);
  c.set("user", user);
  await next();
});

exportRoutes.get("/:id", async (c) => {
  const row = await ownedExport(c.env, c.get("user"), Number(c.req.param("id")));
  if (!row) return c.json({ error: "Not found" }, 404);

  return c.json({
    id: row.id,
    deck_id: row.deck_id,
    format: row.format,
    status: row.status,
    url: row.status === "done" ? `/api/exports/${row.id}/download` : null,
    error: row.error,
  });
});

exportRoutes.get("/:id/download", async (c) => {
  const row = await ownedExport(c.env, c.get("user"), Number(c.req.param("id")));
  if (!row || row.status !== "done" || !row.r2_key) return c.json({ error: "Not found" }, 404);

  const object = await c.env.BLOBS.get(row.r2_key);
  if (!object) return c.json({ error: "Artifact missing" }, 404);

  return new Response(object.body, {
    headers: {
      "content-type": exportContentType(row.format),
      "content-disposition": `attachment; filename="${row.format === "notes" ? "notes.md" : `deck.${row.format}`}"`,
    },
  });
});

async function ownedExport(env: Env, user: User, id: number) {
  const row = await getExport(env, id);
  if (!row) return null;

  const deck = await getDeck(env, user.id, row.deck_id);
  return deck ? row : null;
}