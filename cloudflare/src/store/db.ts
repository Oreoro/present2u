// D1 access layer. All SQL lives here so routes and the Workspace DO stay
// storage-agnostic. Mirrors the Book/Leaf/Leafable operations the Ruby
// Planner/DeckBuilder performed.

import type { Env, User, DeckRow, SlideRow, SessionRow } from "../types";
import { sha256Hex } from "../render/digest";

// --- Users --------------------------------------------------------------------

export async function findUserByToken(env: Env, token: string): Promise<User | null> {
  return env.DB.prepare("SELECT * FROM users WHERE api_token = ?").bind(token).first<User>();
}

export async function findUserByEmail(env: Env, email: string): Promise<User | null> {
  return env.DB.prepare("SELECT * FROM users WHERE email = ?").bind(email.toLowerCase()).first<User>();
}

export async function createUser(env: Env, email: string, name?: string): Promise<User> {
  const token = crypto.randomUUID().replace(/-/g, "") + crypto.randomUUID().replace(/-/g, "");
  await env.DB.prepare("INSERT INTO users (email, name, api_token) VALUES (?, ?, ?)")
    .bind(email.toLowerCase(), name ?? null, token)
    .run();
  const user = await findUserByEmail(env, email);
  if (!user) throw new Error("Failed to create user");
  return user;
}

export async function ensureUser(env: Env, email: string, name?: string): Promise<User> {
  return (await findUserByEmail(env, email)) ?? createUser(env, email, name);
}

// --- Decks --------------------------------------------------------------------

export async function listDecks(env: Env, userId: number): Promise<DeckRow[]> {
  const { results } = await env.DB.prepare("SELECT * FROM decks WHERE user_id = ? ORDER BY updated_at DESC")
    .bind(userId)
    .all<DeckRow>();
  return results ?? [];
}

export async function getDeck(env: Env, userId: number, deckId: number): Promise<DeckRow | null> {
  return env.DB.prepare("SELECT * FROM decks WHERE id = ? AND user_id = ?").bind(deckId, userId).first<DeckRow>();
}

export async function createDeck(env: Env, userId: number, deck: Partial<DeckRow>): Promise<number> {
  const result = await env.DB.prepare(
    `INSERT INTO decks (user_id, slug, title, subtitle, author, theme, aspect, format, meta)
     VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)`,
  )
    .bind(
      userId,
      deck.slug ?? "deck",
      deck.title ?? "Untitled deck",
      deck.subtitle ?? null,
      deck.author ?? null,
      deck.theme ?? null,
      deck.aspect ?? "16:9",
      deck.format ?? "markdown",
      deck.meta ?? null,
    )
    .run();
  return Number(result.meta.last_row_id);
}

export async function updateDeck(env: Env, deckId: number, patch: Partial<DeckRow>): Promise<void> {
  const fields = Object.keys(patch).filter((key) => key !== "id");
  if (fields.length === 0) return;

  const assignments = fields.map((field) => `${field} = ?`).join(", ");
  const values = fields.map((field) => (patch as Record<string, unknown>)[field]);
  await env.DB.prepare(`UPDATE decks SET ${assignments}, updated_at = datetime('now') WHERE id = ?`)
    .bind(...values, deckId)
    .run();
}

export async function deleteDeck(env: Env, deckId: number): Promise<void> {
  await env.DB.prepare("DELETE FROM decks WHERE id = ?").bind(deckId).run();
}

/** Finds a slug that is unique for the user (deck, deck-2, deck-3, …). */
export async function uniqueSlug(env: Env, userId: number, base: string): Promise<string> {
  const root = base || "deck";
  for (let attempt = 0; attempt < 50; attempt++) {
    const candidate = attempt === 0 ? root : `${root}-${attempt + 1}`;
    const clash = await env.DB.prepare("SELECT 1 FROM decks WHERE user_id = ? AND slug = ?")
      .bind(userId, candidate)
      .first();
    if (!clash) return candidate;
  }
  return `${root}-${crypto.randomUUID().slice(0, 8)}`;
}

// --- Slides -------------------------------------------------------------------

export async function listSlides(env: Env, deckId: number): Promise<SlideRow[]> {
  const { results } = await env.DB.prepare("SELECT * FROM slides WHERE deck_id = ? ORDER BY position ASC")
    .bind(deckId)
    .all<SlideRow>();
  return results ?? [];
}

/** Replaces the deck's slides atomically in the desired order. */
export async function replaceSlides(env: Env, deckId: number, slides: Partial<SlideRow>[]): Promise<void> {
  const statements = [env.DB.prepare("DELETE FROM slides WHERE deck_id = ?").bind(deckId)];

  slides.forEach((slide, position) => {
    statements.push(
      env.DB.prepare(
        `INSERT INTO slides (deck_id, p2u_id, position, layout, title, notes, sketch, kind, theme, body, source, caption, image_url)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
      ).bind(
        deckId,
        slide.p2u_id ?? null,
        position,
        slide.layout ?? "content",
        slide.title ?? null,
        slide.notes ?? null,
        slide.sketch ?? 0,
        slide.kind ?? "markdown",
        slide.theme ?? null,
        slide.body ?? null,
        slide.source ?? null,
        slide.caption ?? null,
        slide.image_url ?? null,
      ),
    );
  });

  await env.DB.batch(statements);
}

// --- Sessions -----------------------------------------------------------------

export async function createSession(env: Env, email: string, ttlSeconds = 900): Promise<string> {
  const token = crypto.randomUUID().replace(/-/g, "") + crypto.randomUUID().replace(/-/g, "");
  const tokenHash = await sha256Hex(token);

  // Store expiry in SQLite's own format so `expires_at > datetime('now')` compares correctly.
  await env.DB.prepare("INSERT INTO sessions (email, token_hash, expires_at) VALUES (?, ?, datetime('now', ?))")
    .bind(email.toLowerCase(), tokenHash, `+${ttlSeconds} seconds`)
    .run();

  return token;
}

export async function consumeSession(env: Env, token: string): Promise<string | null> {
  const tokenHash = await sha256Hex(token);
  const session = await env.DB.prepare(
    "SELECT * FROM sessions WHERE token_hash = ? AND consumed_at IS NULL AND expires_at > datetime('now')",
  )
    .bind(tokenHash)
    .first<SessionRow>();

  if (!session) return null;

  await env.DB.prepare("UPDATE sessions SET consumed_at = datetime('now') WHERE id = ?").bind(session.id).run();
  return session.email;
}