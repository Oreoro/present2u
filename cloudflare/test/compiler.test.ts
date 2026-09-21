import { describe, expect, it } from "vitest";
import {
  Compiler,
  Emitter,
  Parser,
  Planner,
  Validator,
  outline,
} from "../src/compiler";
import { digestFor, cacheKey } from "../src/render/digest";

const MANIFEST = `p2u: 1
deck:
  title: Attention Is All You Need
  subtitle: The Transformer, end to end
  theme: violet
slides:
  - id: intro
    layout: section
    title: Attention
    body: The Transformer, end to end
  - id: why
    layout: content
    title: Why divide by sqrt(d_k)?
    body: |
      Scaling keeps the softmax in a useful range: $ \\\\sqrt{d_k} $.
  - id: eq
    layout: equation
    blocks:
      - kind: equation
        source: \\\\mathrm{softmax}\\\\left(\\\\frac{QK^\\\\top}{\\\\sqrt{d_k}}\\\\right)V
`;

describe("Parser", () => {
  it("parses a YAML manifest", () => {
    const manifest = Parser.parse(MANIFEST);
    expect(manifest.version).toBe("1");
    expect(manifest.deck.title).toBe("Attention Is All You Need");
    expect(manifest.slides).toHaveLength(3);
    expect(manifest.slides[0]!.layout).toBe("section");
  });

  it("normalises legacy type/body slides", () => {
    const manifest = Parser.parse('{"deck":{"title":"T"},"slides":[{"type":"page","title":"A","body":"B"}]}');
    expect(manifest.slides[0]!.layout).toBe("content");
    expect(manifest.slides[0]!.id).toBe("a-1");
  });

  it("parses Markdown front matter", () => {
    const source = `---\ndeck:\n  title: Markdown Deck\n---\n\n# Section One\n\nBody text\n\n---\n\n## Content Two\n\nMore text\n`;
    const manifest = Parser.parse(source);
    expect(manifest.deck.title).toBe("Markdown Deck");
    expect(manifest.slides.map((slide) => slide.layout)).toEqual(["section", "content"]);
  });
});

describe("Validator", () => {
  it("accepts a valid manifest", () => {
    const diagnostics = Validator.validate(Parser.parse(MANIFEST));
    expect(diagnostics.filter((diagnostic) => diagnostic.isError)).toHaveLength(0);
  });

  it("reports unknown layouts with a hint", () => {
    const manifest = Parser.parse('{"p2u":1,"deck":{"title":"T"},"slides":[{"layout":"two-columns","title":"A"}]}');
    const errors = Validator.validate(manifest).filter((diagnostic) => diagnostic.isError);
    expect(errors.some((diagnostic) => diagnostic.code === "unknown_layout")).toBe(true);
  });

  it("warns when a slide is too dense", () => {
    const body = Array.from({ length: 60 }, (_, index) => `- bullet number ${index}`).join("\n");
    const manifest = Parser.parse(JSON.stringify({ p2u: 1, deck: { title: "T" }, slides: [{ layout: "content", body }] }));
    const warnings = Validator.validate(manifest).filter((diagnostic) => diagnostic.isWarning);
    expect(warnings.some((diagnostic) => diagnostic.code === "too_many_bullets")).toBe(true);
  });
});

describe("Emitter", () => {
  it("maps layouts onto the runtime slide shape", () => {
    const slides = new Emitter(Parser.parse(MANIFEST)).slides;
    expect(slides[0]).toMatchObject({ id: "intro", layout: "section", type: "section" });
    expect(slides[2]).toMatchObject({ id: "eq", layout: "equation", type: "content" });
    expect(slides[2]!.body).toContain("```latex");
  });
});

describe("Outline", () => {
  it("counts slides and words", () => {
    const result = outline(Parser.parse(MANIFEST));
    expect(result.slide_count).toBe(3);
    expect(result.words).toBeGreaterThan(0);
  });
});

describe("Compiler", () => {
  it("plans an asset per equation/diagram without rendering", async () => {
    const result = await Compiler.compile(MANIFEST);
    expect(result.valid).toBe(true);
    expect(result.plan).toHaveLength(1);
    expect(result.plan[0]!.kind).toBe("latex");
    expect(result.plan[0]!.digest).toMatch(/^[a-f0-9]{64}$/);
    expect(result.plan[0]!.url).toBe(`/rendered/${result.plan[0]!.digest}.svg`);
  });

  it("returns a parse diagnostic rather than throwing", async () => {
    const result = await Compiler.compile("{ not json");
    expect(result.valid).toBe(false);
    expect(result.diagnostics[0]!.code).toBe("parse_error");
  });
});

describe("Asset digests", () => {
  it("is stable and order-independent over options", async () => {
    const a = await digestFor({ kind: "d2", source: "a -> b", options: { layout: "tala", theme: 301 } });
    const b = await digestFor({ kind: "d2", source: "a -> b", options: { theme: 301, layout: "tala" } });
    expect(a).toBe(b);
    expect(a).toMatch(/^[a-f0-9]{64}$/);
  });

  it("matches the Ruby cache-key shape", () => {
    expect(cacheKey("d2", "a -> b", { layout: "tala", theme: 301 })).toBe(
      'd2\u0000[["layout", "tala"], ["theme", "301"]]\u0000a -> b',
    );
  });
});

describe("Planner", () => {
  it("plans creates for an empty deck and is stable by p2u_id", () => {
    const plan = new Planner(Parser.parse(MANIFEST), []).plan();
    expect(plan.valid).toBe(true);
    expect(plan.actions.filter((action) => action.action === "create")).toHaveLength(3);
  });

  it("plans updates by p2u_id", () => {
    const existing = [
      { id: 1, p2u_id: "intro", title: "Attention", notes: null, sketch: false, layout: "section", kind: "section", body: "Old", source: null, caption: null },
    ];
    const plan = new Planner(Parser.parse(MANIFEST), existing).plan();
    expect(plan.actions.some((action) => action.action === "update" && action.slide === "intro")).toBe(true);
    expect(plan.actions.filter((action) => action.action === "create")).toHaveLength(2);
  });
});