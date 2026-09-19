# P2U/1 — the present2u presentation language

P2U/1 is a declarative manifest for technical presentations. You describe *what*
the deck contains; the compiler parses, validates, plans and emits it. The same
manifest can be written as YAML, JSON or Markdown, and is compiled to the same
abstract slide model.

```
source ──parse──▶ manifest ──validate──▶ diagnostics ──plan──▶ render plan ──emit──▶ deck
```

- **Schema:** `GET /api/schema` (JSON Schema 2020-12, also in `config/schemas/p2u-1.schema.json`)
- **Toolchain:** `GET /api/toolchain`, `bin/p2u doctor`
- **Compile:** `POST /api/compile`, `bin/p2u validate|compile`
- **Ruby:** `P2u.compile(source, format: nil, render: false)`

## Surfaces

### YAML (canonical)

```yaml
p2u: 1
deck:
  title: Raft consensus
  theme: violet
slides:
  - layout: section
    title: Raft
  - layout: content
    title: Leader election
    body: A **leader** is elected by a majority.
```

### JSON

```json
{ "p2u": 1, "deck": { "title": "Raft" }, "slides": [ { "layout": "content", "body": "Hi" } ] }
```

### Markdown

Front matter carries the deck, `---` separates slides, `#` makes a section and
`##` a content slide.

```markdown
---
title: Raft consensus
theme: violet
---

# Raft

Consensus, made understandable.

---

## Leader election

A **leader** is elected by a majority.
```

## Deck fields

| Field | Type | Notes |
| --- | --- | --- |
| `p2u` | `"1"` | Language version. Missing is assumed to be `1`. |
| `deck.title` | string | Deck title. |
| `deck.subtitle` | string | Optional. |
| `deck.author` | string | Defaults to the creating user. |
| `deck.aspect` | `16:9`, `4:3`, `16:10` | Defaults to `16:9`. |
| `deck.theme` | string or `{ preset, tokens }` | `writebook black blue green magenta orange violet white`. |
| `deck.format` | `markdown` (default) or `typst` | Authoring language for slide bodies. |
| `deck.defaults` | object | Default `layout`, `transition`, `diagram`, `math`. |
| `deck.meta` | object | Venue, date, license — free-form. |
| `slides` | array | One or more slides. |

### Typst-first decks

Set `deck.format: typst` to author every slide body in [Typst](https://typst.app)
instead of Markdown. Each slide's `body` is a Typst document compiled to a
single 16:9 SVG with the `typst` CLI and embedded in the slide — there is no
Markdown step. A slide may override with its own `format: typst|markdown`.

```yaml
deck:
  title: Raft in Typst
  format: typst
slides:
  - layout: content
    body: |
      = Quorums
      Any two quorums intersect.
      $ q = floor(N/2) + 1 $
```

A slide body is just content — the Present2u slide theme is applied for you:
16:9 page, typography, heading/code/link styling, and an auto-fit wrapper so a
long slide scales down instead of spilling onto a second page. Two helpers are
available:

- `#p2u-title("Title", subtitle: "Subtitle")` — a centred title slide
- `#p2u-fit[...]` — applied automatically to every slide body

In the app, Typst slides are a first-class leafable (`Typst`): create one from
the deck toolbar, edit the source with a live preview, and present it like any
other slide. Fenced ` ```typst ` blocks are raw figures (no theme) — the author
controls the page.

## Slide fields

| Field | Type | Notes |
| --- | --- | --- |
| `id` | string | Stable identity; derived from the title when omitted. |
| `layout` | enum | See below. Defaults to `content`. |
| `type` | string | Legacy alias for `layout` (`divider`, `page`, `picture`). |
| `title` / `subtitle` | string | |
| `body` | string | Markdown shorthand for a single markdown block. |
| `blocks` | array | Typed content blocks. |
| `left` / `right` / `code` / `prose` | block or string | Slots for column layouts. |
| `notes` | string | Speaker-only notes. |
| `theme` | string | Section theme override. |
| `sketch` | boolean | Hand-drawn theme for the slide. |
| `reveal` | array of integers | Progressive build steps. |
| `caption` / `image_url` | string | Image slide shorthand. |

## Layouts

| Layout | Requires | Purpose |
| --- | --- | --- |
| `title` | title | Deck or talk title |
| `section` | title | Section divider |
| `content` | body or blocks | Markdown content |
| `two-column` | left, right | Two content columns |
| `compare` | left, right | Side-by-side comparison |
| `code-split` | code, prose | Code beside prose |
| `full-code` | a `code` block | Full-bleed code |
| `diagram` | a `diagram` block | Diagram focus |
| `equation` | an `equation` block | Equation focus |
| `table` | — | Data table |
| `metric-row` | a `metric` block | KPI cards |
| `timeline` | — | Timeline or roadmap |
| `quote` | — | Pull quote |
| `image` | — | Image slide |
| `image-grid` | an `image` block | Image gallery |
| `references` | — | Bibliography |
| `recap` | — | Summary |
| `qa` | — | Questions |
| `end` | — | Closing slide |

## Blocks

Blocks are the typed units inside `blocks` (or a slot). Each compiles to the
markdown the renderer already understands.

| Block | Required | Renders as |
| --- | --- | --- |
| `markdown` | `body` | Inline Markdown with `$math$` |
| `code` | `source` | Rouge-highlighted fenced code (`lang`) |
| `diagram` | `source` | ` ```d2 `/` ```d2-sketch `/` ```typst `/Mermaid etc. |
| `equation` | `source` | ` ```latex ` → cropped SVG |
| `table` | — | Markdown table (`columns` + `rows`) |
| `chart` | — | Chart from inline data |
| `image` | `url`/`src`/`image_url` | `![alt](url)` |
| `video` | `url` | Link |
| `metric` | `value`, `label` | `**label:** value` |
| `quote` | `text` | Blockquote, optional `attribution` |
| `callout` | `body` | Callout (optional `tone`) |
| `definition` | `term`, `body` | `**term** — body` |
| `references` | `items` | Bulleted bibliography |
| `notes-only` | `body` | Speaker notes only, hidden on the slide |
| `spacer` | — | Horizontal rule |

Diagram engines: `d2`, `d2-sketch`, `tala`, `typst`, `mermaid`, `graphviz`, `tikz`.
` ```typst ` compiles the snippet with the `typst` CLI to a self-contained SVG
(page background transparent, black text re-pointed at `currentColor`).

## Diagnostics

The validator returns machine-readable diagnostics. Each has `severity`
(`error`/`warning`/`info`), a `code`, a human `message`, and the `slide`/`path`
where it occurred.

| Code | Severity | Meaning |
| --- | --- | --- |
| `parse_error` | error | Source could not be parsed. |
| `unsupported_version` | error | `p2u` is not `1`. |
| `missing_version` | warning | No `p2u` declared; assumed `1`. |
| `missing_title` | warning | Deck has no title. |
| `unknown_theme` | error | Theme is not one of the known presets. |
| `unknown_aspect` | error | Aspect ratio is not supported. |
| `unknown_layout` | error | Slide layout is not in the vocabulary. |
| `missing_field` | error | A layout-required field is absent. |
| `missing_content` | error | A content layout has neither body nor blocks. |
| `missing_slot` | error | A column layout is missing a slot. |
| `missing_block` | error | A layout requires at least one block. |
| `unknown_block` | error | Block kind is not in the vocabulary. |
| `block_not_allowed` | error | Layout does not accept this block kind. |
| `missing_block_field` | error | A block-required field is absent. |
| `unknown_engine` | error | Diagram engine is not supported. |
| `duplicate_slide_id` | error | Two slides share an `id`. |
| `slide_density` | warning | Slide exceeds the word budget. |
| `too_many_bullets` | warning | Slide exceeds the bullet budget. |
| `code_density` | warning | Slide exceeds the code-line budget. |
| `render_failed` | error | An asset compiler failed during `render: true`. |

## CLI

```
p2u validate FILE [--format json|yaml|markdown] [--json]
p2u compile  FILE [--render] [--format ...] [--json]
p2u plan     FILE --deck ID [--format ...] [--json]
p2u apply    FILE --deck ID --user EMAIL [--format ...] [--json]
p2u compose  "PROMPT" [--slides N] [--theme T] [--source FILE] [--out FILE] [--create --user EMAIL] [--json]
p2u outline  FILE [--json]
p2u export   FILE --to html|notes|pdf [--out PATH]
p2u mcp
p2u schema   [--json]
p2u doctor   [--json]
```

`FILE` may be `-` to read stdin. Exit codes: `0` valid, `1` diagnostics, `2` usage.

## API

| Method | Path | Purpose |
| --- | --- | --- |
| `GET` | `/api/schema` | P2U/1 JSON Schema |
| `GET` | `/api/toolchain` | Compiler stack and versions |
| `POST` | `/api/compile` | Parse + validate + plan (no persistence) |
| `POST` | `/api/compose` | Compose a manifest from a prompt (`{prompt, sources, slides, theme, create}`) |
| `POST` | `/api/export` | Export a manifest to self-contained HTML or Markdown notes |
| `POST` | `/api/decks/:id/plan` | Diff a manifest against a deck (read-only) |
| `POST` | `/api/decks/:id/apply` | Idempotently apply a manifest to a deck |

`POST /api/compile` accepts a manifest JSON body directly, or
`{ "source": "...", "format": "yaml", "render": true }` for raw text. Pass
`render: true` to build diagrams and equations and receive stable asset URLs.

## Plan and apply

A deck is the *desired state*; `plan` reports how the current deck differs and
`apply` brings it in line. The manifest is the source of truth, so applying the
same manifest twice is a no-op.

Slides are matched by their stable `id` (persisted as `leaves.p2u_id`). Decks
created before ids existed are matched positionally, so an existing deck can be
adopted by a manifest on first apply.

```json
{
  "valid": true,
  "deck": { "id": 8, "title": "Raft consensus", "slug": "raft-consensus" },
  "summary": { "update": 1, "create": 1, "delete": 1, "reorder": 1 },
  "actions": [
    { "action": "update", "slide": "election", "leaf_id": 21, "changes": { "title": ["Election", "Leader election"] } },
    { "action": "create", "slide": "safety" },
    { "action": "delete", "slide": "old-notes", "leaf_id": 19 },
    { "action": "reorder", "slides": ["intro", "election", "safety"] }
  ]
}
```

- `create` — the slide is not in the deck yet.
- `update` — attributes differ; `changes` maps field to `[current, desired]`.
- `delete` — a leaf in the deck is not in the manifest (soft-deleted).
- `reorder` — the relative order of matched slides differs.

Plan output is safe to show a human before applying. Invalid manifests are never
applied.

## Export

`p2u export` renders a manifest to a distributable artifact:

- `--to html` — a single self-contained file: 16:9 slides, keyboard/click
  navigation, progress, speaker notes (`N`) and print styles. Diagram, Typst and
  equation SVGs are inlined. Markdown is rendered in the browser with
  **markdown-it** (`markdown-it-texmath` → KaTeX for `$...$`/`$$...$$`,
  highlight.js for code); markdown-it, KaTeX and highlight.js load from a CDN.
- `--to notes` — speaker notes as Markdown.
- `--to pdf` — one landscape page per slide, via headless Chrome/Chromium
  (`p2u doctor` reports availability). The HTML export also prints to PDF from
  the browser.

`POST /api/export` returns the same HTML or notes as JSON.

## Use with an agent (MCP)

`bin/p2u mcp` runs a Model Context Protocol server over stdio. Point clients at
`bin/p2u-mcp`, which finds a compatible Ruby (MCP clients often launch with a
bare environment where `ruby` is an old system Ruby):

```json
{
  "mcpServers": {
    "present2u": { "command": "/absolute/path/to/writebook/bin/p2u-mcp" }
  }
}
```

`plan`/`apply` tools read and write the app database, so run against the app
checkout (set `RAILS_ENV` if not `development`). `P2U_RUBY` overrides the
interpreter.

Tools: `p2u_get_schema`, `p2u_validate`, `p2u_compile`, `p2u_compose`,
`p2u_outline`, `p2u_render`, `p2u_export`, `p2u_list_templates`, `p2u_doctor`,
`p2u_plan`, `p2u_apply`. An agent can go from a prompt to a validated, rendered,
exported deck without knowing the schema by hand.

## Compose

`p2u compose "a 12-slide technical deck on Raft consensus"` turns a request into
a P2U/1 manifest, then validates it.

- With an OpenAI-compatible LLM configured (`P2U_LLM_API_KEY` or
  `OPENAI_API_KEY`, plus optional `P2U_LLM_BASE_URL` and `P2U_LLM_MODEL`), the
  composer asks the model for a manifest and **self-repairs** it against the
  validator's diagnostics for up to two rounds.
- Without a key it uses a deterministic outline: it derives slides from any
  `--source` notes, otherwise scaffolds a standard technical narrative for the
  topic, honouring `--slides` and `--theme`.
- `--create --user EMAIL` builds the deck immediately; `--out FILE` writes the
  manifest. `POST /api/compose` supports `create: true` for the same flow.

## Outline

`p2u outline FILE` reports the slide count, total words, an estimated talk
length and a per-slide budget (words, bullets, code lines), warning when a slide
is too dense. Use it to answer "how many slides should this be?" before
rendering.

## Compatibility

Legacy manifests and API payloads using `type` (`section`, `content`/`page`,
`image`/`picture`) and `body` keep compiling: `type` is resolved to a `layout`
and `body` is treated as a single markdown block. Existing decks and the eight
built-in templates therefore validate unchanged.