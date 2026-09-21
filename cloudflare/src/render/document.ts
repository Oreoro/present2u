// Renders a full deck to a self-contained HTML document: 16:9 slides, keyboard
// navigation, progress, speaker notes and print styles. Diagram/equation SVGs
// are inlined from R2 so the file reads without a server; KaTeX and highlight.js
// styles load from a CDN (as the Ruby exporter does). Port of
// p2u/render/document.rb.

import type { Env } from "../types";
import { presence, asBool } from "../compiler/util";
import { getAsset } from "./assets";

export interface DocumentSlide {
  html: string;
  layout: string;
  kicker: string | null;
  notes: string | null;
}

export interface DocumentOptions {
  deck: Record<string, any>;
  slides: DocumentSlide[];
  title: string;
}

interface Palette {
  bg: string;
  fg: string;
  accent: string;
  subtle: string;
  page: string;
}

const PALETTES: Record<string, Palette> = {
  writebook: { bg: "#ffffff", fg: "#37352f", accent: "#2383e2", subtle: "#e9e9e7", page: "#f7f7f5" },
  black: { bg: "#191919", fg: "#f2f2f2", accent: "#529cca", subtle: "#2f2f2f", page: "#111111" },
  blue: { bg: "#191919", fg: "#eef4fb", accent: "#529cca", subtle: "#2f2f2f", page: "#111111" },
  green: { bg: "#191919", fg: "#eefaf2", accent: "#5fa56a", subtle: "#2f2f2f", page: "#111111" },
  magenta: { bg: "#191919", fg: "#fdeef5", accent: "#c14c8a", subtle: "#2f2f2f", page: "#111111" },
  orange: { bg: "#191919", fg: "#fff3e6", accent: "#d9730d", subtle: "#2f2f2f", page: "#111111" },
  violet: { bg: "#191919", fg: "#f2efff", accent: "#9065b0", subtle: "#2f2f2f", page: "#111111" },
  white: { bg: "#f7f7f5", fg: "#37352f", accent: "#2383e2", subtle: "#e9e9e7", page: "#ffffff" },
};

const RENDERED_IMG_SRC = /<img src="\/rendered\/([a-f0-9]{64})\.svg"[^>]*>/g;

export async function renderDocument(env: Env, options: DocumentOptions): Promise<string> {
  const { deck, slides, title } = options;
  const theme = themeName(deck.theme);
  const palette = PALETTES[theme] ?? PALETTES.violet!;
  const dark = theme !== "writebook" && theme !== "white";
  const scroll = asBool(deck.scroll ?? deck.flow);

  const body = await inlineRenderedSvgs(env, slideMarkup(slides, title));
  const highlightCss = dark
    ? "https://cdn.jsdelivr.net/npm/highlight.js@11.10.0/styles/github-dark.min.css"
    : "https://cdn.jsdelivr.net/npm/highlight.js@11.10.0/styles/github.min.css";

  return `<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>${h(title)}</title>
<link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/katex@0.16.11/dist/katex.min.css" crossorigin="anonymous">
<link rel="stylesheet" href="${highlightCss}" crossorigin="anonymous">
<style>${styles(palette)}</style>
</head>
<body class="p2u theme--${theme}${dark ? " p2u-dark" : ""}${scroll ? " p2u-scroll" : ""}">
<main class="p2u-deck" data-p2u-deck>
${body}
</main>
<div class="p2u-progress" data-p2u-progress></div>
<div class="p2u-hud">
  <button type="button" data-p2u-prev aria-label="Previous slide">‹</button>
  <span data-p2u-counter>1 / ${slides.length}</span>
  <button type="button" data-p2u-next aria-label="Next slide">›</button>
  <button type="button" data-p2u-notes aria-label="Speaker notes (N)">notes</button>
</div>
<aside class="p2u-notes-panel" data-p2u-notes-panel hidden></aside>
<script>${javascript}</script>
<script type="module">${mathModule}</script>
<script type="module">${renderersModule(env.PUBLIC_ORIGIN)}</script>
</body>
</html>`;
}

function slideMarkup(slides: DocumentSlide[], title: string): string {
  return slides
    .map((slide, index) => {
      const kicker = slide.kicker ? `<span class="p2u-kicker">${h(slide.kicker)}</span>` : "";
      const notes = h(slide.notes ?? "");
      return `<section class="p2u-slide p2u-layout--${h(slide.layout)}" data-index="${index}" data-notes="${notes}">
  ${kicker}
  ${slide.html}
  <footer class="p2u-slide__footer"><span>${h(title)}</span><span class="p2u-slide__number">${index + 1} / ${slides.length}</span></footer>
</section>`;
    })
    .join("\n");
}

/** Replace `/rendered/<digest>.svg` references with the SVG markup itself. */
async function inlineRenderedSvgs(env: Env, html: string): Promise<string> {
  const digests = [...html.matchAll(RENDERED_IMG_SRC)].map((match) => match[1]!);
  if (digests.length === 0) return html;

  const svgs = new Map<string, string>();
  for (const digest of new Set(digests)) {
    const object = await getAsset(env, digest);
    if (!object) continue;
    svgs.set(digest, (await object.text()).replace(/^<\?xml[^>]*\?>\s*/, ""));
  }

  return html.replace(RENDERED_IMG_SRC, (whole, digest: string) => svgs.get(digest) ?? whole);
}

function themeName(theme: unknown): string {
  const name = theme && typeof theme === "object" ? (theme as any).preset : theme;
  const value = presence(name);
  return value && value in PALETTES ? value : "writebook";
}

function styles(p: Palette): string {
  return `
*, *::before, *::after { box-sizing: border-box; }
:root { --p2u-bg: ${p.bg}; --p2u-fg: ${p.fg}; --p2u-accent: ${p.accent}; --p2u-subtle: ${p.subtle}; --p2u-page: ${p.page}; }
html, body { margin: 0; height: 100%; }
body.p2u { background: color-mix(in srgb, var(--p2u-fg) 4%, var(--p2u-page)); color: var(--p2u-fg); font-family: system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; overflow: hidden; }
.p2u-deck { align-items: center; display: flex; height: 100vh; justify-content: center; width: 100vw; }
.p2u-slide { aspect-ratio: 16 / 9; background: var(--p2u-bg); border-radius: 8px; box-shadow: 0 8px 32px rgba(0,0,0,.35); container-type: inline-size; display: none; flex-direction: column; inline-size: min(96vw, 170vh); justify-content: center; max-block-size: 94vh; overflow-x: hidden; overflow-y: auto; overscroll-behavior: contain; padding: clamp(1.5rem, 5cqi, 4.5rem); position: relative; text-align: start; }
.p2u-slide.is-active { display: flex; }
body.p2u-scroll { block-size: auto; overflow: auto; }
.p2u-scroll .p2u-deck { display: block; block-size: auto; padding: clamp(1rem, 3vw, 2.5rem) 0; }
.p2u-scroll .p2u-slide { aspect-ratio: auto; display: flex; inline-size: min(96vw, 1080px); margin: 0 auto clamp(1.5rem, 4vw, 3rem); max-block-size: none; overflow: visible; }
.p2u-scroll .p2u-hud, .p2u-scroll .p2u-progress { display: none; }
.p2u-slide__inner { display: flex; flex-direction: column; gap: 1em; min-block-size: 0; }
.p2u-slide__inner--diagram, .p2u-slide__inner--equation, .p2u-slide__inner--typst { justify-content: center; overflow: hidden; }
.p2u-kicker { align-items: center; color: var(--p2u-accent); display: flex; gap: 1em; font-size: clamp(.68rem, 1.4cqi, .85rem); font-weight: 600; letter-spacing: .09em; margin-block-end: clamp(1rem, 3cqi, 1.75rem); text-transform: uppercase; }
.p2u-kicker::after { border-block-start: 1px solid var(--p2u-subtle); content: ""; flex-grow: 1; }
.p2u-slide__footer { align-items: center; border-block-start: 1px solid var(--p2u-subtle); color: color-mix(in srgb, var(--p2u-fg) 55%, transparent); display: flex; font-size: clamp(.65rem, 1.3cqi, .8rem); justify-content: space-between; margin-block-start: clamp(1rem, 3cqi, 1.75rem); padding-block-start: .7rem; }
.p2u-heading { font-size: clamp(1.5rem, 4.4cqi, 3rem); font-weight: 600; line-height: 1.2; margin: 0; }
.p2u-title { font-size: clamp(2.2rem, 9cqi, 6rem); font-weight: 600; letter-spacing: -.02em; line-height: 1.05; margin: 0; }
.p2u-subtitle { color: color-mix(in srgb, var(--p2u-fg) 72%, transparent); font-size: clamp(1.1rem, 3.4cqi, 2.2rem); margin: 0; }
.p2u-slide__inner--title, .p2u-slide__inner--section { align-items: center; justify-content: center; text-align: center; }
.p2u-slide :is(p, li) { font-size: clamp(.95rem, 2.1cqi, 1.5rem); line-height: 1.55; max-inline-size: 68ch; }
.p2u-slide :is(h1,h2,h3) { font-weight: 600; line-height: 1.15; }
.p2u-slide a { color: var(--p2u-accent); }
.p2u-slide img { border-radius: 6px; max-inline-size: 100%; }
.p2u-slide table { border-collapse: collapse; font-size: clamp(.8rem, 2cqi, 1.25rem); inline-size: 100%; }
.p2u-slide th, .p2u-slide td { border-bottom: 1px solid var(--p2u-subtle); padding: .5em .7em; text-align: start; }
.p2u-slide pre { background: color-mix(in srgb, var(--p2u-fg) 7%, transparent); border: 1px solid var(--p2u-subtle); border-radius: 6px; font-size: clamp(.7rem, 1.8cqi, 1.05rem); overflow: auto; padding: 1em 1.2em; }
.p2u-slide code { font-family: "SF Mono", ui-monospace, Menlo, Consolas, monospace; }
.p2u-slide :not(pre) > code { background: var(--p2u-subtle); border-radius: 4px; padding: .1em .35em; }
.p2u-columns { align-items: start; display: grid; gap: clamp(1rem, 3cqi, 2.5rem); min-block-size: 0; }
.p2u-columns--two-column, .p2u-columns--compare { grid-template-columns: 1fr 1fr; }
.p2u-columns--code-split { grid-template-columns: 1.15fr .85fr; }
.p2u-columns--compare .p2u-column { background: color-mix(in srgb, var(--p2u-fg) 4%, transparent); border-radius: 8px; padding: 1em; }
.p2u-column { min-block-size: 0; min-inline-size: 0; }
.p2u-metrics { display: grid; gap: clamp(.75rem, 2.5cqi, 1.75rem); grid-template-columns: repeat(auto-fit, minmax(140px, 1fr)); }
.p2u-metric { background: color-mix(in srgb, var(--p2u-fg) 4%, transparent); border: 1px solid var(--p2u-subtle); border-radius: 8px; display: flex; flex-direction: column; gap: .3em; padding: 1.1em 1.3em; }
.p2u-metric__value { font-size: clamp(1.6rem, 5cqi, 3.2rem); font-weight: 600; }
.p2u-metric__label { color: color-mix(in srgb, var(--p2u-fg) 68%, transparent); font-size: clamp(.75rem, 1.9cqi, 1.1rem); }
.p2u-quote { border-inline-start: 3px solid var(--p2u-accent); margin: 0; padding-inline-start: 1.1em; }
.p2u-quote p { font-size: clamp(1.3rem, 4cqi, 2.6rem) !important; font-weight: 500; line-height: 1.25; margin: 0; }
.p2u-quote cite { color: color-mix(in srgb, var(--p2u-fg) 65%, transparent); display: block; font-size: clamp(.85rem, 2cqi, 1.2rem); margin-block-start: .6em; }
.p2u-diagram, .p2u-equation { align-items: center; color: var(--p2u-fg); display: flex; justify-content: center; min-block-size: 0; }
.p2u-diagram svg, .p2u-equation svg, .p2u-d2 svg, .p2u-typst svg { block-size: auto; max-block-size: 100%; max-inline-size: 100%; }
.p2u-equation svg { max-block-size: 40vh; }
.p2u-diagram svg { max-block-size: 58vh; }
.p2u-d2, .p2u-typst { align-items: center; color: var(--p2u-fg); display: flex; justify-content: center; min-block-size: 0; }
.p2u-d2 { max-block-size: 58vh; }
.p2u-d2:not(.is-rendered), .p2u-typst:not(.is-rendered) { display: block; font-family: "SF Mono", ui-monospace, Menlo, Consolas, monospace; font-size: clamp(.7rem, 1.8cqi, 1.05rem); overflow: auto; white-space: pre-wrap; color: color-mix(in srgb, var(--p2u-fg) 62%, transparent); }
.p2u-tex { overflow: auto; }
.p2u-diagram--sketch { border: 2px solid color-mix(in srgb, var(--p2u-fg) 28%, transparent); border-radius: 18px 8px 16px 10px / 10px 16px 8px 18px; padding: clamp(.5rem, 2cqi, 1.25rem); }
.p2u-typst { align-items: center; color: var(--p2u-fg); display: flex; justify-content: center; }
.p2u-typst svg { block-size: auto; max-block-size: 100%; max-inline-size: 100%; }
.p2u-images--image-grid { display: grid; gap: 1rem; grid-template-columns: repeat(auto-fit, minmax(200px, 1fr)); }
.p2u-images figure { margin: 0; }
.p2u-images figcaption { color: color-mix(in srgb, var(--p2u-fg) 62%, transparent); font-size: .85rem; margin-block-start: .4em; }
.p2u-callout { background: color-mix(in srgb, var(--p2u-fg) 5%, transparent); border-inline-start: 3px solid var(--p2u-accent); border-radius: 6px; padding: .8em 1em; }
.p2u-definition { margin: 0; } .p2u-definition dt { font-weight: 600; } .p2u-definition dd { margin: .2em 0 0; }
.p2u-progress { background: var(--p2u-accent); block-size: 3px; inline-size: 0; left: 0; position: fixed; top: 0; transition: inline-size .2s ease; z-index: 30; }
.p2u-hud { align-items: center; bottom: 1rem; display: flex; gap: .5rem; left: 50%; position: fixed; transform: translateX(-50%); z-index: 30; }
.p2u-hud button, .p2u-hud span { background: color-mix(in srgb, var(--p2u-fg) 10%, transparent); border: 1px solid color-mix(in srgb, var(--p2u-fg) 20%, transparent); border-radius: 4px; color: var(--p2u-fg); cursor: pointer; font: inherit; font-size: .85rem; min-inline-size: 2.4rem; padding: .45rem .8rem; }
.p2u-notes-panel { background: var(--p2u-bg); border-block-start: 1px solid var(--p2u-subtle); bottom: 0; color: var(--p2u-fg); font-size: 1rem; left: 0; line-height: 1.5; max-block-size: 34vh; overflow: auto; padding: 1.2rem 1.5rem; position: fixed; right: 0; white-space: pre-wrap; z-index: 40; }
@media print {
  @page { margin: 0; size: 297mm 167mm; }
  html, body { height: auto; overflow: visible; }
  body.p2u { background: #fff; }
  .p2u-deck { display: block; height: auto; }
  .p2u-slide { aspect-ratio: auto; border-radius: 0; box-shadow: none; display: flex !important; inline-size: 100%; min-block-size: 167mm; page-break-after: always; }
  .p2u-hud, .p2u-progress, .p2u-notes-panel { display: none !important; }
}`;
}

const javascript = `
(function () {
  var slides = Array.prototype.slice.call(document.querySelectorAll('.p2u-slide'));
  if (!slides.length) return;
  var index = 0;
  var counter = document.querySelector('[data-p2u-counter]');
  var progress = document.querySelector('[data-p2u-progress]');
  var notesPanel = document.querySelector('[data-p2u-notes-panel]');
  function render() {
    slides.forEach(function (slide, i) { slide.classList.toggle('is-active', i === index); });
    if (counter) counter.textContent = (index + 1) + ' / ' + slides.length;
    if (progress) progress.style.inlineSize = ((index + 1) / slides.length * 100) + '%';
    if (notesPanel) notesPanel.textContent = slides[index].dataset.notes || 'No speaker notes for this slide.';
  }
  function go(n) { index = Math.max(0, Math.min(slides.length - 1, n)); render(); }
  function next() { go(index + 1); }
  function prev() { go(index - 1); }
  document.querySelector('[data-p2u-next]').addEventListener('click', next);
  document.querySelector('[data-p2u-prev]').addEventListener('click', prev);
  document.querySelector('[data-p2u-notes]').addEventListener('click', function () {
    if (notesPanel) notesPanel.hidden = !notesPanel.hidden;
  });
  document.addEventListener('keydown', function (event) {
    if (event.target.closest('input, textarea, select')) return;
    switch (event.key) {
      case 'ArrowRight': case ' ': case 'PageDown': case 'Enter': event.preventDefault(); next(); break;
      case 'ArrowLeft': case 'PageUp': event.preventDefault(); prev(); break;
      case 'Home': event.preventDefault(); go(0); break;
      case 'End': event.preventDefault(); go(slides.length - 1); break;
      case 'f': case 'F':
        if (document.fullscreenElement) document.exitFullscreen(); else document.documentElement.requestFullscreen && document.documentElement.requestFullscreen();
        break;
      case 'n': case 'N': if (notesPanel) notesPanel.hidden = !notesPanel.hidden; break;
      case 'Escape': if (notesPanel) notesPanel.hidden = true; break;
    }
  });
  document.addEventListener('click', function (event) {
    if (event.target.closest('.p2u-hud, .p2u-notes-panel, a, button')) return;
    (event.clientX / window.innerWidth > 0.5 ? next : prev)();
  });
  render();
})();`;

// Markdown is already server-rendered; only inline KaTeX maths needs the browser.
const mathModule = `
import renderMathInElement from 'https://cdn.jsdelivr.net/npm/katex@0.16.11/dist/contrib/auto-render.mjs';
function run() {
  renderMathInElement(document.body, {
    delimiters: [
      { left: '$$', right: '$$', display: true },
      { left: '$', right: '$', display: false },
      { left: '\\\\(', right: '\\\\)', display: false },
      { left: '\\\\[', right: '\\\\]', display: true }
    ],
    throwOnError: false
  });
}
if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', run); else run();`;

// Client-side renderers for D2 (WASM) and Typst (WASM), so diagrams work even
// when the render container is unavailable. KaTeX (above) handles equations.
// The D2 browser build + wasm are self-hosted at /d2 (the npm package's browser
// folder is missing d2.wasm), referenced by absolute origin so exported files
// work from anywhere.
function renderersModule(origin: string): string {
  return `
(async () => {
  const race = (promise, ms, label) => Promise.race([
    promise,
    new Promise((_, reject) => setTimeout(() => reject(new Error('timeout ' + label)), ms))
  ]);
  const renderD2 = async () => {
    const nodes = Array.prototype.slice.call(document.querySelectorAll('.p2u-d2'));
    if (!nodes.length) return;
    let D2 = null;
    for (const url of ['${origin}/d2/index.js', 'https://esm.sh/@terrastruct/d2@0.1.33']) {
      try { ({ D2 } = await import(url)); break; } catch (error) { console.warn('present2u: D2 loader', url, error); }
    }
    if (!D2) return;
    const d2 = new D2();
    for (const el of nodes) {
      try {
        const compiled = await race(d2.compile(el.textContent || '', { layout: 'dagre' }), 60000, 'd2 compile');
        const svg = await race(d2.render(compiled.diagram, { noXMLTag: true, pad: 20, sketch: el.dataset.sketch === 'true' }), 20000, 'd2 render');
        el.innerHTML = svg;
        el.classList.add('is-rendered');
      } catch (error) { console.error('present2u: D2 render failed', error); }
    }
  };
  const renderTypst = async () => {
    const nodes = Array.prototype.slice.call(document.querySelectorAll('.p2u-typst[data-render]'));
    if (!nodes.length) return;
    try {
      const typst = await import('https://esm.sh/@myriaddreamin/typst.ts@0.7.0');
      const compilerWasm = 'https://cdn.jsdelivr.net/npm/@myriaddreamin/typst-ts-web-compiler@0.7.0/pkg/typst_ts_web_compiler_bg.wasm';
      const rendererWasm = 'https://cdn.jsdelivr.net/npm/@myriaddreamin/typst-ts-renderer@0.7.0/pkg/typst_ts_renderer_bg.wasm';
      typst.$typst.setCompilerInitOptions({ getModule: () => WebAssembly.compileStreaming(fetch(compilerWasm)) });
      typst.$typst.setRendererInitOptions({ getModule: () => WebAssembly.compileStreaming(fetch(rendererWasm)) });
      for (const el of nodes) {
        const svg = await race(typst.$typst.svg({ mainContent: el.textContent || '' }), 90000, 'typst svg');
        el.innerHTML = svg;
        el.classList.add('is-rendered');
      }
    } catch (error) { console.error('present2u: Typst render failed', error); }
  };
  try { await renderD2(); } catch (error) { console.error(error); }
  try { await renderTypst(); } catch (error) { console.error(error); }
  window.__p2uRenderComplete = true;
})();`;
}

function h(value: unknown): string {
  return String(value ?? "")
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#39;");
}