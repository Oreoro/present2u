// Export job records. The queue consumer writes artifacts to R2 and updates
// these rows; the API reports status and streams the artifact.

import type { Env } from "../types";

export interface ExportRow {
  id: number;
  deck_id: number;
  format: string;
  status: "pending" | "running" | "done" | "failed";
  r2_key: string | null;
  error: string | null;
  created_at: string;
  updated_at: string;
}

export async function createExport(env: Env, deckId: number, format: string): Promise<number> {
  const result = await env.DB.prepare("INSERT INTO exports (deck_id, format) VALUES (?, ?)")
    .bind(deckId, format)
    .run();
  return Number(result.meta.last_row_id);
}

export async function getExport(env: Env, id: number): Promise<ExportRow | null> {
  return env.DB.prepare("SELECT * FROM exports WHERE id = ?").bind(id).first<ExportRow>();
}

export async function updateExport(
  env: Env,
  id: number,
  patch: Partial<Pick<ExportRow, "status" | "r2_key" | "error">>,
): Promise<void> {
  const fields = Object.keys(patch) as (keyof typeof patch)[];
  if (fields.length === 0) return;

  const assignments = fields.map((field) => `${field} = ?`).join(", ");
  const values = fields.map((field) => patch[field] ?? null);
  await env.DB.prepare(`UPDATE exports SET ${assignments}, updated_at = datetime('now') WHERE id = ?`)
    .bind(...values, id)
    .run();
}

export function exportKey(deckId: number, exportId: number, format: string): string {
  const extension = format === "html" ? "html" : format === "notes" ? "md" : "pdf";
  return `exports/${deckId}/${exportId}.${extension}`;
}

export function exportContentType(format: string): string {
  if (format === "html") return "text/html; charset=utf-8";
  if (format === "notes") return "text/markdown; charset=utf-8";
  return "application/pdf";
}