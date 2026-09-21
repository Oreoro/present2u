// Content-addressed asset serving: GET /rendered/<sha256>.svg from R2.

import { Hono } from "hono";
import type { Env } from "../types";
import { getAsset } from "../render/assets";

export const assetRoutes = new Hono<{ Bindings: Env }>();

assetRoutes.get("/:file", async (c) => {
  const file = c.req.param("file");
  const match = file.match(/^([a-f0-9]{64})\.svg$/);
  if (!match) return c.notFound();

  const object = await getAsset(c.env, match[1]!);
  if (!object) return c.notFound();

  return new Response(object.body, {
    headers: {
      "content-type": "image/svg+xml",
      "cache-control": "public, max-age=31536000, immutable",
      etag: object.httpEtag,
    },
  });
});