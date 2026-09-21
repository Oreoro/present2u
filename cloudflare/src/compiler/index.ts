// The P2U/1 compiler, at the edge. Pure modules (parse, validate, outline,
// emit, plan) run in the Worker; asset rendering is delegated to the render
// container. This is the TS counterpart of writebook/app/models/p2u/.

export { Manifest } from "./manifest";
export type { Slide, Block } from "./manifest";
export { Parser } from "./parser";
export { Validator, DENSITY, THEMES, ASPECTS } from "./validator";
export { Compiler, assetRequests } from "./compiler";
export type { CompileResult, CompileOptions } from "./compiler";
export { Emitter, serializeBlock } from "./emitter";
export type { DeckAttributes, SlideAttributes } from "./emitter";
export { outline, ESTIMATED_SECONDS_PER_SLIDE } from "./outliner";
export type { Outline, SlideSummary } from "./outliner";
export { Planner } from "./planner";
export type { Action, ActionName, ExistingSlide, PlanResult } from "./planner";
export { Exporter, TITLED_LAYOUTS } from "./exporter";
export { compose, DEFAULT_SLIDES } from "./composer";
export type { ComposeOptions, ComposeResult } from "./composer";
export { toolchainReport } from "./toolchain";
export { Diagnostic, ParseError } from "./diagnostic";
export type { Severity } from "./diagnostic";
export { VERSION, SERVER_NAME, SERVER_VERSION, MCP_PROTOCOL_VERSION } from "./version";
export * as Layouts from "./layouts";
export * as Blocks from "./blocks";