// Fixed-window rate limiting backed by KV. Approximate (KV has no atomic
// increment) but enough to stop a runaway agent from hammering the render
// container. Keyed by API token when present, otherwise by client IP.

import type { Env } from "../types";

export interface RateLimitResult {
  ok: boolean;
  remaining: number;
  reset: number;
}

export async function rateLimit(
  env: Env,
  key: string,
  limit: number,
  windowSeconds: number,
): Promise<RateLimitResult> {
  const window = Math.floor(Date.now() / 1000 / windowSeconds);
  const bucket = `rl:${key}:${window}`;
  const current = Number((await env.CACHE.get(bucket)) ?? "0");
  const reset = (window + 1) * windowSeconds;

  if (current >= limit) return { ok: false, remaining: 0, reset };

  await env.CACHE.put(bucket, String(current + 1), { expirationTtl: windowSeconds * 2 });
  return { ok: true, remaining: limit - current - 1, reset };
}

export function clientKey(request: Request, token?: string | null): string {
  if (token) return `t:${token.slice(0, 16)}`;
  const ip = request.headers.get("cf-connecting-ip") ?? request.headers.get("x-forwarded-for") ?? "unknown";
  return `ip:${ip.split(",")[0]!.trim()}`;
}