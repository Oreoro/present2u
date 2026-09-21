// Content-addressed asset store. SVGs are keyed by the digest from digest.ts and
// live in R2 (BLOBS) with a KV metadata mirror and a D1 index. Identical source
// renders once and is then served from the edge forever.

import type { Env } from "../types";
import { digestFor } from "./digest";
import type { AssetRequest } from "./digest";
import { renderAsset } from "./container";

const IMMUTABLE = "public, max-age=31536000, immutable";

export function assetKey(digest: string): string {
  return `rendered/${digest}.svg`;
}

/** Returns the stable URL, rendering and caching on first use. */
export async function storeAsset(env: Env, request: AssetRequest): Promise<string> {
  const digest = await digestFor(request);
  const key = assetKey(digest);

  const existing = await env.BLOBS.head(key);
  if (existing) return `/rendered/${digest}.svg`;

  const svg = await renderAsset(env, request);
  await env.BLOBS.put(key, svg, {
    httpMetadata: { contentType: "image/svg+xml", cacheControl: IMMUTABLE },
  });

  await Promise.all([
    env.CACHE.put(`asset:${digest}`, JSON.stringify({ kind: request.kind, bytes: svg.length }), {
      expirationTtl: 60 * 60 * 24,
    }),
    env.DB.prepare("INSERT OR IGNORE INTO assets (digest, kind, r2_key, bytes) VALUES (?, ?, ?, ?)")
      .bind(digest, request.kind, key, svg.length)
      .run(),
  ]);

  return `/rendered/${digest}.svg`;
}

/** Reads a rendered SVG from R2, or null when it isn't cached yet. */
export async function getAsset(env: Env, digest: string): Promise<R2ObjectBody | null> {
  if (!/^[a-f0-9]{64}$/.test(digest)) return null;
  return env.BLOBS.get(assetKey(digest));
}