-- Present2u Cloud — initial schema.
-- Mirrors the Rails Book -> Leaf -> Leafable shape as three flat tables so the
-- edge can query without a polymorphic join. `slides.p2u_id` is the stable slide
-- identity that makes plan/apply idempotent (formerly leaves.p2u_id).

CREATE TABLE users (
  id         INTEGER PRIMARY KEY AUTOINCREMENT,
  email      TEXT NOT NULL UNIQUE,
  name       TEXT,
  api_token  TEXT NOT NULL UNIQUE,
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  updated_at TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE TABLE decks (
  id         INTEGER PRIMARY KEY AUTOINCREMENT,
  user_id    INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  slug       TEXT NOT NULL,
  title      TEXT NOT NULL DEFAULT 'Untitled deck',
  subtitle   TEXT,
  author     TEXT,
  theme      TEXT,
  aspect     TEXT NOT NULL DEFAULT '16:9',
  format     TEXT NOT NULL DEFAULT 'markdown',
  meta       TEXT,
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  updated_at TEXT NOT NULL DEFAULT (datetime('now')),
  UNIQUE (user_id, slug)
);

CREATE INDEX decks_user_idx ON decks (user_id, updated_at DESC);

-- kind: markdown | typst | section | picture  (the Leafable discriminator)
CREATE TABLE slides (
  id         INTEGER PRIMARY KEY AUTOINCREMENT,
  deck_id    INTEGER NOT NULL REFERENCES decks(id) ON DELETE CASCADE,
  p2u_id     TEXT,
  position   INTEGER NOT NULL DEFAULT 0,
  layout     TEXT NOT NULL DEFAULT 'content',
  title      TEXT,
  notes      TEXT,
  sketch     INTEGER NOT NULL DEFAULT 0,
  kind       TEXT NOT NULL DEFAULT 'markdown',
  theme      TEXT,
  body       TEXT,
  source     TEXT,
  caption    TEXT,
  image_url  TEXT,
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  updated_at TEXT NOT NULL DEFAULT (datetime('now')),
  UNIQUE (deck_id, p2u_id)
);

CREATE INDEX slides_deck_position_idx ON slides (deck_id, position);

CREATE TABLE sessions (
  id          INTEGER PRIMARY KEY AUTOINCREMENT,
  email       TEXT NOT NULL,
  token_hash  TEXT NOT NULL UNIQUE,
  expires_at  TEXT NOT NULL,
  consumed_at TEXT,
  created_at  TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX sessions_email_idx ON sessions (email, expires_at DESC);

-- Metadata for content-addressed SVGs / exports; bytes live in R2 (BLOBS).
CREATE TABLE assets (
  digest    TEXT PRIMARY KEY,
  kind      TEXT NOT NULL,
  r2_key    TEXT NOT NULL,
  bytes     INTEGER NOT NULL DEFAULT 0,
  toolchain TEXT,
  created_at TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE TABLE exports (
  id         INTEGER PRIMARY KEY AUTOINCREMENT,
  deck_id    INTEGER NOT NULL REFERENCES decks(id) ON DELETE CASCADE,
  format     TEXT NOT NULL,
  status     TEXT NOT NULL DEFAULT 'pending',
  r2_key     TEXT,
  error      TEXT,
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  updated_at TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX exports_deck_idx ON exports (deck_id, created_at DESC);