import { SELF, env } from "cloudflare:test";
import { beforeAll, describe, expect, it } from "vitest";
import { createDeck, createUser, replaceSlides } from "../src/store/db";
import { createExport, exportKey, getExport } from "../src/store/exports";
import { runExport } from "../src/lib/export-job";
import { markdownToHtml } from "../src/render/markdown";
import { renderSlide } from "../src/render/slide";
import { renderDocument } from "../src/render/document";

const MARKDOWN = `p2u: 1
deck:
  title: Markdown Deck
  theme: white
slides:
  - id: intro
    layout: content
    title: Hello
    body: |
      This is **bold** and a list:

      - one
      - two

      \`\`\`js
      const x = 1;
      \`\`\`
`;

describe("server-side Markdown", () => {
  it("renders Markdown, lists and highlighted code", async () => {
    const html = await markdownToHtml("This is **bold**.\n\n- one\n- two\n\n```js\nconst x = 1;\n```");
    expect(html).toContain("<strong>bold</strong>");
    expect(html).toContain("<ul>");
    expect(html).toContain('class="hljs"');
    expect(html).toContain("const");
  });

  it("escapes raw HTML (html: false)", async () => {
    const html = await markdownToHtml('<script>alert(1)</script>');
    expect(html).not.toContain("<script>");
    expect(html).toContain("&lt;script&gt;");
  });

  it("renders a slide with a server-rendered heading and body", async () => {
    const html = await renderSlide({ id: "intro", layout: "content", title: "Hello", body: "Some **body**." });
    expect(html).toContain('p2u-slide__inner--content');
    expect(html).toContain('<h2 class="p2u-heading">Hello</h2>');
    expect(html).toContain("<strong>body</strong>");
  });

  it("builds a self-contained document with palette variables", async () => {
    const html = await renderDocument(env, {
      deck: { title: "Markdown Deck", theme: "white" },
      slides: [{ html: "<p>hi</p>", layout: "content", kicker: null, notes: "n" }],
      title: "Markdown Deck",
    });
    expect(html).toContain("<!DOCTYPE html>");
    expect(html).toContain("theme--white");
    expect(html).toContain("--p2u-fg: #37352f");
    expect(html).toContain("data-p2u-counter");
  });
});

describe("export API", () => {
  let token = "";
  let deckId = 0;

  beforeAll(async () => {
    const user = await createUser(env, "exporter@present2u.test", "Exporter");
    token = user.api_token;
    deckId = await createDeck(env, user.id, { slug: "md-deck", title: "Markdown Deck", theme: "white" });
    await replaceSlides(env, deckId, [
      { p2u_id: "intro", layout: "content", title: "Hello", kind: "content", body: "Some **body**." },
    ]);
  });

  it("compiles an exported HTML deck from a manifest", async () => {
    const response = await SELF.fetch("https://example.com/api/export", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ source: MARKDOWN, to: "html" }),
    });
    expect(response.status).toBe(200);
    const body = await response.json<any>();
    expect(body.content).toContain("<!DOCTYPE html>");
    expect(body.content).toContain("<strong>bold</strong>");
    expect(body.content).toContain('class="hljs"');
  });

  it("exports speaker notes as Markdown", async () => {
    const response = await SELF.fetch("https://example.com/api/export", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ source: MARKDOWN, to: "notes" }),
    });
    const body = await response.json<any>();
    expect(body.content).toContain("# Markdown Deck");
  });

  it("queues an export job and stores the artifact in R2", async () => {
    const response = await SELF.fetch(`https://example.com/api/decks/${deckId}/export`, {
      method: "POST",
      headers: { "content-type": "application/json", authorization: `Bearer ${token}` },
      body: JSON.stringify({ format: "html" }),
    });
    expect(response.status).toBe(202);
    const { id } = await response.json<any>();

    // The queue consumer isn't drained in tests, so run the job directly.
    await runExport(env, id, deckId, "html");

    const row = await getExport(env, id);
    expect(row?.status).toBe("done");

    const object = await env.BLOBS.get(exportKey(deckId, id, "html"));
    expect(object).not.toBeNull();
    expect(await object!.text()).toContain("Markdown Deck");

    const status = await SELF.fetch(`https://example.com/api/exports/${id}`, {
      headers: { authorization: `Bearer ${token}` },
    });
    const statusBody = await status.json<any>();
    expect(statusBody.status).toBe("done");
    expect(statusBody.url).toBe(`/api/exports/${id}/download`);

    const download = await SELF.fetch(`https://example.com/api/exports/${id}/download`, {
      headers: { authorization: `Bearer ${token}` },
    });
    expect(download.headers.get("content-type")).toContain("text/html");
    expect(await download.text()).toContain("Markdown Deck");
  });

  it("requires authentication for export status", async () => {
    const response = await SELF.fetch("https://example.com/api/exports/1");
    expect(response.status).toBe(401);
  });
});

describe("rate limiting", () => {
  it("returns 429 after the per-minute budget", async () => {
    const request = () =>
      SELF.fetch("https://example.com/api/compose", {
        method: "POST",
        headers: { "content-type": "application/json", "cf-connecting-ip": "203.0.113.9" },
        body: JSON.stringify({ prompt: "a deck", provider: "heuristic" }),
      });

    let sawLimit = false;
    for (let index = 0; index < 15; index++) {
      const response = await request();
      if (response.status === 429) {
        sawLimit = true;
        expect(response.headers.get("retry-after")).toBeTruthy();
        break;
      }
    }
    expect(sawLimit).toBe(true);
  });
});