// Present2u Cloud — the edge Worker.
//
//   /api/*        JSON API + compiler contract
//   /api/decks/*  declarative decks (plan/apply)
//   /auth/*       magic-link sign-in
//   /rendered/*   content-addressed SVG assets
//   /mcp          remote MCP (Streamable HTTP)
//   /*            static site (ASSETS binding)

import { Hono } from "hono";
import { cors } from "hono/cors";
import type { Env } from "./types";
import { apiRoutes, RenderUnavailable } from "./routes/api";
import { deckRoutes } from "./routes/decks";
import { authRoutes } from "./routes/auth";
import { assetRoutes } from "./routes/assets";
import { exportRoutes } from "./routes/exports";
import { mcpRoutes } from "./routes/mcp";
import { runExport } from "./lib/export-job";

const app = new Hono<{ Bindings: Env }>();

// Browser-based agents and MCP clients need CORS on the machine surfaces.
const corsOptions = cors({
  origin: "*",
  allowHeaders: ["Authorization", "Content-Type"],
  allowMethods: ["GET", "POST", "OPTIONS"],
  maxAge: 86400,
});
app.use("/api/*", corsOptions);
app.use("/mcp", corsOptions);

app.route("/api/decks", deckRoutes);
app.route("/api/exports", exportRoutes);
app.route("/api", apiRoutes);
app.route("/auth", authRoutes);
app.route("/rendered", assetRoutes);
app.route("/mcp", mcpRoutes);

// D2 browser build + WASM, served same-origin with CORS so exported decks can
// import it from any location. See public/d2/.
app.get("/d2/*", async (c) => {
  const response = await c.env.ASSETS.fetch(c.req.raw);
  const headers = new Headers(response.headers);
  headers.set("access-control-allow-origin", "*");
  headers.set("cache-control", "public, max-age=86400");
  return new Response(response.body, { status: response.status, headers });
});

app.notFound((c) => c.env.ASSETS.fetch(c.req.raw));

app.onError((error, c) => {
  if (error instanceof RenderUnavailable) {
    return c.json(
      {
        error: "renderer_unavailable",
        message: error.message,
        hint: "The render container is starting or at capacity; retry shortly.",
      },
      503,
    );
  }
  console.error(error);
  return c.json({ error: "internal_error", message: error.message }, 500);
});

export { Workspace } from "./do/workspace";
export { RendererContainer } from "./render/container";

export default {
  fetch: app.fetch,

  // Keeps a render container instance warm so the first user request is fast.
  async scheduled(_event: ScheduledController, env: Env, ctx: ExecutionContext): Promise<void> {
    const { rendererHealth } = await import("./render/container");
    ctx.waitUntil(rendererHealth(env).catch(() => undefined));
  },

  // Async export jobs: render HTML/notes/PDF and drop the artifact in R2.
  async queue(batch: MessageBatch<{ exportId: number; deckId: number; format: string }>, env: Env): Promise<void> {
    for (const message of batch.messages) {
      try {
        await runExport(env, message.body.exportId, message.body.deckId, message.body.format);
        message.ack();
      } catch (error) {
        console.error("[present2u] export job failed", error);
        message.retry();
      }
    }
  },
};