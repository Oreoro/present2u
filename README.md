# present2u

**Technical presentations as source code.** Write a deck once — math, diagrams,
code and layouts — and compile it to a live presenter, a self-contained HTML
file, a PDF, or speaker notes. Then let an agent drive the whole thing.

present2u started life as [Writebook](https://github.com/basecamp/writebook) and
grew a declarative presentation compiler, **P2U/1**, on top: a versioned manifest
language plus a compiler with diagnostics, a plan/apply workflow, a renderer and
an export pipeline.

```p2u
p2u: 1
deck:
  title: Attention Is All You Need
  theme: violet
slides:
  - layout: section
    title: Attention
    body: The Transformer, end to end
  - layout: two-column
    title: Scaled dot-product attention
    left:  { kind: markdown, body: "Why divide by $\\sqrt{d_k}$?" }
    right:
      kind: diagram
      lang: d2
      source: |
        direction: right
        q: "Q"
        k: "K"
        v: "V"
        q -> attn
        k -> attn
        v -> attn
  - layout: equation
    blocks:
      - kind: equation
        source: \mathrm{softmax}\!\left(\frac{QK^\top}{\sqrt{d_k}}\right)V
```

```console
$ p2u validate talk.p2u
✓ Attention Is All You Need — 3 slides

$ p2u export talk.p2u --to pdf
wrote attention-is-all-you-need.pdf
```

## Why

Writing a technical talk usually means fighting a slide tool: pasting equations
as images, redrawing diagrams, hand-laying-out code. present2u treats the deck as
a program:

- **Declarative** — describe the deck; the compiler builds it.
- **Verifiable** — diagnostics with codes, paths and hints; a density budget.
- **Idempotent** — `plan`/`apply` diffs a manifest against a deck, like Terraform.
- **Agent-friendly** — a JSON Schema, a JSON API and an MCP server.
- **Rendered** — D2 diagrams (TALA + sketch), LaTeX → SVG, KaTeX math, Rouge code.

## Get it

Present2u is **open source (MIT)** and runs on your own machine — clone it,
install the toolchain, run it. There is no hosted app to sign up for; the live
site at [p2u.focuslab.pk](https://p2u.focuslab.pk) is just a front door
(landing, agent docs, a rendered deck and a discovery MCP).

```console
$ git clone <your-fork-url> present2u
$ cd present2u/writebook
$ bin/setup                  # install gems, prepare the database
$ bin/rails server -p 3010   # http://localhost:3010
```

Requirements: **Ruby 3.4**, and `d2` (TALA), `typst`, `pdflatex` + `pdftocairo`
on your `PATH`. `bin/p2u doctor` reports what's available. `bin/p2u` finds a
modern Ruby for you (set `P2U_RUBY` to override).

A `Dockerfile` is included for container hosting; note it must be extended with
`d2`, `typst` and a TeX distribution to render diagrams and equations.

License: MIT — see [`LICENSE`](LICENSE) (a fork of
[Writebook](https://github.com/basecamp/writebook), also MIT).

## Quickstart

Requires Ruby 3.4 (the app is a Rails 8 app), plus `d2`, `pdflatex` and
`pdftocairo` for diagrams and equations. `p2u doctor` reports what's available.

```console
$ bin/setup
$ bin/p2u validate examples/raft.p2u
$ bin/p2u outline examples/raft.p2u
$ bin/p2u export examples/raft.p2u --to html
$ bin/p2u compose "a 12-slide technical deck on Raft consensus" --out raft.p2u
$ bin/dev            # the Rails app: /decks, /templates, present mode
```

## Just command about a presentation

```console
$ p2u compose "a 10-slide deck on the Transformer, with diagrams and code" --create --user you@example.com
✓ Attention Is All You Need — 10 slides (via llm)
created deck #12: The Transformer, With Diagrams and Code
```

`compose` uses an OpenAI-compatible LLM when `P2U_LLM_API_KEY` (or
`OPENAI_API_KEY`) is set, validating and **self-repairing** the generated
manifest against compiler diagnostics. Without a key it falls back to a
deterministic outline built from your prompt and any `--source` notes, so it
always produces something valid.

## The compiler

```
source ─parse─▶ manifest ─validate─▶ diagnostics ─plan─▶ render plan ─emit─▶ deck
```

| Stage | Class | What it does |
| --- | --- | --- |
| Parse | `P2u::Parser` | YAML / JSON / Markdown front matter → manifest |
| Validate | `P2u::Validator` | Schema + semantics + density → `P2u::Diagnostic[]` |
| Compile | `P2u::Compiler` | Validate and plan asset renders (deterministic hashes) |
| Emit | `P2u::Emitter` | Manifest → deck records (`Book`/`Leaf`) |
| Plan/Apply | `P2u::Planner` | Diff and idempotently apply against a deck |
| Outline | `P2u::Outliner` | Slide count, words, talk length, per-slide budget |
| Render | `P2u::Render::{Slide,Document}` | Layout-aware HTML |
| Export | `P2u::Exporter` | Self-contained HTML, Markdown notes, PDF |
| Toolchain | `P2u::Toolchain` | Report engines, binaries and versions |
| Agent | `P2u::MCP` | Model Context Protocol server over stdio |

## Layouts & blocks

19 layouts — `title`, `section`, `content`, `two-column`, `compare`,
`code-split`, `full-code`, `diagram`, `equation`, `table`, `metric-row`,
`timeline`, `quote`, `image`, `image-grid`, `references`, `recap`, `qa`, `end`.

15 blocks — `markdown`, `code`, `diagram`, `equation`, `table`, `chart`, `image`,
`video`, `metric`, `quote`, `callout`, `definition`, `references`, `notes-only`,
`spacer`. Diagram engines: `d2`, `d2-sketch`, `tala`, `mermaid`, `graphviz`,
`tikz`. Full reference: [`P2U_SPEC.md`](writebook/P2U_SPEC.md).

## Declarative plan & apply

```console
$ p2u plan talk.p2u --deck 8
plan for Attention Is All You Need: {"update" => 1, "create" => 1, "reorder" => 1}
  - update attention slides[1] {"title" => ["Attention", "Scaled dot-product attention"]}
  - create safety
  - reorder ["intro", "attention", "safety"]

$ p2u apply talk.p2u --deck 8 --user you@example.com
```

Slides are matched by stable `id` (persisted as `leaves.p2u_id`), with a
positional fallback so existing decks adopt a manifest on first apply. Applying
twice is a no-op.

## Agent surface (MCP)

```json
{ "mcpServers": { "present2u": { "command": "bin/p2u", "args": ["mcp"] } } }
```

Tools: `p2u_get_schema`, `p2u_validate`, `p2u_compile`, `p2u_compose`,
`p2u_outline`, `p2u_render`, `p2u_export`, `p2u_list_templates`, `p2u_doctor`,
`p2u_plan`, `p2u_apply`. An agent can fetch the API index from `GET /api` for
the endpoint list and MCP tool descriptions, and can compose a manifest from a
prompt, repair it from diagnostics, render it and export it.

## HTTP API

Bearer auth with a user's `api_token`.

| Method | Path | Purpose |
| --- | --- | --- |
| `GET` | `/api` | Self-describing index |
| `GET` | `/api/schema` | P2U/1 JSON Schema |
| `GET` | `/api/toolchain` | Engines, binaries, versions |
| `POST` | `/api/compile` | Parse + validate + plan |
| `POST` | `/api/compose` | Prompt → manifest (optional `create`) |
| `POST` | `/api/export` | HTML or Markdown notes |
| `POST` | `/api/decks/:id/plan` | Diff a manifest against a deck |
| `POST` | `/api/decks/:id/apply` | Apply a manifest |

## The app

The Rails side is still a full presentation app: a deck library at `/decks`, a
template gallery at `/templates` (8 ready-made technical decks), a live
presenter (16:9, keyboard/swipe nav, speaker notes, overview, sketch mode),
generative cover art, and context.dev imagery.

## Status

P2U/1 compiler, plan/apply, renderer, export and MCP are implemented and tested
(`test/models/p2u`, `test/controllers/api`). The roadmap lives in
[`PLAN.md`](PLAN.md) and the language reference in
[`P2U_SPEC.md`](writebook/P2U_SPEC.md).

## Development

```console
$ bin/rails test          # full suite
$ bin/rubocop             # style
$ bin/p2u doctor          # toolchain
```

## License

MIT — see [`writebook/MIT-LICENSE`](writebook/MIT-LICENSE).