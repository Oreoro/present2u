// Present2u render container.
//
// A tiny HTTP service in front of the native renderers. The Worker reaches it
// through the RendererContainer Durable Object (Cloudflare Containers).
//
//   GET  /health                              -> toolchain versions
//   POST /render { kind, source, options }    -> { svg }
//   POST /pdf    { html }                     -> application/pdf
//
// The recolor steps mirror the Ruby renderers exactly (D2Diagram,
// LatexEquation, TypstDocument) so assets match the self-hosted output.

import { createServer } from "node:http";
import { execFile } from "node:child_process";
import { mkdtemp, readFile, readdir, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { promisify } from "node:util";

const run = promisify(execFile);
const PORT = Number(process.env.PORT ?? 8080);
const TIMEOUT = Number(process.env.RENDER_TIMEOUT_MS ?? 30000);

const D2_DEFAULT_THEME = 301;
const GRAYSCALE_INK = "#000410";
const GRAYSCALE_FILL = "#FFFFFF";

const LATEX_PACKAGES = [
  "\\usepackage{amsmath,amssymb,amsfonts}",
  "\\usepackage{mathtools}",
  "\\usepackage{bm}",
].join("\n");

const LATEX_UNSUPPORTED = /\\(begin|end)\{(tikzpicture|pspicture|picture|figure|table)\}/;

const TYPST_PREAMBLE = `// Present2u slide theme — Notion-flavored
#set page(width: 16cm, height: 9cm, margin: (x: 1.2cm, y: 1cm), fill: none)
#set text(font: ("Helvetica Neue", "New Computer Modern"), size: 17pt, fill: rgb("#37352f"))
#set par(leading: 0.62em, justify: false)
#set list(indent: 1em, spacing: 0.5em, marker: [•])
#set block(spacing: 0.9em)
#show heading.where(level: 1): it => block(width: 100%, above: 0pt, below: 0.65em, text(size: 26pt, weight: "semibold", tracking: -0.2pt, it.body))
#show heading.where(level: 2): it => block(above: 0.8em, below: 0.35em, text(size: 20pt, weight: "semibold", it.body))
#show heading.where(level: 3): it => block(above: 0.6em, below: 0.3em, text(size: 17pt, weight: "semibold", it.body))
#show raw: set text(font: ("JetBrains Mono", "DejaVu Sans Mono"), size: 0.86em)
#show raw.where(block: true): it => block(width: 100%, fill: rgb("#f7f7f5"), stroke: 0.5pt + rgb("#e9e9e7"), inset: 10pt, radius: 4pt, it)
#show link: set text(fill: rgb("#2383e2"))
#let p2u-fit(body) = layout(size => {
  let content = block(width: size.width, body)
  let measured = measure(content)
  let factor = calc.min(1.0, size.height / calc.max(measured.height, 1pt))
  scale(x: factor * 100%, y: factor * 100%, origin: top + left, content)
})`;

const server = createServer(async (request, response) => {
  try {
    const url = new URL(request.url, `http://localhost:${PORT}`);

    if (request.method === "GET" && url.pathname === "/health") {
      return json(response, 200, await health());
    }
    if (request.method === "POST" && url.pathname === "/render") {
      const body = await readJson(request);
      const svg = await renderAsset(body.kind, String(body.source ?? ""), body.options ?? {});
      return json(response, 200, { svg });
    }
    if (request.method === "POST" && url.pathname === "/pdf") {
      // Chromium is intentionally not bundled (image size / cold-start budget).
      return json(response, 501, { error: "pdf_not_supported", hint: "PDF is rendered by Cloudflare Browser Rendering." });
    }

    return json(response, 404, { error: "not found" });
  } catch (error) {
    return json(response, 500, { error: String(error?.message ?? error) });
  }
});

server.listen(PORT, "0.0.0.0", () => console.log(`present2u renderer listening on 0.0.0.0:${PORT}`));

// --- Assets -------------------------------------------------------------------

async function renderAsset(kind, source, options) {
  switch (kind) {
    case "d2":
      return renderD2(source, options);
    case "latex":
      return renderLatex(source, options);
    case "typst":
      return renderTypst(source, options);
    default:
      throw new Error(`Unknown rendered asset kind: ${kind}`);
  }
}

async function withTmp(prefix, work) {
  const dir = await mkdtemp(join(tmpdir(), prefix));
  try {
    return await work(dir);
  } finally {
    await rm(dir, { recursive: true, force: true });
  }
}

async function renderD2(source, options) {
  if (!source.trim()) throw new Error("Empty diagram");
  const layout = options.layout ?? "tala";
  const theme = Number(options.theme ?? D2_DEFAULT_THEME);
  const pad = Number(options.pad ?? 20);

  return withTmp("p2u-d2-", async (dir) => {
    const input = join(dir, "diagram.d2");
    const output = join(dir, "diagram.svg");
    await writeFile(input, source);

    const args = [`--layout=${layout}`, `--theme=${theme}`, `--pad=${pad}`];
    if (options.sketch) args.push("--sketch");
    if (options.dark_theme) args.push(`--dark-theme=${options.dark_theme}`);
    args.push(input, output);

    await run("d2", args, { timeout: TIMEOUT });

    let svg = await readFile(output, "utf8");
    if (options.transparent !== false) {
      svg = svg.replace(/<rect\b[^>]*stroke-width="0"[^>]*>/, (rect) => rect.replace(/fill="[^"]*"/, 'fill="transparent"'));
    }
    if (theme === D2_DEFAULT_THEME) {
      svg = svg
        .split(GRAYSCALE_INK).join("#37352f")
        .split(GRAYSCALE_FILL).join("#f7f7f5")
        .split('fill="white"').join('fill="#f7f7f5"');
    }
    return svg;
  });
}

async function renderLatex(source, options) {
  if (!source.trim()) throw new Error("Empty equation");
  if (LATEX_UNSUPPORTED.test(source)) {
    throw new Error("TikZ/picture environments aren't supported yet — use a D2 diagram instead.");
  }

  const body = wrapLatex(source, options.display !== false);

  return withTmp("p2u-tex-", async (dir) => {
    const dimensions = await probeLatex(dir, body);
    const pdf = await compileLatex(dir, body, dimensions);
    const svg = await convertLatex(dir, pdf);
    return svg
      .replace(/fill="rgb\(\s*0%,\s*0%,\s*0%\s*\)"/g, 'fill="currentColor"')
      .replace(/stroke="rgb\(\s*0%,\s*0%,\s*0%\s*\)"/g, 'stroke="currentColor"');
  });
}

function wrapLatex(source, display) {
  let text = source.trim();
  text = text
    .replace(/\\begin\{align\*?\}/g, "\\\\begin{aligned}")
    .replace(/\\end\{align\*?\}/g, "\\\\end{aligned}")
    .replace(/\\begin\{gather\*?\}/g, "\\\\begin{gathered}")
    .replace(/\\end\{gather\*?\}/g, "\\\\end{gathered}")
    .replace(/\\begin\{multline\*?\}/g, "\\\\begin{gathered}")
    .replace(/\\end\{multline\*?\}/g, "\\\\end{gathered}")
    .replace(/\\begin\{equation\*?\}/g, "")
    .replace(/\\end\{equation\*?\}/g, "");

  if (text.startsWith("$") || text.startsWith("\\(")) return text;
  if (text.startsWith("\\[")) {
    return `$\\displaystyle ${text.replace(/^\\\[/, "").replace(/\\\]\s*$/, "")}$`;
  }
  return display ? `$\\displaystyle ${text}$` : `$${text}$`;
}

async function probeLatex(dir, body) {
  const tex = [
    "\\documentclass[12pt]{article}",
    LATEX_PACKAGES,
    "\\newsavebox{\\presenttwobox}",
    "\\begin{document}",
    `\\sbox{\\presenttwobox}{${body}}`,
    "\\typeout{PRESENT2U-BOX: \\the\\wd\\presenttwobox|\\the\\ht\\presenttwobox|\\the\\dp\\presenttwobox}",
    "\\noindent\\usebox{\\presenttwobox}",
    "\\end{document}",
  ].join("\n");

  await compileTex(dir, "probe", tex);
  const log = await readFile(join(dir, "probe.log"), "utf8");
  const match = log.match(/PRESENT2U-BOX: ([\d.]+)pt\|([\d.]+)pt\|([\d.]+)pt/);
  if (!match) throw new Error((log.match(/^!.*$/m) ?? ["Could not measure the LaTeX snippet"])[0].trim());

  return { width: Number(match[1]), height: Number(match[2]), depth: Number(match[3]) };
}

async function compileLatex(dir, body, dimensions) {
  const padding = 2.0;
  const width = dimensions.width + padding * 2;
  const height = dimensions.height + dimensions.depth + padding * 2;

  const tex = [
    "\\documentclass[12pt]{article}",
    `\\usepackage[paperwidth=${width}pt,paperheight=${height}pt,margin=0pt]{geometry}`,
    LATEX_PACKAGES,
    "\\pagestyle{empty}",
    "\\newsavebox{\\presenttwobox}",
    "\\begin{document}",
    `\\sbox{\\presenttwobox}{${body}}`,
    "\\noindent\\usebox{\\presenttwobox}",
    "\\end{document}",
  ].join("\n");

  await compileTex(dir, "equation", tex);
  return join(dir, "equation.pdf");
}

async function compileTex(dir, name, tex) {
  const path = join(dir, `${name}.tex`);
  await writeFile(path, tex);
  try {
    await run("pdflatex", ["-no-shell-escape", "-interaction=nonstopmode", "-halt-on-error", `-output-directory=${dir}`, path], {
      timeout: TIMEOUT,
    });
  } catch (error) {
    let message = error.stderr?.trim();
    try {
      const log = await readFile(join(dir, `${name}.log`), "utf8");
      message = (log.match(/^!.*$/m) ?? [message])[0].trim();
    } catch {
      // keep stderr
    }
    throw new Error(message || "pdflatex failed");
  }
}

async function convertLatex(dir, pdf) {
  const output = join(dir, "equation.svg");
  await run("pdftocairo", ["-svg", pdf, output], { timeout: TIMEOUT });
  return readFile(output, "utf8");
}

async function renderTypst(source, options) {
  if (!source.trim()) throw new Error("Empty Typst document");

  const document = options.preamble === null ? source : `${TYPST_PREAMBLE}\n#p2u-fit[\n${source}\n]`;

  return withTmp("p2u-typst-", async (dir) => {
    const input = join(dir, "document.typ");
    await writeFile(input, document);
    await run("typst", ["compile", "--format", "svg", input, join(dir, "document-{p}.svg")], { timeout: TIMEOUT });

    const pages = (await readdir(dir))
      .filter((file) => file.startsWith("document-") && file.endsWith(".svg"))
      .sort((a, b) => pageNumber(a) - pageNumber(b));

    if (pages.length === 0) throw new Error("typst produced no pages");
    if (pages.length > 1 && !options.allow_multiple) {
      throw new Error(`Typst content overflows the slide (${pages.length} pages). Trim it or use a smaller text size.`);
    }

    let svg = await readFile(join(dir, pages[0]), "utf8");
    svg = svg.replace(/<path\b[^>]*?fill="#ffffff"[^>]*?>/, (path) => path.replace('fill="#ffffff"', 'fill="transparent"'));
    return svg.replace(/fill="#(?:0{6}|1b1b1f|37352f)"/gi, 'fill="currentColor"');
  });
}

function pageNumber(file) {
  return Number(file.match(/-(\d+)\.svg$/)?.[1] ?? 0);
}

// --- Toolchain -----------------------------------------------------------------

async function health() {
  const version = async (bin, args) => {
    try {
      const { stdout, stderr } = await run(bin, args, { timeout: 5000 });
      return { available: true, version: (stdout || stderr).split("\n")[0].trim() };
    } catch {
      return { available: false, version: null };
    }
  };

  const [d2, typst, pdflatex, pdftocairo] = await Promise.all([
    version("d2", ["--version"]),
    version("typst", ["--version"]),
    version("pdflatex", ["--version"]),
    version("pdftocairo", ["-v"]),
  ]);

  return { available: true, image: process.env.P2U_IMAGE ?? "present2u/renderer", d2, typst, pdflatex, pdftocairo, chrome: { available: false } };
}

// --- HTTP helpers --------------------------------------------------------------

function json(response, status, body) {
  response.writeHead(status, { "content-type": "application/json" });
  response.end(JSON.stringify(body));
}

async function readJson(request) {
  const chunks = [];
  for await (const chunk of request) chunks.push(chunk);
  return JSON.parse(Buffer.concat(chunks).toString("utf8") || "{}");
}