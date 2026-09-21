// The content block vocabulary of P2U/1. Blocks are the typed units that make up
// a slide body. They compile down to Markdown fences the renderer understands
// (d2, d2-sketch, latex, code). Port of writebook/app/models/p2u/blocks.rb.

export interface BlockDefinition {
  summary: string;
  required?: string[];
  any?: string[];
  defaults?: Record<string, string>;
}

export const DEFINITIONS: Record<string, BlockDefinition> = {
  markdown: { summary: "Inline Markdown", required: ["body"] },
  code: { summary: "Highlighted code", required: ["source"], defaults: { lang: "text" } },
  diagram: { summary: "Diagram (D2, Mermaid…)", required: ["source"], defaults: { lang: "d2" } },
  equation: { summary: "LaTeX equation", required: ["source"] },
  table: { summary: "Data table" },
  chart: { summary: "Chart from data" },
  image: { summary: "Image", any: ["url", "src", "image_url"] },
  video: { summary: "Video embed", required: ["url"] },
  metric: { summary: "Metric or KPI", required: ["value", "label"] },
  quote: { summary: "Pull quote", required: ["text"] },
  callout: { summary: "Callout", required: ["body"] },
  definition: { summary: "Term definition", required: ["term", "body"] },
  references: { summary: "Reference list", required: ["items"] },
  "notes-only": { summary: "Speaker-only content", required: ["body"] },
  spacer: { summary: "Vertical spacer" },
};

/** Diagram engines the compiler knows how to route. */
export const ENGINES = ["d2", "d2-sketch", "tala", "typst", "mermaid", "graphviz", "tikz"];

export function blockKey(name: unknown): boolean {
  return String(name ?? "").trim().toLowerCase() in DEFINITIONS;
}

export function fetchBlock(name: unknown): BlockDefinition {
  const key = String(name ?? "").trim().toLowerCase();
  const def = DEFINITIONS[key];
  if (!def) throw new Error(`Unknown block kind: ${key}`);
  return def;
}

export function blockKeys(): string[] {
  return Object.keys(DEFINITIONS);
}