// Turns a natural-language request into a valid P2U/1 manifest. Uses Workers AI
// when available, validating and repairing the result against the compiler's
// diagnostics; otherwise falls back to a deterministic outline built from the
// prompt and any supplied source notes. Port of p2u/composer.rb.

import { Manifest } from "./manifest";
import { Parser } from "./parser";
import { Validator } from "./validator";
import { Diagnostic, ParseError } from "./diagnostic";
import { presence } from "./util";
import { layoutKeys } from "./layouts";
import { blockKeys, ENGINES } from "./blocks";
import type { Env } from "../types";

export const DEFAULT_SLIDES = 10;
export const MAX_REPAIRS = 2;

export interface ComposeOptions {
  prompt: string;
  sources?: string[];
  slides?: number | null;
  theme?: string | null;
  provider?: string | null;
}

export interface ComposeResult {
  manifest: Manifest | null;
  diagnostics: Diagnostic[];
  provider: string;
  note?: string;
}

export async function compose(env: Env, options: ComposeOptions): Promise<ComposeResult> {
  const provider = presence(options.provider)?.toLowerCase();
  if (provider !== "heuristic" && env.AI) {
    try {
      return await llmCompose(env, options);
    } catch (error) {
      return heuristicResult(options, "heuristic", `LLM unavailable: ${(error as Error).message}`);
    }
  }

  return heuristicResult(options, "heuristic");
}

function heuristicResult(options: ComposeOptions, provider: string, note?: string): ComposeResult {
  const manifest = new Manifest(heuristic(options));
  return { manifest, diagnostics: Validator.validate(manifest), provider, note };
}

async function llmCompose(env: Env, options: ComposeOptions): Promise<ComposeResult> {
  let manifest: Manifest | null = null;
  let diagnostics: Diagnostic[] = [];

  for (let attempt = 0; attempt <= MAX_REPAIRS; attempt++) {
    const response = await env.AI.run("@cf/meta/llama-3.1-8b-instruct", {
      messages: [
        { role: "system", content: systemPrompt() },
        { role: "user", content: userPrompt(options, manifest, diagnostics) },
      ],
    });

    const content = typeof response === "object" && response && "response" in response ? String((response as any).response) : String(response);
    manifest = extractManifest(content);
    diagnostics = Validator.validate(manifest);
    if (!diagnostics.some((diagnostic) => diagnostic.isError)) break;
  }

  return { manifest, diagnostics, provider: "llm" };
}

function systemPrompt(): string {
  return [
    "You are the present2u compiler's author. Reply with ONLY a P2U/1 manifest (YAML or JSON).",
    "No prose, no code fences.",
    "",
    "Shape:",
    "  p2u: 1",
    "  deck: { title, subtitle?, author?, theme? }",
    "  slides: [ { id?, layout, title?, subtitle?, body?, blocks?, notes?, theme?, sketch? } ]",
    "",
    `Layouts: ${layoutKeys().join(", ")}.`,
    `Block kinds: ${blockKeys().join(", ")} (diagram langs: ${ENGINES.join(", ")}).`,
    "`body` is Markdown and may contain inline $math$, fenced ```d2, ```d2-sketch and ```latex.",
    "Use diagram/equation/code-split/metric-row/two-column where they genuinely help.",
    "Include speaker notes on content slides. Aim for a clear narrative.",
  ].join("\n");
}

function userPrompt(options: ComposeOptions, previous: Manifest | null, diagnostics: Diagnostic[]): string {
  const parts: string[] = ["Create a technical presentation."];
  if (presence(options.prompt)) parts.push(`Topic / request: ${options.prompt}.`);
  parts.push(`Target about ${targetCount(options)} slides.`);
  if (presence(options.theme)) parts.push(`Theme: ${options.theme}.`);
  if (options.sources?.length) parts.push(`Base it on these notes:\n\n${options.sources.join("\n\n---\n\n")}`);

  if (previous && diagnostics.some((diagnostic) => diagnostic.isError)) {
    parts.push("Your previous manifest was invalid. Fix these and return the corrected manifest only:");
    parts.push(
      diagnostics
        .filter((diagnostic) => diagnostic.isError)
        .map((diagnostic) => `- [${diagnostic.code}] ${diagnostic.message}`)
        .join("\n"),
    );
  }

  return parts.join("\n\n");
}

function extractManifest(content: string): Manifest {
  let text = content.trim().replace(/^```[a-zA-Z]*[ \t]*\r?\n?/, "").replace(/\r?\n?```\s*$/, "");
  try {
    return Parser.parse(text);
  } catch (error) {
    if (!(error instanceof ParseError)) throw error;
    const fenced = content.match(/```[a-zA-Z]*[ \t]*\r?\n([\s\S]*?)```/);
    if (!fenced) throw error;
    return Parser.parse(fenced[1]);
  }
}

// --- Deterministic fallback ---------------------------------------------------

const DEFAULT_SECTIONS = [
  { title: "Context", body: "Why this matters and the problem we're solving." },
  { title: "Background", body: "Prior art and the landscape." },
  { title: "Approach", body: "The core idea and how it works." },
  { title: "Architecture", body: "Components, data flow and interfaces." },
  { title: "Implementation", body: "Key decisions, code and trade-offs." },
  { title: "Results", body: "Measurements, benchmarks and evidence." },
  { title: "Evaluation", body: "How we know it works." },
  { title: "Limitations", body: "What is hard, and what comes next." },
  { title: "Conclusion", body: "Recap and takeaways." },
];

function heuristic(options: ComposeOptions): Record<string, unknown> {
  const topic = topicOf(options.prompt);
  const count = targetCount(options);
  const body = bodySlides(options, topic, count);

  let slides: Record<string, unknown>[];
  if (count >= 8) {
    slides = [titleSlide(topic), agendaSlide(body), ...body.slice(0, Math.max(count - 4, 1)), recapSlide(), qaSlide()];
  } else if (count >= 4) {
    slides = [titleSlide(topic), ...body.slice(0, Math.max(count - 2, 1)), qaSlide()];
  } else {
    slides = [titleSlide(topic), ...body.slice(0, Math.max(count - 1, 0))];
  }

  return {
    p2u: 1,
    deck: { title: topic, subtitle: "A technical overview", theme: presence(options.theme) ?? "violet" },
    slides,
  };
}

function bodySlides(options: ComposeOptions, topic: string, count: number): Record<string, unknown>[] {
  if (options.sources?.length) {
    const derived = options.sources
      .flatMap((source) => sourceSlides(source))
      .filter((slide) => slide.layout !== "title")
      .map((slide) => ({
        layout: slide.layout === "section" ? "section" : "content",
        title: slide.title,
        body: slide.body,
        blocks: slide.blocks,
        notes: slide.notes,
      }));
    if (derived.length > 0) return pad(derived, topic, count);
  }
  return generated(topic, count);
}

function sourceSlides(source: string): Record<string, any>[] {
  try {
    const manifest = Parser.parse(source);
    if (manifest.slides.length > 0) return manifest.slides as Record<string, any>[];
  } catch {
    // fall through to heading split
  }
  return splitByHeadings(source);
}

function splitByHeadings(source: string): Record<string, unknown>[] {
  const segments = source.split(/^(?=#{1,3}\s+)/m).filter((segment) => segment.trim().length > 0);
  const slides = segments.map((segment) => {
    const match = segment.match(/^#{1,3}\s+(.+?)\s*\n([\s\S]*)$/);
    if (match) return { layout: "content", title: match[1]!.trim(), body: match[2]!.trim() };
    return { layout: "content", body: segment.trim() };
  });
  return slides.length > 0 ? slides : [{ layout: "content", body: source.trim() }];
}

function generated(topic: string, count: number): Record<string, unknown>[] {
  const total = Math.max(count, 1);
  return Array.from({ length: total }, (_, index) => {
    const section = DEFAULT_SECTIONS[index % DEFAULT_SECTIONS.length]!;
    return {
      layout: "content",
      title: section.title,
      body: `${section.body}\n\nHow it applies to **${topic}**:\n\n- Point one\n- Point two\n- Point three`,
    };
  });
}

function pad(slides: Record<string, unknown>[], topic: string, count: number): Record<string, unknown>[] {
  if (slides.length >= count) return slides;
  return [...slides, ...generated(topic, count - slides.length)];
}

function titleSlide(topic: string): Record<string, unknown> {
  return { layout: "title", title: topic, subtitle: "A technical overview" };
}

function agendaSlide(body: Record<string, unknown>[]): Record<string, unknown> {
  const titles = body.map((slide) => slide.title).filter(Boolean).slice(0, 8) as string[];
  const bullets = titles.length > 0 ? titles.map((title) => `- ${title}`) : ["- Overview"];
  return { layout: "content", title: "Agenda", body: bullets.join("\n") };
}

function recapSlide(): Record<string, unknown> {
  return { layout: "recap", title: "Recap", body: "The key ideas, in one slide." };
}

function qaSlide(): Record<string, unknown> {
  return { layout: "qa", title: "Questions", body: "Thank you." };
}

function targetCount(options: ComposeOptions): number {
  return options.slides ?? promptCount(options.prompt) ?? DEFAULT_SLIDES;
}

function promptCount(prompt: string): number | undefined {
  const match = prompt.match(/\b(\d{1,3})\s*[- ]?slides?\b/i);
  return match ? Number(match[1]) : undefined;
}

function topicOf(prompt: string): string {
  let text = prompt;
  text = text.replace(/^\s*(please\s+)?(make|create|build|generate|write|give\s+me|design|prepare)\s+(me\s+)?/i, "");
  text = text.replace(/\b\d{1,3}\s*[- ]?slides?\b/gi, "");
  text = text.replace(/\b(deck|presentation|talk|slides?|technical|overview|introduction|intro)\b/gi, "");
  text = text.replace(/^\s*(a|an|the)\s+/i, "");
  text = text.replace(/\b(on|about|for|covering|re:)\b/gi, "");
  text = text.replace(/\s+/g, " ").trim();
  return text || "Untitled talk";
}