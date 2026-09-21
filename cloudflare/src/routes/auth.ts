// Magic-link sign-in routes.

import { Hono } from "hono";
import type { Env } from "../types";
import { startMagicLink, completeMagicLink } from "../auth/magic-link";
import { findUserByEmail } from "../store/db";
import { sessionCookie, signSession } from "../auth/tokens";

export const authRoutes = new Hono<{ Bindings: Env }>();

authRoutes.post("/start", async (c) => {
  const body = await c.req.json<{ email?: string }>().catch(() => ({ email: undefined }));
  if (!body.email) return c.json({ error: "email is required" }, 400);

  try {
    const result = await startMagicLink(c.env, body.email);
    return c.json(result);
  } catch (error) {
    return c.json({ error: (error as Error).message }, 400);
  }
});

authRoutes.get("/callback", async (c) => {
  const token = c.req.query("token");
  if (!token) return c.json({ error: "token is required" }, 400);

  const email = await completeMagicLink(c.env, token);
  if (!email) return c.json({ error: "Invalid or expired link" }, 400);

  const user = await findUserByEmail(c.env, email);
  if (!user) return c.json({ error: "User not found" }, 404);

  const session = await signSession(c.env, user.api_token);
  return new Response(null, {
    status: 302,
    headers: {
      location: "/",
      "set-cookie": sessionCookie(session, c.env.PUBLIC_ORIGIN),
    },
  });
});