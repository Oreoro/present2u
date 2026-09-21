// Bindings declared in wrangler.jsonc.
import type { RendererContainer } from "./render/container";

export interface Env {
  ASSETS: Fetcher;
  DB: D1Database;
  CACHE: KVNamespace;
  BLOBS: R2Bucket;
  WORKSPACE: DurableObjectNamespace;
  RENDERER: DurableObjectNamespace<RendererContainer>;
  EXPORTS: Queue;
  AI: Ai;
  BROWSER: Fetcher;
  P2U_VERSION: string;
  PUBLIC_ORIGIN: string;
  RENDER_TIMEOUT_MS: string;
  /** Set with `wrangler secret put SESSION_SECRET`. Falls back to a dev default. */
  SESSION_SECRET?: string;
}

export interface User {
  id: number;
  email: string;
  name: string | null;
  api_token: string;
  created_at: string;
  updated_at: string;
}

export interface DeckRow {
  id: number;
  user_id: number;
  slug: string;
  title: string;
  subtitle: string | null;
  author: string | null;
  theme: string | null;
  aspect: string;
  format: string;
  meta: string | null;
}

export interface SlideRow {
  id: number;
  deck_id: number;
  p2u_id: string | null;
  position: number;
  layout: string;
  title: string | null;
  notes: string | null;
  sketch: number;
  kind: string;
  theme: string | null;
  body: string | null;
  source: string | null;
  caption: string | null;
  image_url: string | null;
}

export interface SessionRow {
  id: number;
  email: string;
  token_hash: string;
  expires_at: string;
  consumed_at: string | null;
}