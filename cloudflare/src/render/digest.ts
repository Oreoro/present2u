// Content address for a rendered asset. Kept byte-for-byte compatible with
// writebook/app/models/rendered_asset.rb so the same manifest yields the same
// digest on both runtimes.

export type AssetKind = "d2" | "latex" | "typst";

export interface AssetRequest {
  slide: string;
  kind: AssetKind;
  source: string;
  options: Record<string, unknown>;
}

export interface AssetEntry {
  slide: string;
  kind: AssetKind;
  digest: string;
  url: string;
  rendered: boolean;
}

export function cacheKey(kind: string, source: string, options: Record<string, unknown> = {}): string {
  const normalized = Object.entries(options)
    .map(([key, value]) => [String(key), String(value)] as [string, string])
    .sort((a, b) => (a[0] === b[0] ? (a[1] < b[1] ? -1 : a[1] > b[1] ? 1 : 0) : a[0] < b[0] ? -1 : 1));

  // Ruby: [kind.to_s, normalized.inspect, source.to_s].join("\u0000")
  // normalized.inspect for an array of [String, String] pairs.
  const inspected = `[${normalized.map(([k, v]) => `[${quote(k)}, ${quote(v)}]`).join(", ")}]`;
  return [String(kind), inspected, String(source)].join("\u0000");
}

export async function digestFor(request: Pick<AssetRequest, "kind" | "source" | "options">): Promise<string> {
  return sha256Hex(cacheKey(request.kind, request.source, request.options ?? {}));
}

export async function sha256Hex(input: string): Promise<string> {
  const bytes = new TextEncoder().encode(input);
  const digest = await crypto.subtle.digest("SHA-256", bytes);
  return [...new Uint8Array(digest)].map((byte) => byte.toString(16).padStart(2, "0")).join("");
}

/** Ruby-style double-quoted string (good enough for keys/values we emit). */
function quote(value: string): string {
  return `"${value.replace(/\\/g, "\\\\").replace(/"/g, '\\"')}"`;
}