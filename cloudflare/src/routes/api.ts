// Compiler API: validate/compile, outline, compose, render, export, and the
// contract endpoints (/schema, /toolchain, /templates). Ports the Ruby
// Api::* controllers onto the edge compiler.

import { Hono } from "hono";
import type { Context } from "hono";
import type { Env } from "../types";
import {
  Compiler,
  Exporter,
  Parser,
  compose,
  outline,
  toolchainReport,
  VERSION,
  SERVER_NAME,
  SERVER_VERSION,
} from "../compiler";
import { storeAsset } from "../render/assets";
import { renderAsset } from "../render/container";
import { rateLimit, clientKey } from "../lib/rate-limit";
import { bearerToken } from "../auth/tokens";
import type { AssetRequest } from "../render/digest";

export const apiRoutes = new Hono<{ Bindings: Env }>();

/** Applies a per-minute rate limit to an expensive endpoint. */
async function guard(c: Context<{ Bindings: Env }>, name: string, limit: number): Promise<Response | null> {
  const key = clientKey(c.req.raw, bearerToken(c.req.raw));
  const result = await rateLimit(c.env, `${name}:${key}`, limit, 60);
  if (result.ok) return null;

  const retryAfter = Math.max(1, result.reset - Math.floor(Date.now() / 1000));
  c.header("retry-after", String(retryAfter));
  return c.json({ error: "rate_limited", retry_after: retryAfter }, 429);
}

apiRoutes.get("/", async (c) => {
  const origin = new URL(c.req.url).origin;
  return c.json({
    name: SERVER_NAME,
    version: SERVER_VERSION,
    p2u: VERSION,
    description: "Present2u Cloud — the P2U/1 compiler at the edge.",
    endpoints: {
      schema: `${origin}/api/schema`,
      toolchain: `${origin}/api/toolchain`,
      templates: `${origin}/api/templates`,
      compile: `${origin}/api/compile`,
      outline: `${origin}/api/outline`,
      compose: `${origin}/api/compose`,
      render: `${origin}/api/render`,
      export: `${origin}/api/export`,
      decks: `${origin}/api/decks`,
      mcp: `${origin}/mcp`,
    },
  });
});

apiRoutes.get("/schema", (c) => c.redirect("/schema.json", 307));
apiRoutes.get("/health", (c) => c.json({ ok: true, name: SERVER_NAME, version: SERVER_VERSION, p2u: VERSION }));
apiRoutes.get("/toolchain", async (c) => c.json(await toolchainReport(c.env)));
apiRoutes.get("/templates", (c) => c.redirect("/templates.json", 307));

apiRoutes.post("/compile", async (c) => {
  const limited = await guard(c, "compile", 60);
  if (limited) return limited;

  const body = await c.req.json<{ source?: unknown; format?: string; render?: boolean }>();
  const result = await Compiler.compile(body.source, {
    format: body.format,
    render: !!body.render,
    store: (request) => storeAsset(c.env, request),
  });

  return c.json({
    valid: result.valid,
    version: VERSION,
    manifest: result.manifest?.toJSON() ?? null,
    diagnostics: result.diagnostics.map((diagnostic) => diagnostic.toJSON()),
    plan: result.plan,
  });
});

apiRoutes.post("/outline", async (c) => {
  const limited = await guard(c, "outline", 60);
  if (limited) return limited;

  const body = await c.req.json<{ source?: unknown; format?: string }>();
  const manifest = Parser.parse(body.source, body.format);
  return c.json(outline(manifest));
});

apiRoutes.post("/compose", async (c) => {
  const limited = await guard(c, "compose", 10);
  if (limited) return limited;

  const body = await c.req.json<{
    prompt?: string;
    sources?: string[];
    slides?: number;
    theme?: string;
    provider?: string;
  }>();

  const result = await compose(c.env, {
    prompt: body.prompt ?? "",
    sources: body.sources,
    slides: body.slides,
    theme: body.theme,
    provider: body.provider,
  });

  return c.json({
    valid: result.diagnostics.every((diagnostic) => !diagnostic.isError),
    provider: result.provider,
    note: result.note,
    manifest: result.manifest?.toJSON() ?? null,
    diagnostics: result.diagnostics.map((diagnostic) => diagnostic.toJSON()),
  });
});

apiRoutes.post("/render", async (c) => {
  const limited = await guard(c, "render", 30);
  if (limited) return limited;

  const body = await c.req.json<{ kind?: string; source?: string; options?: Record<string, unknown> }>();
  if (!body.source) return c.json({ error: "source is required" }, 400);

  const request: AssetRequest = {
    slide: "api",
    kind: (body.kind as AssetRequest["kind"]) ?? "d2",
    source: body.source,
    options: body.options ?? {},
  };

  const url = await storeAsset(c.env, request).catch((error: Error) => {
    throw new RenderUnavailable(error.message);
  });
  return c.json({ url, digest: url.split("/").pop()?.replace(".svg", "") });
});

apiRoutes.post("/export", async (c) => {
  const limited = await guard(c, "export", 10);
  if (limited) return limited;

  const body = await c.req.json<{ source?: unknown; format?: string; to?: string }>();
  const exporter = new Exporter(Parser.parse(body.source, body.format));
  const store = (request: AssetRequest) => storeAsset(c.env, request);

  if (body.to === "notes") {
    return c.json({ to: "notes", content: exporter.toNotes() });
  }

  if (body.to === "pdf") {
    const pdf = await exporter.toPdf(c.env, store).catch((error: Error) => {
      throw new RenderUnavailable(error.message);
    });
    return new Response(pdf, { headers: { "content-type": "application/pdf" } });
  }

  return c.json({ to: "html", content: await exporter.toHtml(c.env, store) });
});

// Exposed for the CLI's `p2u render` and internal use.
export async function renderOne(env: Env, request: AssetRequest): Promise<string> {
  return renderAsset(env, request);
}

/** Signals that the render container isn't available (cold start / capacity). */
export class RenderUnavailable extends Error {
  override name = "RenderUnavailable";
}