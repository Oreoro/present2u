# present2u — from Writebook to a declarative presentation compiler

> **Status:** Phases 0–1, 3, 4, 5 and 6 shipped (Phase 2 shipped as a layout-aware renderer + presenter attribute rather than server-rendered partials).
>
> - **Compiler:** `P2u::{Parser,Validator,Compiler,Emitter,Planner,Outliner,Exporter,MCP,Toolchain,CLI}`; `P2u::Render::{Slide,Document}`; `Layouts`/`Blocks` registries.
> - **Language:** P2U/1 YAML/JSON/Markdown, JSON Schema, diagnostics, density budget.
> - **Declarative:** stable `leaves.p2u_id` + `leaves.layout`; idempotent `plan`/`apply` (create/update/delete/reorder).
> - **Render:** layout-aware HTML for all 19 layouts (two-column, compare, code-split, metric-row, diagram, equation, image-grid, quote…).
> - **Export:** self-contained HTML, Markdown notes, PDF via headless Chrome. API `POST /api/export`.
> - **Agent:** MCP stdio server (`bin/p2u mcp`) with 11 tools; `p2u outline` slide budgeter.
> - **Compose:** `P2u::Composer` + `P2u::LLM` (OpenAI-compatible, self-repairing) or a deterministic outline from a prompt/notes; `p2u compose` / `POST /api/compose`.
> - **CLI:** `validate|compile|plan|apply|compose|outline|export|mcp|schema|doctor` (`--json`).
> - **Tests:** `test/models/p2u` + `test/controllers/api`; full suite 353 runs with only the pre-existing vips HEIC/AVIF failures.

## 0. Where we actually are (audit)

The repo is **not** base Writebook anymore. The following already exist and work:

| Capability | Where |
| --- | --- |
| Books→decks, Leaves→slides (`section` / `content` / `image`) | `app/models/{book,leaf,section,page,picture}.rb` |
| Markdown + Rouge + inline KaTeX | `lib/markdown_renderer.rb`, `app/javascript/controllers/math_controller.js` |
| Fenced ` ```d2 ` / ` ```d2-sketch ` → SVG (TALA layout) | `app/models/d2_diagram.rb` |
| Fenced ` ```latex ` → tightly-cropped SVG (pdflatex → pdftocairo) | `app/models/latex_equation.rb` |
| Content-addressed asset store + sanitizer-safe `/rendered/<sha>.svg` | `app/models/rendered_asset.rb`, `rendered_assets_controller.rb` |
| Manifest → deck (`DeckBuilder`) | `app/models/deck_builder.rb` |
| 8 ready-made technical templates | `app/models/deck_templates/*.rb` |
| JSON API (`/api`, `/api/decks`, `/import`, slides, `/api/templates`) | `app/controllers/api/*` |
| Present mode: 16:9, arrows/space/swipe, ESC, counter, notes, overview, `?` | `app/javascript/controllers/present_controller.js` |
| Generative cover art, themes, sketch theme, Space Grotesk | `app/models/generative_art.rb`, `app/assets/stylesheets/{decks,technical,sketch,present}.css` |
| context.dev imagery | `app/models/context_dev.rb` |

**The gap:** today a deck is an *ad-hoc Ruby hash* (`{ type:, title:, body: }`) plus an imperative API. There is no versioned language, no validation/diagnostics, no layout system, no plan/apply, no CLI, no MCP, no export pipeline, and no way for an agent to ask "compile this intent into N slides on this toolchain."

This plan turns that hash into a **declarative compiler** with an agent-first command surface.

---

## 1. Target architecture

Treat a deck like source code:

```
 .p2u / .md / .json  ──parse──▶  AST  ──validate──▶  diagnostics
                                     │
                                     ▼
                                 planner ──▶ plan (diff vs existing deck)
                                     │
                                     ▼
                                 emitter ──▶ deck records (DeckBuilder)
                                     │
                          renderer ──┴──▶ asset cache (RenderedAsset)
                                     │
                                     ▼
                        exporter ──▶ web / HTML / PDF / PNG / PPTX / notes
```

Five separable components, each independently testable:

1. **Language** — `P2U/1` versioned manifest (JSON Schema + YAML/Markdown surface).
2. **Compiler** — parse → validate → plan → emit → render (deterministic, idempotent, content-addressed).
3. **Layout engine** — slide `layout` + `blocks` primitives instead of one hard-coded `type`.
4. **Command surface** — CLI, HTTP API, MCP tools, natural-language compose.
5. **Render targets** — live presenter, static HTML, PDF/PNG/PPTX, speaker notes.

---

## 2. The `P2U/1` manifest language

A deck is a declarative document. Accept three surfaces that compile to the same AST:

- **YAML** — canonical, human/agent friendly.
- **JSON** — machine/tool-call friendly; the existing API keeps working.
- **Markdown** — front matter for deck meta, `---` separates slides, per-slide fenced front matter for layout/notes. This is how a human "just writes" a deck.

```yaml
p2u: 1
deck:
  id: transformer-2024          # stable identity for plan/apply
  title: Attention Is All You Need
  subtitle: From equations to engineering
  author: Present2u
  aspect: "16:9"
  theme:
    preset: violet
    tokens: { accent: "#7c5cff", code: github-dark }
  defaults:
    layout: content
    transition: fade
    diagram: { engine: d2, layout: tala, theme: dark }
    math: { engine: katex }
  meta: { venue: NeurIPS, date: 2024-06-01, license: CC-BY }

slides:
  - id: why
    layout: section
    title: Why attention
    body: Sequential models hit a wall
    notes: Set up the limitation.

  - id: recurrence
    layout: content
    title: The problem with recurrence
    blocks:
      - kind: markdown
        body: |
          An RNN advances one step at a time: $$h_t = f(h_{t-1}, x_t).$$
      - kind: diagram
        lang: d2
        source: |
          direction: right
          rnn: "RNN cell" { shape: cylinder }
          rnn -> rnn: "t"
    notes: Emphasise O(n) sequential depth.

  - id: qkv
    layout: two-column
    title: Attention as soft lookup
    left:  { kind: markdown, body: "Query, key, value…" }
    right: { kind: diagram, lang: d2-sketch, source: "…" }
    reveal: [0, 1]              # progressive build steps
    sketch: true
```

Design rules:

- **`layout` replaces `type`** (`section` / `content` / `image` stay as aliases for backward compatibility).
- **`blocks` are typed content units** (`markdown`, `code`, `diagram`, `equation`, `table`, `chart`, `image`, `quote`, `metric`, `video`, `callout`, `references`, `notes-only`).
- **`id` on every slide** is the stable key that makes `plan`/`apply` idempotent.
- **`reveal`** declares fragments; **`notes`** is speaker-only.
- **Everything is addressable** (`deck.slides[qkv].right.source`) so diagnostics can point precisely.

Deliverables: `config/schemas/p2u-1.schema.json` (JSON Schema), `P2U_SPEC.md`, and `Api::SchemaController#show` so any LLM can fetch the contract.

---

## 3. Compiler pipeline

New namespace `app/models/p2u/` (or `lib/p2u/`):

| Stage | Class | Responsibility |
| --- | --- | --- |
| Parse | `P2u::Parser` | YAML/JSON/Markdown-front-matter → `P2u::Manifest` AST |
| Validate | `P2u::Validator` | schema + semantic checks; returns `P2u::Diagnostic[]` |
| Plan | `P2u::Planner` | diff desired manifest vs existing deck → ordered actions |
| Emit | `P2u::Emitter` | plan → `Book`/`Leaf` writes (wraps `DeckBuilder`) |
| Render | `P2u::Renderer` | compile blocks → assets via `RenderedAsset` (cache-aware) |
| Export | `P2u::Exporter` | deck → HTML / PDF / PNG / PPTX / notes |

Diagnostic shape (agent- and CLI-friendly):

```json
{ "severity": "error", "code": "unknown_layout", "slide": "qkv",
  "path": "slides[2].layout", "message": "Unknown layout: two-columns",
  "hint": "Did you mean 'two-column'? See /api/schema." }
```

Semantic checks beyond schema:

- unknown layout / block kind / diagram engine
- missing required field per layout
- unresolved `$ref` to images or sibling slides
- **density budget**: words-per-slide, bullets-per-slide, code-line budget → warning
- D2 syntax pre-check (`d2 --check` or a dry render) and LaTeX pre-check, cached
- theme token validation
- duplicate slide `id`
- "how many slides" estimate + suggested split when a slide overflows

`present2u compile file.p2u --dry-run --json` returns diagnostics + the asset render plan **without writing** to the DB.

---

## 4. Layout & block library

Turn the current 3 slide kinds into a documented library.

**Layouts:** `title`, `section`, `content`, `two-column`, `compare`, `code-split` (code + prose), `full-code`, `diagram`, `equation`, `table`, `metric-row`, `timeline`, `quote`, `image`, `image-grid`, `references`, `recap`, `qa`, `end`.

**Blocks:** `markdown`, `code` (lang + line highlights), `diagram` (d2 / mermaid / graphviz / tikz), `equation`, `table`, `chart` (bar/line/scatter from an inline data table), `image`, `video`, `metric`, `quote`, `callout`, `definition`, `references`, `notes-only`, `spacer`.

Implementation: each layout is a view partial + a Ruby layout descriptor (`app/models/p2u/layouts/*.rb`) declaring required/optional fields, allowed blocks, and capacity. The presenter CSS (`app/assets/stylesheets/present.css`, `technical.css`) gets a grid per layout; the runtime measures overflow and emits a `density` warning back through the compiler (WYSIWYG guard).

This is where "how many slides" becomes a real answer: a **slide budgeter** estimates content volume, proposes an outline (N slides), and splits overflowing slides deterministically.

---

## 5. Asset compilers & the "stack" report

Generalise `RenderedAsset` from `{d2, latex}` to a registry:

```
app/models/p2u/compilers/
  d2_compiler.rb        # tala / elk / dagre; theme + dark-theme from deck tokens
  latex_compiler.rb     # math + tikz (sandboxed, no shell-escape)
  mermaid_compiler.rb   # via @mermaid-js/mermaid-cli
  graphviz_compiler.rb  # dot → svg
  chart_compiler.rb     # vega-lite / matplotlib from inline tables
  code_compiler.rb      # Rouge server-side highlight for export
```

`present2u doctor` and `GET /api/toolchain` report the **stack** with versions and availability:

```json
{ "markdown": {"engine":"redcarpet","version":"3.6"}, "math":{"engine":"katex"},
  "d2": {"binary":"d2","version":"0.6.x","layouts":["tala","elk"]},
  "latex": {"pdflatex":"…","pdftocairo":"…"}, "mermaid":"…", "chrome":"…" }
```

Cache key becomes `(compiler, version, source, options, theme)` so a toolchain upgrade invalidates only affected assets. Compilers run through the existing Resque pool (`resque-pool` is already a dependency) with timeouts, output-size caps, and no shell escape — an agent can never block a request thread.

---

## 6. Agent command surface

### 6.1 CLI — `bin/p2u`

```
p2u init deck.p2u                     # scaffold a manifest
p2u validate deck.p2u --json          # diagnostics only, exit code = severity
p2u compile deck.p2u --dry-run        # render plan + assets, no DB writes
p2u plan   deck.p2u --deck 42         # Terraform-style diff
p2u apply  deck.p2u --deck 42         # idempotent create/update/move/delete
p2u render block.d2 -o out.svg        # single asset
p2u preview deck.p2u                  # local live server
p2u export deck.p2u --to pdf|html|png|pptx|notes
p2u outline notes.md --slides 12      # propose an outline + slide budget
p2u schema                            # emit JSON Schema
p2u doctor                            # toolchain report
```

Every command supports `--json` and meaningful exit codes so agents can loop on diagnostics.

### 6.2 HTTP API (extends existing `/api`)

- `GET /api/schema` — P2U JSON Schema (tool contract).
- `GET /api/toolchain` — stack report.
- `POST /api/compile` — validate + render without persisting.
- `GET /api/decks/:id/plan` — diff a manifest against a deck.
- `POST /api/decks/:id/apply` — idempotent declarative apply.
- `POST /api/render` — single diagram/equation render.
- `POST /api/decks/:id/export` — async export job → artifact URL.
- Existing `/api/decks`, `/import`, `/slides`, `/templates` remain unchanged.

### 6.3 MCP server — `lib/mcp/present2u.rb`

Expose the compiler as tools so Claude/any agent can drive it conversationally:

`get_schema`, `validate_manifest`, `create_deck`, `plan_deck`, `apply_deck`, `render_diagram`, `render_equation`, `export_deck`, `list_templates`, `compose_deck`, `doctor`.

Resources: `p2u://schema`, `p2u://templates`, `p2u://deck/{id}`. This is the literal "people can just command about a presentation" layer.

### 6.4 Natural-language compose — `POST /api/compose`

```json
{ "prompt": "12-slide technical deck on Raft consensus with diagrams and Go code",
  "sources": ["https://raft.github.io/"], "theme": "violet" }
```

Pipeline: `P2u::Composer` (context.dev/LLM) → candidate manifest → `Validator` (self-repair loop on diagnostics, max N) → `Planner`/`Emitter`. Returns the manifest *and* diagnostics so the human can see and edit it. Slide count and stack are explicit in the response.

---

## 7. Render targets & presenter upgrades

- **Static HTML**: self-contained bundle (assets inlined, KaTeX + fonts, keyboard nav) → a single `.html` or a folder.
- **PDF / PNG**: headless Chrome print-to-PDF over the presenter DOM, one page per slide, aspect-locked. PNG per slide for thumbnails/OG.
- **PPTX**: `pptxgenjs` (or a Ruby bridge) — one slide per layout, SVG assets embedded; explicitly "lossy export" with a fidelity report.
- **Speaker notes**: Markdown/PDF notes export; a real **presenter view** (current slide + next + notes + timer).
- **Runtime**: fragments/`reveal`, dual-window presenter, ActionCable remote control + audience follow, QR (`qr_code_link` already exists), and a live slide-count/progress HUD.

---

## 8. Determinism, testing, security

- **Deterministic**: same manifest + same toolchain versions → byte-identical assets (already true for `RenderedAsset`; extend version to cache key).
- **Golden tests**: `test/compiler/` with manifest fixtures → expected diagnostics, plan, and asset hashes.
- **Fixtures-first** per `AGENTS.md`; `_path` helpers; `assert_in_body`.
- **Security**: compilers already disable LaTeX shell-escape and validate image URLs against SSRF (`ContextDev.private_host?`). Add per-compiler timeouts, memory/output caps, temp-dir isolation, allow-listed engines, and run everything on Resque. Sanitizer-safe `/rendered/<sha>.svg` stays the only asset path.
- **Observability**: compile jobs report status/errors per slide; `p2u doctor` for humans.

---

## 9. Phased roadmap

**Phase 0 — Freeze the current contract (small)**
- Write `P2U_SPEC.md` + `config/schemas/p2u-1.schema.json` from today's `DeckBuilder` behaviour.
- Keep `type` as an alias of `layout`; no breaking API changes.

**Phase 1 — Compiler core**
- `P2u::{Parser,Validator,Diagnostic}`; `POST /api/compile`; `bin/p2u validate|compile`.
- Semantic + density checks; D2/LaTeX pre-check through `RenderedAsset`.
- Tests: validator diagnostics, schema round-trip.

**Phase 2 — Layout & block library**
- Layout descriptors + view partials + CSS; `blocks` model; `reveal`.
- Migrate the 8 templates to the new syntax as living examples.

**Phase 3 — Declarative apply**
- `P2u::Planner` with stable slide `id`; `GET /plan`, `POST /apply`; `bin/p2u plan|apply`.
- Tests: add/update/reorder/delete idempotency.

**Phase 4 — Export & presenter**
- `P2u::Exporter` (HTML/PDF/PNG/PPTX/notes) via Resque; presenter view + fragments + remote.

**Phase 5 — Agent surface**
- MCP server; `GET /api/schema`, `/api/toolchain`; `p2u doctor`.
- `POST /api/compose` (NL → manifest → validated deck) with self-repair.

**Phase 6 — More compilers & incremental builds**
- mermaid, graphviz, charts, tikz; version-aware cache; incremental asset invalidation.
- `p2u outline` slide budgeter.

**Phase 7 — Harden & document**
- Golden tests, load/timeout tests, docs site for the language, expand template gallery.

---

## 10. Risks & open questions

- **PPTX fidelity** is inherently lossy for D2/LaTeX — ship it with an explicit fidelity report, or prefer PDF as the interchange format.
- **LaTeX/TikZ** is a large attack surface; keep shell-escape off, sandbox, and time-box.
- **Layout overflow** is the main UX risk; the density diagnostics + budgeter must be trustworthy before auto-compose ships.
- **Backward compatibility**: existing API consumers send `type`; the alias layer must stay until `P2U/1` is documented and templates migrated.
- **Toolchain presence**: D2/pdflatex/poppler/Chrome must be in the Docker image; `p2u doctor` should fail loudly and the API should degrade gracefully.

### Suggested first PR
Phase 0 + Phase 1 parser/validator/`POST /api/compile`/`bin/p2u validate`. That single slice makes the system "declarative and agent-checkable" without touching existing deck rendering.