import { SELF, env } from "cloudflare:test";
import { beforeAll, describe, expect, it } from "vitest";
import { createUser } from "../src/store/db";

const MANIFEST = `p2u: 1
deck:
  title: Raft
  subtitle: Consensus, end to end
slides:
  - id: intro
    layout: section
    title: Raft
  - id: log
    layout: content
    title: The log
    body: |
      An append-only sequence of entries.
  - id: eq
    layout: equation
    blocks:
      - kind: equation
        source: \\\\sum_i x_i
`;

let token = "";

beforeAll(async () => {
  const user = await createUser(env, "agent@present2u.test", "Agent");
  token = user.api_token;
});

function authed(path: string, init: RequestInit = {}): Promise<Response> {
  return SELF.fetch(`https://example.com${path}`, {
    ...init,
    headers: { "content-type": "application/json", authorization: `Bearer ${token}`, ...(init.headers ?? {}) },
  });
}

describe("compiler API", () => {
  it("serves the service index", async () => {
    const response = await SELF.fetch("https://example.com/api");
    expect(response.status).toBe(200);
    const body = await response.json<any>();
    expect(body.name).toBe("present2u");
    expect(body.endpoints.compile).toContain("/api/compile");
  });

  it("compiles a manifest without rendering", async () => {
    const response = await SELF.fetch("https://example.com/api/compile", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ source: MANIFEST }),
    });
    const body = await response.json<any>();
    expect(body.valid).toBe(true);
    expect(body.plan).toHaveLength(1);
    expect(body.plan[0].kind).toBe("latex");
  });

  it("outlines a manifest", async () => {
    const response = await SELF.fetch("https://example.com/api/outline", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ source: MANIFEST }),
    });
    const body = await response.json<any>();
    expect(body.slide_count).toBe(3);
  });

  it("composes a heuristic deck", async () => {
    const response = await SELF.fetch("https://example.com/api/compose", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ prompt: "a 6-slide deck on Raft consensus", provider: "heuristic" }),
    });
    const body = await response.json<any>();
    expect(body.provider).toBe("heuristic");
    expect(body.manifest.slides.length).toBeGreaterThanOrEqual(6);
  });

  it("reports the toolchain", async () => {
    const response = await SELF.fetch("https://example.com/api/toolchain");
    const body = await response.json<any>();
    expect(body.p2u.version).toBe("1");
    expect(body.layouts).toContain("two-column");
  });
});

describe("MCP", () => {
  it("lists tools and validates a manifest", async () => {
    const list = await SELF.fetch("https://example.com/mcp", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ jsonrpc: "2.0", id: 1, method: "tools/list" }),
    });
    const listed = await list.json<any>();
    expect(listed.result.tools.map((tool: any) => tool.name)).toContain("p2u_validate");

    const call = await SELF.fetch("https://example.com/mcp", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({
        jsonrpc: "2.0",
        id: 2,
        method: "tools/call",
        params: { name: "p2u_validate", arguments: { source: MANIFEST } },
      }),
    });
    const called = await call.json<any>();
    expect(JSON.parse(called.result.content[0].text).valid).toBe(true);
  });
});

describe("decks: import, plan, apply", () => {
  it("requires authentication", async () => {
    const response = await SELF.fetch("https://example.com/api/decks");
    expect(response.status).toBe(401);
  });

  it("is idempotent by p2u_id", async () => {
    const imported = await authed("/api/decks/import", { method: "POST", body: JSON.stringify({ source: MANIFEST }) });
    expect(imported.status).toBe(201);
    const { id } = await imported.json<any>();

    // Import already created the slides, so a plan against the same manifest is empty.
    const firstPlan = await authed(`/api/decks/${id}/plan`, { method: "POST", body: JSON.stringify({ source: MANIFEST }) });
    const planned = await firstPlan.json<any>();
    expect(planned.valid).toBe(true);
    expect(planned.actions).toHaveLength(0);

    const firstApply = await authed(`/api/decks/${id}/apply`, { method: "POST", body: JSON.stringify({ source: MANIFEST }) });
    expect(firstApply.status).toBe(200);
    const applied = await firstApply.json<any>();
    expect(applied.result.created).toBe(0);
    expect(applied.result.updated).toBe(0);

    const read = await authed(`/api/decks/${id}`);
    const deck = await read.json<any>();
    const ids = deck.slides.map((slide: any) => slide.id);

    // Re-applying the same manifest is a no-op and preserves slide ids.
    const secondApply = await authed(`/api/decks/${id}/apply`, { method: "POST", body: JSON.stringify({ source: MANIFEST }) });
    const reapplied = await secondApply.json<any>();
    expect(reapplied.result.created).toBe(0);
    expect(reapplied.result.updated).toBe(0);
    expect(reapplied.result.deleted).toBe(0);

    const reread = await authed(`/api/decks/${id}`);
    const redeck = await reread.json<any>();
    expect(redeck.slides.map((slide: any) => slide.id)).toEqual(ids);
  });

  async function freshDeck(source: string): Promise<number> {
    const imported = await authed("/api/decks/import", { method: "POST", body: JSON.stringify({ source }) });
    const { id } = await imported.json<any>();
    return id;
  }

  it("plans an update when a slide body changes", async () => {
    const id = await freshDeck(MANIFEST);
    const edited = MANIFEST.replace("An append-only sequence of entries.", "A replicated, append-only log.");
    const response = await authed(`/api/decks/${id}/plan`, { method: "POST", body: JSON.stringify({ source: edited }) });
    const plan = await response.json<any>();
    expect(plan.summary.update).toBe(1);
    expect(plan.summary.delete ?? 0).toBe(0);
    expect(plan.summary.create ?? 0).toBe(0);
  });

  it("plans a delete when a slide is removed", async () => {
    const id = await freshDeck(MANIFEST);
    const removed = MANIFEST.replace(
      "  - id: eq\n    layout: equation\n    blocks:\n      - kind: equation\n        source: \\\\sum_i x_i\n",
      "",
    );
    const response = await authed(`/api/decks/${id}/plan`, { method: "POST", body: JSON.stringify({ source: removed }) });
    const plan = await response.json<any>();
    expect(plan.summary.delete).toBe(1);
    expect(plan.summary.update ?? 0).toBe(0);
  });

  it("plans a create when a slide is added", async () => {
    const id = await freshDeck(MANIFEST);
    const added = MANIFEST.concat("  - id: safety\n    layout: content\n    title: Safety\n    body: Leader completeness.\n");
    const response = await authed(`/api/decks/${id}/plan`, { method: "POST", body: JSON.stringify({ source: added }) });
    const plan = await response.json<any>();
    expect(plan.summary.create).toBe(1);
    expect(plan.summary.update ?? 0).toBe(0);
  });

  it("applies a create and keeps existing slide ids", async () => {
    const id = await freshDeck(MANIFEST);
    const before = await (await authed(`/api/decks/${id}`)).json<any>();
    const beforeIds = before.slides.map((slide: any) => slide.id);

    const added = MANIFEST.concat("  - id: safety\n    layout: content\n    title: Safety\n    body: Leader completeness.\n");
    const applied = await (await authed(`/api/decks/${id}/apply`, { method: "POST", body: JSON.stringify({ source: added }) })).json<any>();
    expect(applied.result.created).toBe(1);

    const after = await (await authed(`/api/decks/${id}`)).json<any>();
    expect(after.slides.map((slide: any) => slide.id).slice(0, beforeIds.length)).toEqual(beforeIds);
    expect(after.slides.map((slide: any) => slide.p2u_id)).toContain("safety");
  });
});