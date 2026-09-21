// Runs an export job: rebuild the manifest, render the artifact, store it in R2
// and update the job row. Called by the queue consumer.

import type { Env } from "../types";
import { Exporter } from "../compiler";
import { deckManifest } from "../store/manifest";
import { storeAsset } from "../render/assets";
import { exportContentType, exportKey, updateExport } from "../store/exports";

export async function runExport(env: Env, exportId: number, deckId: number, format: string): Promise<void> {
  await updateExport(env, exportId, { status: "running" });

  try {
    const manifest = await deckManifest(env, deckId);
    if (!manifest) throw new Error("Deck not found");

    const exporter = new Exporter(manifest);
    const store = (request: Parameters<typeof storeAsset>[1]) => storeAsset(env, request);

    let body: string | ArrayBuffer;
    if (format === "notes") {
      body = exporter.toNotes();
    } else if (format === "pdf") {
      body = await exporter.toPdf(env, store);
    } else {
      body = await exporter.toHtml(env, store);
    }

    const key = exportKey(deckId, exportId, format);
    await env.BLOBS.put(key, body, { httpMetadata: { contentType: exportContentType(format) } });
    await updateExport(env, exportId, { status: "done", r2_key: key });
  } catch (error) {
    await updateExport(env, exportId, { status: "failed", error: (error as Error).message });
    throw error;
  }
}