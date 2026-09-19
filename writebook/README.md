# Present2u

**Technical presentations as source code.** Write a deck once — maths, diagrams,
code and layouts — and compile it to a live presenter, a self-contained HTML
file, a PDF, or speaker notes. Then let an agent drive the whole thing.

This directory is the Rails application. The compiler is **P2U/1**, a declarative
manifest language with diagnostics, a plan/apply workflow, a renderer and an
export pipeline.

> This app is a fork of [Writebook](https://github.com/basecamp/writebook); the
> product documentation lives in the repository root `README.md`, and the agent
> guide is in `llms.txt` / `SKILL.md`.

## Run it

Requires **Ruby 3.4**, plus `d2` (TALA), `typst`, and `pdflatex` + `pdftocairo`
on your `PATH`. Node is used for the front-end.

```console
$ bin/setup                  # install gems, prepare the database
$ bin/rails server -p 3010   # http://localhost:3010
$ bin/p2u doctor             # verify the toolchain (d2 / typst / pdflatex)
```

`bin/p2u` finds a modern Ruby for you; if it can't, set `P2U_RUBY=/path/to/ruby`.

## Author a deck

```yaml
# talk.p2u
p2u: 1
deck:
  title: Attention Is All You Need
  theme: white
slides:
  - id: intro
    layout: section
    title: Attention
  - layout: equation
    blocks:
      - kind: equation
        source: \mathrm{softmax}\!\left(\frac{QK^\top}{\sqrt{d_k}}\right)V
```

```console
$ bin/p2u validate talk.p2u
$ bin/p2u outline  talk.p2u
$ bin/p2u export   talk.p2u --to html --out talk.html
$ bin/p2u export   talk.p2u --to notes
```

Exports are single-file HTML decks (diagrams and equations are inlined); maths,
code and the Markdown runtime are loaded from a CDN, so open them online or
bundle the assets for fully offline use.

## Drive it from an agent

```console
$ bin/p2u mcp        # MCP over stdio (bin/p2u-mcp is the same, Ruby-safe wrapper)
```

Tools: `p2u_guide`, `p2u_get_schema`, `p2u_validate`, `p2u_compile`,
`p2u_outline`, `p2u_compose`, `p2u_render`, `p2u_export`, `p2u_list_templates`,
`p2u_list_decks`, `p2u_get_deck`, `p2u_create_deck`, `p2u_compose_deck`,
`p2u_plan`, `p2u_apply`, `p2u_doctor`. Read `llms.txt` or call `p2u_guide` first.

## HTTP API

Authenticate with `Authorization: Bearer <user.api_token>`. `GET /api` is a
self-describing index of the API; see also `/api/schema` and `/api/toolchain`.

## Deploying

The app ships with a `Dockerfile`. The static site + remote MCP for the edge is
in `../cloudflare/` (`./deploy.sh` → Cloudflare Workers).