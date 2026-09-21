import { env } from "cloudflare:test";
import { describe, expect, it } from "vitest";
import { renderSlide } from "../src/render/slide";
import { markdownToHtml } from "../src/render/markdown";
import { renderDocument } from "../src/render/document";

const MANIFEST = {
  p2u: 1,
  deck: { title: "Render", theme: "white" },
  slides: [
    {
      id: "eq",
      layout: "equation",
      blocks: [{ kind: "equation", source: "\\frac{a}{b}" }],
    },
    {
      id: "d2",
      layout: "diagram",
      blocks: [{ kind: "diagram", lang: "d2", source: "a -> b" }],
    },
    {
      id: "md",
      layout: "content",
      body: "Inline math $x^2$ and a fence:\n\n```latex\n\\sqrt{d_k}\n```\n\n```d2\nx -> y\n```",
    },
  ],
};

describe("client-side rendering fallback", () => {
  it("renders equations as client-side KaTeX display math", async () => {
    const html = await renderSlide(MANIFEST.slides[0] as any, {});
    expect(html).toContain("p2u-tex");
    expect(html).toContain("\\[");
    expect(html).not.toContain("/rendered/");
  });

  it("renders D2 blocks as client-side D2 when no server renderer", async () => {
    const html = await renderSlide(MANIFEST.slides[1] as any, {});
    expect(html).toContain('class="p2u-d2"');
    expect(html).toContain("a -&gt; b");
  });

  it("converts latex and d2 fences in Markdown bodies", async () => {
    const html = await markdownToHtml("\\[\\sqrt{d_k}\\]\n\n```d2\nx -> y\n```");
    expect(html).toContain("p2u-d2");
    expect(html).toContain("x -&gt; y");
  });

  it("falls back to client rendering when the asset store throws", async () => {
    const failing = () => Promise.reject(new Error("container unavailable"));
    const html = await renderSlide(MANIFEST.slides[1] as any, { assetStore: failing as any });
    expect(html).toContain('class="p2u-d2"');
  });

  it("ships the D2/Typst client renderers in the exported document", async () => {
    const html = await renderDocument(env, {
      deck: MANIFEST.deck,
      slides: [{ html: '<div class="p2u-d2">a -&gt; b</div>', layout: "diagram", kicker: null, notes: null }],
      title: "Render",
    });
    expect(html).toContain("@terrastruct/d2");
    expect(html).toContain("@myriaddreamin/typst.ts");
    expect(html).toContain("/d2/index.js");
    expect(html).toContain("__p2uRenderComplete");
    expect(html).toContain("renderMathInElement");
  });
});