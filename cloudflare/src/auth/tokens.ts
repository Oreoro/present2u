// Authentication: bearer API tokens for agents and the CLI, and an HMAC-signed
// session cookie for the browser.

import type { Env, User } from "../types";
import { findUserByToken } from "../store/db";

export const SESSION_COOKIE = "p2u_session";

export function bearerToken(request: Request): string | null {
  const header = request.headers.get("authorization") ?? "";
  const match = header.match(/^Bearer\s+(.+)$/i);
  return match ? match[1]!.trim() : null;
}

export function cookieValue(request: Request, name: string): string | null {
  const cookie = request.headers.get("cookie") ?? "";
  for (const part of cookie.split(";")) {
    const [key, ...rest] = part.trim().split("=");
    if (key === name) return decodeURIComponent(rest.join("="));
  }
  return null;
}

/** Resolves the acting user from a bearer token or session cookie. */
export async function authenticate(env: Env, request: Request): Promise<User | null> {
  const token = bearerToken(request);
  if (token) return findUserByToken(env, token);

  const session = cookieValue(request, SESSION_COOKIE);
  if (!session) return null;

  const payload = await verifySession(env, session);
  if (!payload) return null;

  return findUserByToken(env, payload.token);
}

export async function signSession(env: Env, token: string, ttlSeconds = 60 * 60 * 24 * 30): Promise<string> {
  const expires = Math.floor(Date.now() / 1000) + ttlSeconds;
  const payload = `${token}.${expires}`;
  const signature = await hmac(env, payload);
  return `${payload}.${signature}`;
}

export async function verifySession(env: Env, session: string): Promise<{ token: string } | null> {
  const parts = session.split(".");
  if (parts.length !== 3) return null;

  const [token, expires, signature] = parts as [string, string, string];
  if (Number(expires) < Math.floor(Date.now() / 1000)) return null;

  const expected = await hmac(env, `${token}.${expires}`);
  if (!timingSafeEqual(expected, signature)) return null;

  return { token };
}

export function sessionCookie(session: string, origin: string): string {
  const secure = origin.startsWith("https") ? " Secure;" : "";
  return `${SESSION_COOKIE}=${encodeURIComponent(session)}; Path=/; HttpOnly;${secure} SameSite=Lax; Max-Age=${60 * 60 * 24 * 30}`;
}

async function hmac(env: Env, payload: string): Promise<string> {
  const secret = env.SESSION_SECRET ?? "dev-insecure-session-secret";
  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const signature = await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(payload));
  return [...new Uint8Array(signature)].map((byte) => byte.toString(16).padStart(2, "0")).join("");
}

function timingSafeEqual(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let index = 0; index < a.length; index++) diff |= a.charCodeAt(index) ^ b.charCodeAt(index);
  return diff === 0;
}