// Reports the toolchain ("stack") the compiler will use, with versions and
// availability. Powers GET /api/toolchain and the MCP p2u_doctor tool. The
// native versions come from the render container's /health endpoint.

import { layoutKeys } from "./layouts";
import { blockKeys, ENGINES } from "./blocks";
import { VERSION } from "./version";
import type { Env } from "../types";

export async function toolchainReport(env: Env): Promise<Record<string, unknown>> {
  let health: Record<string, any> = { available: false };
  try {
    // Lazy so the pure compiler core never loads the container module.
    const { rendererHealth } = await import("../render/container");
    health = await rendererHealth(env);
  } catch {
    health = { available: false };
  }

  return {
    p2u: { version: VERSION },
    markdown: { engine: "markdown-it", client: "markdown-it" },
    highlight: { engine: "highlight.js" },
    math: { engine: "katex" },
    typst: { engine: "typst", ...(health.typst ?? { available: false }) },
    diagram: {
      engine: "d2",
      layouts: ["tala", "elk", "dagre"],
      styles: ["default", "sketch"],
      ...(health.d2 ?? { available: false }),
    },
    latex: {
      engine: "pdflatex",
      binary: health.pdflatex ?? { available: false },
      converter: health.pdftocairo ?? { available: false },
    },
    chrome: health.chrome ?? { available: false },
    renderer: { available: !!health.available, image: health.image ?? null },
    layouts: layoutKeys(),
    blocks: blockKeys(),
    diagram_engines: ENGINES,
  };
}