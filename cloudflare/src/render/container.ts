// The native render farm, as a Cloudflare Container behind a Durable Object.
// One warm instance per colo serves d2 / typst / pdflatex / headless Chrome.
//
// The container image is defined in ../container/Dockerfile and speaks a tiny
// HTTP contract (see ../container/server.mjs):
//
//   GET  /health                 -> { d2, typst, pdflatex, pdftocairo, chrome }
//   POST /render { kind, source, options } -> { svg }
//   POST /pdf    { html }        -> application/pdf
//
// Cold starts (first request after the instance sleeps) can exceed the Durable
// Object's wait, so calls are wrapped in a short retry/backoff. A cron trigger
// (see wrangler.jsonc) pings /health to keep an instance warm.

import { Container, getContainer } from "@cloudflare/containers";
import type { Env } from "../types";
import type { AssetRequest } from "./digest";

export class RendererContainer extends Container {
  override defaultPort = 8080;
  override sleepAfter = "30m";

  override async fetch(request: Request): Promise<Response> {
    return super.fetch(request);
  }
}

function stub(env: Env) {
  // Official singleton helper: lets the platform co-locate the DO with the
  // container app's instances (no manual location hint).
  return getContainer(env.RENDERER);
}

/** Retries a container call, since the first request after a cold start may fail. */
async function withRetry<T>(operation: () => Promise<T>, attempts = 4, delayMs = 5000): Promise<T> {
  let lastError: unknown;
  for (let attempt = 0; attempt < attempts; attempt++) {
    try {
      return await operation();
    } catch (error) {
      lastError = error;
      if (attempt < attempts - 1) await new Promise((resolve) => setTimeout(resolve, delayMs));
    }
  }
  throw lastError instanceof Error ? lastError : new Error(String(lastError));
}

export async function rendererHealth(env: Env): Promise<Record<string, any>> {
  // Single attempt: this is a probe (and the cron warm-up), not a user request.
  const response = await stub(env).fetch("http://renderer/health");
  if (!response.ok) throw new Error(`renderer /health failed: ${response.status}`);
  return response.json();
}

/** Renders a single asset and returns its SVG source. */
export async function renderAsset(env: Env, request: AssetRequest): Promise<string> {
  return withRetry(async () => {
    const response = await stub(env).fetch("http://renderer/render", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ kind: request.kind, source: request.source, options: request.options }),
    });

    if (!response.ok) {
      const detail = await response.text().catch(() => "");
      throw new Error(detail.trim() || `renderer failed (${response.status})`);
    }

    const data = (await response.json()) as { svg?: string };
    if (!data.svg) throw new Error("renderer returned no svg");
    return data.svg;
  });
}

/** Prints a self-contained deck to PDF via Cloudflare Browser Rendering. */
export async function renderPdf(env: Env, html: string): Promise<ArrayBuffer> {
  if (!env.BROWSER) throw new Error("Browser Rendering is not configured on this Worker");

  const puppeteer = await import("@cloudflare/puppeteer");
  const browser = await puppeteer.launch(env.BROWSER as unknown as Parameters<typeof puppeteer.launch>[0]);

  try {
    const page = await browser.newPage();
    // Give the page a real origin first, so ES-module imports of the D2/Typst
    // WASM resolve (setContent on about:blank has an opaque origin).
    await page.goto(`${env.PUBLIC_ORIGIN}/d2/blank.html`, { waitUntil: "domcontentloaded" }).catch(() => undefined);
    await page.setContent(html, { waitUntil: "networkidle0" });
    // Wait for the client-side D2/Typst/KaTeX renderers to finish before printing.
    await page.waitForFunction("window.__p2uRenderComplete === true", { timeout: 90000 }).catch(() => undefined);
    const pdf = await page.pdf({ printBackground: true, landscape: true, preferCSSPageSize: true });
    const bytes = new Uint8Array(pdf);
    return bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength) as ArrayBuffer;
  } finally {
    await browser.close();
  }
}