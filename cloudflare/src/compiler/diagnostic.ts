// A single compiler finding, addressable by slide and manifest path so an agent
// can locate, explain and repair it. Port of p2u/diagnostic.rb.

export type Severity = "error" | "warning" | "info";

export const SEVERITIES: Severity[] = ["error", "warning", "info"];

export interface DiagnosticOptions {
  slide?: string | null;
  path?: string | null;
  hint?: string | null;
}

export class Diagnostic {
  readonly severity: Severity;
  readonly code: string;
  readonly message: string;
  readonly slide?: string;
  readonly path?: string;
  readonly hint?: string;

  constructor(severity: string, code: string, message: string, options: DiagnosticOptions = {}) {
    const sev = String(severity);
    if (!SEVERITIES.includes(sev as Severity)) throw new Error(`Unknown severity: ${sev}`);
    this.severity = sev as Severity;
    this.code = String(code);
    this.message = String(message);
    this.slide = options.slide ?? undefined;
    this.path = options.path ?? undefined;
    this.hint = options.hint ?? undefined;
  }

  get isError(): boolean {
    return this.severity === "error";
  }

  get isWarning(): boolean {
    return this.severity === "warning";
  }

  toJSON(): Record<string, unknown> {
    const out: Record<string, unknown> = {
      severity: this.severity,
      code: this.code,
      message: this.message,
    };
    if (this.slide) out.slide = this.slide;
    if (this.path) out.path = this.path;
    if (this.hint) out.hint = this.hint;
    return out;
  }

  toString(): string {
    const location = [this.slide, this.path].filter(Boolean).join(" ");
    const prefix = location ? `${location}: ` : "";
    const suffix = this.hint ? ` (${this.hint})` : "";
    return `${this.severity.toUpperCase()} [${this.code}] ${prefix}${this.message}${suffix}`;
  }
}

export class ParseError extends Error {
  override name = "P2uParseError";
}