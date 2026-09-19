---
name: present2u
description: Build and publish technical presentations with Present2u — author a P2U/1 manifest (maths, D2 diagrams, Typst, code), compile it, create/update decks, and export to HTML/PDF/notes. Use when a user asks for a technical deck, slides, a talk, a presentation, or to work with P2U/present2u manifests, the CLI, the JSON API, or the MCP tools.
---

# Present2u

Present2u compiles **P2U/1** manifests into 16:9 presentations. Diagrams (D2),
equations (LaTeX), and Typst documents render server-side to SVG; inline maths
renders with KaTeX; code is highlighted with Rouge. One light theme runs through
the app, the decks and the slides.

## When to use

- The user wants a technical deck / slides / talk / presentation.
- The user has a `.p2u` manifest or asks for one.
- The user wants to update an existing deck from source (plan/apply).
- The user wants to export a deck to HTML, PDF, or speaker notes.

## Setup (from scratch)

```console
$ git clone <repo> && cd present2u/writebook
$ bin/setup                 # bundle, db:prepare
$ bin/rails server -p 3010  # http://localhost:3010
$ bin/p2u doctor            # verify d2 / typst / pdflatex
```

Requires Ruby 3.4, and `d2`, `typst`, `pdflatex` + `pdftocairo` on PATH.

## Workflow

1. **Author** a manifest (YAML, JSON, or Markdown front-matter).
2. **Validate**: `bin/p2u validate deck.p2u` — fix diagnostics.
3. **Check density**: `bin/p2u outline deck.p2u` — ≤ ~45 words per slide.
4. **Create**: via API `POST /api/decks/import`, or `p2u_create_deck` (MCP).
5. **Update**: `bin/p2u plan` then `bin/p2u apply` (idempotent by slide `id`).
6. **Export**: `bin/p2u export deck.p2u --to html|pdf|notes`.

## Manifest essentials

```yaml
p2u: 1
deck: { title: "…", subtitle: "…", author: "…", theme: white }
slides:
  - id: intro            # stable id → clean plan/apply
    layout: section
    title: Introduction
  - layout: content
    title: Scaled dot-product attention
    body: |
      Scaling by $\sqrt{d_k}$ keeps softmax useful.

      ```d2
      direction: right
      q: Q
      k: K
      q -> attn
      k -> attn
      ```
```

Layouts: `title section content two-column compare code-split full-code diagram
equation table metric-row timeline quote image image-grid references recap qa end
divider`. Blocks: `markdown code diagram equation table chart image video metric
quote callout definition references notes-only spacer`.

## MCP

`bin/p2u mcp` (or `bin/p2u-mcp`) speaks MCP over stdio. Prefer the agentic tools:
`p2u_compose_deck` (prompt → created deck) and `p2u_create_deck`, then
`p2u_plan`/`p2u_apply` for updates. Read `p2u://guide` first.

## Rules

- Validate before creating; never ship a deck with error diagnostics.
- Keep one idea per slide; use `outline` to catch density.
- Put `id` on slides you will edit later.
- The design is one light Notion-flavoured theme — don't introduce ad-hoc colours.
- Prefer Typst for new display maths/documents; LaTeX remains supported for
  compatibility. Inline maths is always KaTeX.