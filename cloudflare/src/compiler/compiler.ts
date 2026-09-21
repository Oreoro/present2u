// Parses, validates and plans a manifest. Compilation is pure unless
// `render: true` is passed, in which case diagrams and equations are built and
// their stable URLs are returned in the plan. Port of p2u/compiler.rb.

import { Manifest } from "./manifest";
import type { Slide } from "./manifest";
import { Parser } from "./parser";
import { Validator } from "./validator";
import { Diagnostic, ParseError } from "./diagnostic";
import { presence } from "./util";
import { digestFor } from "../render/digest";
import type { AssetEntry, AssetKind, AssetRequest } from "../render/digest";

export interface CompileResult {
  manifest: Manifest | null;
  diagnostics: Diagnostic[];
  plan: AssetEntry[];
  valid: boolean;
}

export interface CompileOptions {
  format?: string;
  render?: boolean;
  /** Renders and stores an asset, returning its stable URL. Required when render is true. */
  store?: (request: AssetRequest) => Promise<string>;
}

export class Compiler {
  private readonly manifest: Manifest;

  constructor(manifest: Manifest) {
    this.manifest = manifest;
  }

  static async compile(source: unknown, options: CompileOptions = {}): Promise<CompileResult> {
    let manifest: Manifest;
    try {
      manifest = source instanceof Manifest ? source : Parser.parse(source, options.format);
    } catch (error) {
      const diagnostic =
        error instanceof ParseError
          ? new Diagnostic("error", "parse_error", error.message)
          : new Diagnostic("error", "parse_error", (error as Error).message);
      return { manifest: null, diagnostics: [diagnostic], plan: [], valid: false };
    }

    return new Compiler(manifest).compile(options);
  }

  async compile(options: CompileOptions = {}): Promise<CompileResult> {
    const diagnostics = Validator.validate(this.manifest);
    let plan: AssetEntry[] = [];

    if (!diagnostics.some((diagnostic) => diagnostic.isError)) {
      const requests = assetRequests(this.manifest);
      plan = [];
      for (const request of requests) {
        plan.push(await this.compileAsset(request, options, diagnostics));
      }
    }

    return {
      manifest: this.manifest,
      diagnostics,
      plan,
      valid: !diagnostics.some((diagnostic) => diagnostic.isError),
    };
  }

  private async compileAsset(
    request: AssetRequest,
    options: CompileOptions,
    diagnostics: Diagnostic[],
  ): Promise<AssetEntry> {
    const digest = await digestFor(request);
    const entry: AssetEntry = {
      slide: request.slide,
      kind: request.kind,
      digest,
      url: `/rendered/${digest}.svg`,
      rendered: false,
    };

    if (options.render) {
      if (!options.store) throw new Error("compile(render: true) requires a store callback");
      try {
        entry.url = await options.store(request);
        entry.rendered = true;
      } catch (error) {
        diagnostics.push(
          new Diagnostic("error", "render_failed", `${request.kind} render failed: ${(error as Error).message}`, {
            slide: request.slide,
          }),
        );
      }
    }

    return entry;
  }
}

/** Every asset-producing block in the deck, in slide order. */
export function assetRequests(manifest: Manifest): AssetRequest[] {
  const requests: AssetRequest[] = [];

  for (const slide of manifest.slides) {
    for (const block of slide.blocks ?? []) {
      if (!block || typeof block !== "object") continue;

      const kind = String((block as any).kind ?? "");
      if (kind === "diagram") {
        const request = diagramRequest(slide, block as Record<string, unknown>);
        if (request) requests.push(request);
      } else if (kind === "equation") {
        requests.push({ slide: slide.id, kind: "latex", source: String((block as any).source ?? ""), options: {} });
      }
    }
  }

  return requests;
}

function diagramRequest(slide: Slide, block: Record<string, unknown>): AssetRequest | null {
  const engine = String(presence(block.lang) ?? presence(block.engine) ?? "d2");
  if (engine === "typst" || engine === "typ") {
    return { slide: slide.id, kind: "typst", source: String(block.source ?? ""), options: {} };
  }
  if (!["d2", "d2-sketch", "tala"].includes(engine)) return null;

  const options: Record<string, unknown> = { layout: "tala", theme: 301, sketch: engine === "d2-sketch" };
  if (block.options && typeof block.options === "object" && !Array.isArray(block.options)) {
    Object.assign(options, block.options);
  }

  return { slide: slide.id, kind: "d2", source: String(block.source ?? ""), options };
}

export type { AssetEntry, AssetKind, AssetRequest };