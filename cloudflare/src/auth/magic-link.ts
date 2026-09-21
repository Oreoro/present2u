// Email magic-link sign-in. Stores a short-lived hashed token and emails a link.
// The mail transport is pluggable: Cloudflare Email Service, Resend, or a
// dev-mode console log when neither is configured.

import type { Env } from "../types";
import { createSession, consumeSession, ensureUser } from "../store/db";

export interface MagicLinkDeps {
  send?: (env: Env, to: string, link: string) => Promise<void>;
}

export async function startMagicLink(env: Env, email: string, deps: MagicLinkDeps = {}): Promise<{ sent: boolean; link?: string }> {
  const normalized = email.trim().toLowerCase();
  if (!normalized.includes("@")) throw new Error("A valid email address is required");

  const token = await createSession(env, normalized);
  const link = `${env.PUBLIC_ORIGIN}/auth/callback?token=${encodeURIComponent(token)}`;

  const send = deps.send ?? sendMagicLinkEmail;
  try {
    await send(env, normalized, link);
  } catch {
    // In dev there may be no mail transport; surface the link instead.
    return { sent: false, link };
  }

  return { sent: true };
}

export async function completeMagicLink(env: Env, token: string): Promise<string | null> {
  const email = await consumeSession(env, token);
  if (!email) return null;
  await ensureUser(env, email);
  return email;
}

async function sendMagicLinkEmail(env: Env, to: string, link: string): Promise<void> {
  // TODO: wire Cloudflare Email Service (send_email binding) or Resend.
  // Until then, log in dev so the flow is testable.
  if (env.PUBLIC_ORIGIN.includes("localhost")) {
    console.log(`[present2u] magic link for ${to}: ${link}`);
    return;
  }
  throw new Error("No mail transport configured");
}