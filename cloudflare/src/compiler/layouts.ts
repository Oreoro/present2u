// The slide layout vocabulary of P2U/1. Each layout declares what it needs, what
// content it accepts and which block kinds it allows. This registry is the
// single source of truth used by the validator and published in the JSON Schema.
// Port of writebook/app/models/p2u/layouts.rb.

export interface LayoutDefinition {
  summary: string;
  required?: string[];
  slots?: string[];
  allowedBlocks?: string[];
  requireBlock?: boolean;
  content?: "required" | "optional";
}

export const DEFINITIONS: Record<string, LayoutDefinition> = {
  title: { summary: "Deck or talk title", required: ["title"], content: "optional" },
  section: { summary: "Section divider", required: ["title"], content: "optional" },
  content: { summary: "Markdown content", content: "required" },
  "two-column": { summary: "Two content columns", slots: ["left", "right"], content: "optional" },
  compare: { summary: "Side-by-side comparison", slots: ["left", "right"], content: "optional" },
  "code-split": { summary: "Code beside prose", slots: ["code", "prose"], content: "optional" },
  "full-code": { summary: "Full-bleed code", allowedBlocks: ["code"], requireBlock: true, content: "optional" },
  diagram: { summary: "Diagram focus", allowedBlocks: ["diagram"], requireBlock: true, content: "optional" },
  equation: { summary: "Equation focus", allowedBlocks: ["equation"], requireBlock: true, content: "optional" },
  table: { summary: "Data table", allowedBlocks: ["table", "markdown"], content: "optional" },
  "metric-row": { summary: "KPI cards", allowedBlocks: ["metric"], requireBlock: true, content: "optional" },
  timeline: { summary: "Timeline or roadmap", content: "optional" },
  quote: { summary: "Pull quote", content: "optional" },
  image: { summary: "Image slide", allowedBlocks: ["image"], content: "optional" },
  "image-grid": { summary: "Image gallery", allowedBlocks: ["image"], requireBlock: true, content: "optional" },
  references: { summary: "Bibliography", content: "optional" },
  recap: { summary: "Summary", content: "optional" },
  qa: { summary: "Questions", content: "optional" },
  end: { summary: "Closing slide", content: "optional" },
};

/** Legacy DeckBuilder slide types map onto layouts. */
export const ALIASES: Record<string, string> = {
  divider: "section",
  page: "content",
  picture: "image",
  typst: "content",
  "": "content",
};

export const DEFAULT = "content";

export function resolveLayout(name: unknown): string {
  const key = String(name ?? "").trim().toLowerCase();
  return ALIASES[key] ?? key;
}

export function layoutKey(name: unknown): boolean {
  return resolveLayout(name) in DEFINITIONS;
}

export function fetchLayout(name: unknown): LayoutDefinition {
  const key = resolveLayout(name);
  const def = DEFINITIONS[key];
  if (!def) throw new Error(`Unknown layout: ${key}`);
  return def;
}

export function layoutKeys(): string[] {
  return Object.keys(DEFINITIONS);
}

export function isLegacyLayout(name: unknown): boolean {
  return String(name ?? "").trim().toLowerCase() in ALIASES;
}