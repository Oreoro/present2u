# Present2u Cloud — running P2U on Cloudflare

> **Goal:** turn Present2u from a self-hosted Rails app into an online, per-user
> service that runs on Cloudflare's edge. The compiler core moves to TypeScript
> in a Worker; only the native renderers (D2, Typst, LaTeX, Chrome) stay in a
> Cloudflare Container.

This document is the architecture plan. `src/` is the scaffold that follows it.

---

## Status

**Implemented and verified**

- Compiler core in TypeScript (`src/compiler/`): parser (YAML/JSON/Markdown
  front-matter), manifest normalisation, validator + density budget, outliner,
  compiler + asset plan, emitter, planner (pure diff), exporter, composer
  (Workers AI + deterministic heuristic), toolchain report.
- **Digest parity with Ruby is exact** — `src/render/digest.ts` reproduces
  `RenderedAsset#cache_key` byte-for-byte (including Ruby `Array#inspect`),
  checked across d2/d2-sketch/latex/typst/dark/empty cases.
- Cloudflare bindings: D1, KV, R2, `Workspace` DO, `RendererContainer`
  (Containers), Queue, Workers AI, static `ASSETS`.
- Routes: `/api` (compile, outline, compose, render, export, schema, toolchain,
  health), `/api/decks` (list, import, read, plan, apply), `/auth` (magic link),
  `/rendered/:digest.svg`, `/mcp`.
- **Plan-based apply**: create/update/delete/reorder executed by stable
  `p2u_id`, idempotent, serialised through the per-user `Workspace` DO.
- **Server-side Markdown**: markdown-it + highlight.js render slide bodies and
  exports in the Worker; special fences (d2, d2-sketch, latex, typst) resolve to
  content-addressed SVGs, which `renderDocument` inlines from R2 so exports are
  self-contained.
- **Async exports**: `POST /api/decks/:id/export` enqueues a job; the queue
  consumer renders HTML/notes/PDF, stores it in R2 and records it in `exports`;
  `GET /api/exports/:id` reports status and `/download` streams the artifact.
- **Rate limiting**: per-minute fixed-window limits (KV) on the expensive
  endpoints (compile, outline, compose, render, export).
- Render container (`container/`): `server.mjs` + `Dockerfile`; D2, Typst and
  LaTeX render with the Ruby recolor/transparency steps. Verified locally.
- Tests: `npm test` runs the compiler unit suite **and** full API/render/export
  integration suites inside workerd against real local D1/KV/R2/DO (35 tests).

**Remaining**

- Provisioning + deploy (`npm run setup`, `npm run deploy`) needs an interactive
  `wrangler login`.
- Optional: swap the D2/Typst container calls for WASM to drop the container for
  the common case; trim highlight.js to the languages actually used.
- Optional: distributed (rather than KV-approximate) rate limiting.

---

## Deployment (live)

Deployed to the `p2u.focuslab.pk` custom domain on the account
`bilalpakistan2002@gmail.com`:

| Resource | Value |
| --- | --- |
| Worker | `present2u` (Version `123cc917…`) |
| D1 | `present2u` — `c44f80e6-a8ab-4a2a-9df2-60e0a11f61e9` (WEUR) |
| KV | `present2u-cache` — `fbaad263589b4043b270591de6919976` |
| R2 | `present2u-blobs` |
| Queue | `present2u-exports` (producer + consumer) |
| Container | `present2u-renderercontainer` — `a03d468b-7fc6-41a0-9c86-8007a9380d48` |
| Cron | `*/5 * * * *` (keeps the renderer warm) |
| Secret | `SESSION_SECRET` |
| PDF | Cloudflare Browser Rendering (`BROWSER` binding) |
| Client renderers | KaTeX (math), Typst WASM (`typst.ts`), D2 WASM (self-hosted at `/d2`) |

The landing page is at `/`; the machine surfaces are the API, `/mcp` and the
exported HTML decks.

Verified live (16-point smoke test): `/`, `/api/health`, `/api/schema`,
`/api/templates`, `/api/toolchain`, `/api/compile`, `/api/outline`,
`/api/compose`, `/api/export` (html/notes), `/api/export?to=pdf` (valid PDF via
Browser Rendering), `/api/decks` import/list/get/plan/apply (idempotent),
`/api/decks/:id/export` queue → R2 → `/api/exports/:id/download`, `/mcp`
(12 tools), `/d2/index.js`, and 401 on unauthenticated deck access.

### Rendering (no container needed)

Because the account's container quota is exhausted (see below), rendering runs
client-side in the exported deck, where WASM size is not a constraint:

- **Math / LaTeX** — KaTeX renders `$…$` and `\[…\]` in the browser. Verified:
  in a PDF export the fraction renders as `a/b` and the raw `\frac` is gone.
- **Typst** — `typst.ts` WASM (compiler + renderer) renders ` ```typst ` blocks
  client-side. Verified locally (19 KB SVG from `= Hello`).
- **D2** — the npm browser build ships without `d2.wasm`, so the build and WASM
  are self-hosted at `/d2/` (served with CORS). Verified end-to-end: the PDF
  export now shows the rendered diagram (raw `direction: right` / `a: Input`
  source gone; only the node labels remain).
- **PDF** — rendered by Browser Rendering, which waits for
  `window.__p2uRenderComplete` before printing so the client renderers finish.

### Container caveat (server-side SVG)

The render container image builds, pushes, and reaches `running`, but the
Container Durable Object cannot attach an instance: the account returns
**"Maximum number of running container instances exceeded"** — the account's
container quota is consumed by its other apps (~14 instances). Tried
`basic`/`standard-1`, region pins, a DO `locationHint`, app recreate, a warm-up
cron and a slimmer image. Consequently `/api/render` and `/api/toolchain` return
a graceful `503 renderer_unavailable`; diagrams/equations still render in the
exported deck via the client renderers above. If capacity frees up, the next
cron tick or `npm run deploy` will attach an instance with no code changes.

---

## 1. Why this split

The Ruby compiler is mostly **pure and deterministic** — it never touches a
database except in `Planner`/`Emitter`. Only three classes shell out to native
binaries (`D2Diagram`, `LatexEquation`, `TypstDocument`) and one to Chrome
(`Exporter#to_pdf`). That maps cleanly onto two runtimes:

| Ruby | Runtime at the edge | Notes |
| --- | --- | --- |
| `Parser`, `Manifest`, `Diagnostic` | Worker (TS) | pure |
| `Layouts`, `Blocks` | Worker (TS) | pure registries |
| `Validator`, `Outliner` | Worker (TS) | pure |
| `Compiler`, `Emitter` | Worker (TS) | pure (`render: true` calls assets) |
| `Render::Slide`, `Render::Document`, `Exporter#to_html/#to_notes` | Worker (TS) | pure string building |
| `Planner` | Worker (TS) + D1/DO | diff is pure; apply writes storage |
| `Composer` (+ `LLM`) | Worker (TS) + Workers AI | heuristic is pure |
| `D2Diagram` | Container | `d2` binary; WASM later |
| `LatexEquation` | Container | `pdflatex` + `pdftocairo` |
| `TypstDocument` | Container | `typst` binary; WASM later |
| `Exporter#to_pdf` | Container | headless Chrome |
| `MCP`, `CLI` | Worker (`/mcp`) / `bin/p2u` | MCP already partly at the edge |

Rationale: the pure 90% runs at every edge location with no cold start; the
native 10% is amortised in a container pool behind a content-addressed cache.

---

## 2. Topology

```
                       ┌──────────────────────── Cloudflare edge ───────────────────────┐
   browser / agent     │                                                                 │
   ───────────────▶    │   Worker  (Hono router)                                         │
   fetch / MCP         │    ├─ compiler/*      parse · validate · outline · compile ·    │
                       │    │                  emit · export(html|notes) · compose       │
                       │    ├─ /api/*          JSON API                                  │
                       │    ├─ /mcp            remote MCP (JSON-RPC 2.0)                 │
                       │    └─ /                static site (ASSETS binding)             │
                       │         │            │            │            │                │
                       │         ▼            ▼            ▼            ▼                │
                       │       D1           KV           R2        WORKSPACE (DO)        │
                       │   users/decks   asset meta   SVGs/PDF   per-user working set    │
                       │   /slides       doc cache    exports    (in-memory + flush)     │
                       │         │                                                       │
                       │         ▼                                                       │
                       │   RENDERER (Container DO)  →  d2 · typst · pdflatex · chrome     │
                       │                                                                 │
                       │   AI (Workers AI)  →  compose()                                 │
                       └─────────────────────────────────────────────────────────────────┘
```

### Bindings

| Binding | Type | Purpose |
| --- | --- | --- |
| `ASSETS` | Static assets | landing site, docs, `schema.json` |
| `DB` | D1 | users, decks, slides, tokens, exports |
| `CACHE` | KV | content-addressed asset metadata + doc/HTML cache |
| `BLOBS` | R2 | rendered SVGs, exported HTML/PDF artifacts |
| `WORKSPACE` | Durable Object | per-user working set ("local memory"), serialises apply |
| `RENDERER` | Durable Object (Container) | native render farm |
| `AI` | Workers AI | compose LLM |
| `EXPORTS` | Queue | async PDF/HTML export jobs |

---

## 3. Data model (D1)

Mirrors the Rails `Book → Leaf → Leafable` shape, flattened to three tables so
the edge can query without a polymorphic join:

- `users` — id, email, name, api_token, created_at.
- `decks` — id, user_id, slug, title, subtitle, author, theme, aspect, format, meta(json).
- `slides` — id, deck_id, p2u_id, position, layout, title, notes, sketch, kind
  (`markdown`/`typst`/`section`/`picture`), body, source, caption, image_url.
- `sessions` — magic-link tokens (hashed, short-lived).
- `assets` — digest → r2_key, kind, bytes, created_at (metadata; bytes live in R2).

`p2u_id` is the stable slide identity that makes `plan`/`apply` idempotent, exactly
as `leaves.p2u_id` does today.

---

## 4. The asset cache

`RenderedAsset` is content-addressed by `sha256(kind \0 sorted(options) \0 source)`.
We keep that contract byte-for-byte so the same manifest yields the same digest
on both runtimes. `src/render/assets.ts`:

1. compute the digest;
2. `HEAD` R2 — if present, return `/rendered/<digest>.svg` (served from R2);
3. otherwise call the `RENDERER` container, store the SVG in R2 + KV metadata;
4. `cache-control: public, max-age=31536000, immutable` at the edge.

A toolchain version bump is folded into the digest (add `toolchain` to the cache
key) so upgrading D2/Typst invalidates only affected assets.

---

## 5. The render container

`container/` packages a small HTTP service:

```
POST /render { kind, source, options } -> { svg }        d2 | typst | latex
POST /pdf { html }                      -> { pdf }        headless Chrome
GET  /health                            -> toolchain versions
```

It is invoked through the `RENDERER` Durable Object (Cloudflare Containers),
which keeps one warm instance per colo and enforces timeouts/output caps. The
Ruby `P2u::Toolchain.report` becomes `GET /api/toolchain`, fed by `/health`.

---

## 6. Per-user "local" data

Two layers, so the common case never touches disk:

- **`WORKSPACE` Durable Object** — one per user. Holds the parsed deck + render
  plan in memory, debounces writes, and serialises `apply` so concurrent agents
  can't interleave create/update/delete. Flushes to D1 on quiesce.
- **D1** — durable source of truth, queryable, cross-device.
- **KV** — hot read-through cache for deck JSON and rendered HTML.

"Locally hosted in cache or memory" = the DO's in-memory working set, fronted by
KV. The edge is still the only server; nothing is required to run on the user's
machine.

---

## 7. Auth

- **Email magic link** — `POST /auth/start` stores a hashed token in `sessions`,
  emails a link via Cloudflare Email Service (or Resend); `GET /auth/callback`
  sets a signed session cookie.
- **API tokens** — `users.api_token`, `Authorization: Bearer <token>` for agents
  and the CLI, matching the existing `/api` contract.

---

## 8. Route map

```
GET  /                         landing (static)
GET  /rendered/:digest.svg     content-addressed asset (R2 → cache)
GET  /api                      service index
GET  /api/schema               P2U/1 JSON Schema
GET  /api/toolchain            renderer /health
GET  /api/templates            built-in templates
POST /api/compile              validate + plan (no writes)
POST /api/outline              slide budget
POST /api/compose              prompt -> manifest
POST /api/export               manifest -> html | notes | pdf
POST /api/render               single d2/latex/typst -> svg
GET  /api/decks                list decks
POST /api/decks/import         manifest -> deck
GET  /api/decks/:id            deck + slide ids
POST /api/decks/:id/plan       diff
POST /api/decks/:id/apply      idempotent apply
GET/POST /mcp                  remote MCP
POST /auth/start|/auth/callback
```

---

## 9. Build order

1. **Scaffold** (this pass) — config, schema, compiler module layout, stubs.
2. **Compiler core** — port parser/validator/outliner/compiler/emitter; golden
   tests against the Ruby output.
3. **Container** — Dockerfile + render service; wire `RENDERER`.
4. **Assets** — R2/KV cache + `/rendered/:digest.svg`.
5. **Storage + auth** — D1, magic link, API tokens, `Workspace` DO.
6. **Planner/Exporter/Composer** — plan/apply, HTML/PDF/notes, Workers AI.
7. **Parity** — run the Ruby test corpus through the TS compiler and diff.

---

## 10. Open questions

- **D2/Typst WASM** would remove the container for the common case (d2 has an
  official WASM build; `typst.ts` exists). Defer until the container proves the
  contract.
- **PDF** genuinely needs Chrome; keep it a container-only, async, queue-backed
  feature.
- **Digest parity** across Ruby/TS must be tested explicitly — `options` sorting
  and string coercion are the sharp edges.