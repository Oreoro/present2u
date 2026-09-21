// Server-side Markdown for slide bodies and HTML export. Renders with
// markdown-it and highlight.js, and resolves the special fences (d2, d2-sketch,
// latex, typst) to content-addressed SVGs before the Markdown pass — the same
// contract as writebook/lib/markdown_renderer.rb.
//
// Raw HTML in Markdown is disabled (`html: false`), so authored HTML cannot
// inject markup; generated asset HTML is inserted from a trusted token map.

import MarkdownIt from "markdown-it";
import hljs from "highlight.js/lib/common";
import type { AssetKind } from "./digest";
import type { AssetResolver } from "./slide";

const FENCE = /^```([a-zA-Z0-9_+-]*)[ \t]*\r?\n([\s\S]*?)^```[ \t]*\r?$/gm;

const D2_LANGS = new Set(["d2", "tala"]);
const D2_SKETCH_LANGS = new Set(["d2-sketch", "d2sketch"]);
const LATEX_LANGS = new Set(["latex", "tex", "math", "equation"]);
const TYPST_LANGS = new Set(["typst", "typ"]);

const md = new MarkdownIt({
  html: false,
  linkify: true,
  breaks: false,
  highlight(source: string, language: string): string {
    if (language && hljs.getLanguage(language)) {
      try {
        return `<pre class="hljs"><code>${hljs.highlight(source, { language, ignoreIllegals: true }).value}</code></pre>`;
      } catch {
        // fall through to escaped source
      }
    }
    return `<pre class="hljs"><code>${escapeHtml(source)}</code></pre>`;
  },
});

function escapeHtml(value: string): string {
  return value
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;");
}

export interface MarkdownOptions {
  dark?: boolean;
  assetStore?: AssetResolver;
}

/** Renders a Markdown fragment to HTML, resolving diagram/equation fences. */
export async function markdownToHtml(text: string, options: MarkdownOptions = {}): Promise<string> {
  if (!text || text.trim().length === 0) return "";

  const fences: { token: string; language: string; source: string }[] = [];
  let counter = 0;

  const prepared = text.replace(FENCE, (whole, rawLanguage: string, body: string) => {
    const language = rawLanguage.toLowerCase();
    if (!isSpecial(language)) return whole;

    const token = `@@P2U_ASSET_${counter}@@`;
    counter += 1;
    fences.push({ token, language, source: body });
    return `\n\n${token}\n\n`;
  });

  const rendered = new Map<string, string>();
  for (const fence of fences) {
    rendered.set(fence.token, await fenceHtml(fence.language, fence.source, options));
  }

  let html = md.render(prepared);
  for (const [token, block] of rendered) {
    html = html.split(`<p>${token}</p>`).join(block).split(token).join(block);
  }

  return html;
}

function isSpecial(language: string): boolean {
  return (
    D2_LANGS.has(language) ||
    D2_SKETCH_LANGS.has(language) ||
    LATEX_LANGS.has(language) ||
    TYPST_LANGS.has(language)
  );
}

async function fenceHtml(language: string, source: string, options: MarkdownOptions): Promise<string> {
  const theme = options.dark ? 200 : 301;

  // LaTeX renders client-side with KaTeX (display math) — no server needed.
  if (LATEX_LANGS.has(language)) {
    return `<div class="p2u-equation p2u-tex">\\[${escapeHtml(source)}\\]</div>`;
  }

  if (D2_LANGS.has(language) || D2_SKETCH_LANGS.has(language)) {
    const sketch = D2_SKETCH_LANGS.has(language);
    const url = await tryServer(options.assetStore, "d2", source, { layout: "tala", sketch, theme, transparent: true });
    if (url) {
      return `<div class="p2u-diagram${sketch ? " p2u-diagram--sketch" : ""}"><img src="${url}" alt="D2 diagram" loading="lazy"></div>`;
    }
    return `<div class="p2u-d2" data-sketch="${sketch ? "true" : "false"}">${escapeHtml(source)}</div>`;
  }

  if (TYPST_LANGS.has(language)) {
    const url = await tryServer(options.assetStore, "typst", source, { slide: true });
    if (url) {
      return `<div class="p2u-diagram p2u-diagram--typst"><img src="${url}" alt="Typst document" loading="lazy"></div>`;
    }
    return `<div class="p2u-typst" data-render="1">${escapeHtml(source)}</div>`;
  }

  return "";
}

// Returns the server-rendered asset URL, or null when the renderer is absent or
// fails (so the caller can emit client-renderable markup instead).
async function tryServer(
  assetStore: AssetResolver | undefined,
  kind: AssetKind,
  source: string,
  options: Record<string, unknown>,
): Promise<string | null> {
  if (!assetStore) return null;
  try {
    return await assetStore({ slide: "markdown", kind, source, options });
  } catch {
    return null;
  }
}