// Shared helpers that mirror the small bits of ActiveSupport the Ruby compiler
// relies on, so the TS port stays behaviourally identical.

/** Recursively stringify object keys (Ruby's deep_stringify_keys). */
export function deepStringify(value: unknown): any {
  if (Array.isArray(value)) return value.map(deepStringify);
  if (value && typeof value === "object") {
    const out: Record<string, any> = {};
    for (const [key, val] of Object.entries(value as Record<string, unknown>)) {
      out[String(key)] = deepStringify(val);
    }
    return out;
  }
  return value;
}

/** Ruby's blank? — null, empty or whitespace-only. */
export function isBlank(value: unknown): boolean {
  if (value === null || value === undefined) return true;
  if (typeof value === "string") return value.trim().length === 0;
  if (Array.isArray(value)) return value.length === 0;
  return false;
}

export function isPresent(value: unknown): boolean {
  return !isBlank(value);
}

/** Ruby's presence — the value if present, otherwise undefined. */
export function presence(value: unknown): string | undefined {
  if (isBlank(value)) return undefined;
  return String(value);
}

/**
 * Approximates ActiveSupport's String#parameterize for id derivation:
 * downcase, collapse non-alphanumerics to `-`, trim leading/trailing `-`.
 */
export function parameterize(value: unknown): string {
  return String(value ?? "")
    .normalize("NFKD")
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-+|-+$/g, "");
}

export function asBool(value: unknown): boolean {
  if (typeof value === "boolean") return value;
  if (typeof value === "string") return ["1", "true", "yes", "on"].includes(value.toLowerCase());
  return !!value;
}