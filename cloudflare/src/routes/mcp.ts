// Remote MCP server over Streamable HTTP (JSON-RPC 2.0). Ports the tools from
// writebook/app/models/p2u/mcp.rb onto the edge compiler.

import { Hono } from "hono";
import type { Env, User } from "../types";
import {
  Compiler,
  Exporter,
  Parser,
  compose,
  outline,
  toolchainReport,
  MCP_PROTOCOL_VERSION,
  SERVER_NAME,
  SERVER_VERSION,
} from "../compiler";
import { storeAsset } from "../render/assets";
import { authenticate } from "../auth/tokens";
import { getDeck, listDecks, listSlides } from "../store/db";

const SOURCE = {
  source: { type: "string", description: "P2U/1 manifest (YAML, JSON or Markdown)." },
  format: { type: "string", enum: ["json", "yaml", "markdown"] },
};

const TOOLS = [
  { name: "p2u_guide", description: "Read the agent guide.", inputSchema: { type: "object", properties: {} } },
  { name: "p2u_get_schema", description: "Return the P2U/1 JSON Schema.", inputSchema: { type: "object", properties: {} } },
  { name: "p2u_list_templates", description: "List built-in deck templates.", inputSchema: { type: "object", properties: {} } },
  { name: "p2u_doctor", description: "Report the compiler toolchain.", inputSchema: { type: "object", properties: {} } },
  { name: "p2u_validate", description: "Validate a manifest.", inputSchema: { type: "object", properties: SOURCE, required: ["source"] } },
  { name: "p2u_compile", description: "Parse, validate and plan a manifest.", inputSchema: { type: "object", properties: { ...SOURCE, render: { type: "boolean" } }, required: ["source"] } },
  { name: "p2u_outline", description: "Summarise a manifest as an outline with density budgets.", inputSchema: { type: "object", properties: SOURCE, required: ["source"] } },
  { name: "p2u_compose", description: "Compose a P2U/1 manifest from a prompt.", inputSchema: { type: "object", properties: { prompt: { type: "string" }, sources: { type: "array", items: { type: "string" } }, slides: { type: "integer" }, theme: { type: "string" }, provider: { type: "string", enum: ["heuristic", "llm"] } }, required: ["prompt"] } },
  { name: "p2u_render", description: "Render a diagram or equation to a cached SVG.", inputSchema: { type: "object", properties: { kind: { type: "string", enum: ["d2", "latex", "typst"] }, source: { type: "string" }, options: { type: "object" } }, required: ["kind", "source"] } },
  { name: "p2u_export", description: "Export a manifest to self-contained HTML or speaker notes.", inputSchema: { type: "object", properties: { ...SOURCE, to: { type: "string", enum: ["html", "notes"] } }, required: ["source"] } },
  { name: "p2u_list_decks", description: "List decks (requires auth).", inputSchema: { type: "object", properties: {} } },
  { name: "p2u_get_deck", description: "Read one deck: outline and slide ids (requires auth).", inputSchema: { type: "object", properties: { deck_id: { type: "integer" } }, required: ["deck_id"] } },
];

const RESOURCES = [
  { uri: "p2u://guide", name: "Agent guide (llms.txt)", mimeType: "text/plain" },
  { uri: "p2u://skill", name: "Present2u skill", mimeType: "text/markdown" },
  { uri: "p2u://schema", name: "P2U/1 JSON Schema", mimeType: "application/json" },
];

export const mcpRoutes = new Hono<{ Bindings: Env }>();

mcpRoutes.get("/", (c) => {
  const origin = new URL(c.req.url).origin;
  return c.text(
    `Present2u MCP\n\nPOST JSON-RPC 2.0 to this endpoint (Streamable HTTP).\n\n` +
      `Tools: ${TOOLS.map((tool) => tool.name).join(", ")}\n` +
      `Resources: ${RESOURCES.map((resource) => resource.uri).join(", ")}\n` +
      `Guide: ${origin}/llms.txt\n`,
  );
});

mcpRoutes.post("/", async (c) => {
  let payload: any;
  try {
    payload = await c.req.json();
  } catch {
    return c.json({ jsonrpc: "2.0", id: null, error: { code: -32700, message: "Parse error" } }, 400);
  }

  const user = await authenticate(c.env, c.req.raw);
  const respond = (request: any) => handle(c.env, c.req.raw, request, user);

  if (Array.isArray(payload)) {
    const responses = (await Promise.all(payload.map(respond))).filter(Boolean);
    return c.json(responses);
  }

  const response = await respond(payload);
  return response === null ? new Response(null, { status: 202 }) : c.json(response);
});

async function handle(env: Env, raw: Request, request: any, user: User | null): Promise<unknown | null> {
  const { id, method, params = {} } = request ?? {};
  try {
    switch (method) {
      case "initialize":
        return ok(id, {
          protocolVersion: MCP_PROTOCOL_VERSION,
          capabilities: { tools: {}, resources: {} },
          serverInfo: { name: SERVER_NAME, version: SERVER_VERSION },
          instructions: await assetText(env, raw, "/llms.txt"),
        });
      case "notifications/initialized":
      case "notifications/cancelled":
        return null;
      case "ping":
        return ok(id, {});
      case "tools/list":
        return ok(id, { tools: TOOLS });
      case "resources/list":
        return ok(id, { resources: RESOURCES });
      case "resources/read":
        return readResource(env, raw, id, params);
      case "tools/call":
        return callTool(env, raw, id, params, user);
      default:
        return err(id, -32601, `Method not found: ${method}`);
    }
  } catch (error) {
    return err(id, -32603, String(error));
  }
}

async function readResource(env: Env, raw: Request, id: unknown, params: any) {
  const uri = String(params.uri ?? "");
  const map: Record<string, [string, string]> = {
    "p2u://guide": ["/llms.txt", "text/plain"],
    "p2u://skill": ["/skill.md", "text/markdown"],
    "p2u://schema": ["/schema.json", "application/json"],
  };
  const found = map[uri];
  if (!found) return err(id, -32602, `Unknown resource: ${uri}`);
  return ok(id, { contents: [{ uri, mimeType: found[1], text: await assetText(env, raw, found[0]) }] });
}

async function callTool(env: Env, raw: Request, id: unknown, params: any, user: User | null) {
  const name = String(params.name ?? "");
  const args = params.arguments ?? {};
  const store = (request: any) => storeAsset(env, request);

  try {
    switch (name) {
      case "p2u_guide":
        return text(id, await assetText(env, raw, "/llms.txt"));
      case "p2u_get_schema":
        return text(id, await assetText(env, raw, "/schema.json"));
      case "p2u_list_templates":
        return text(id, await assetText(env, raw, "/templates.json"));
      case "p2u_doctor":
        return text(id, JSON.stringify(await toolchainReport(env), null, 2));
      case "p2u_validate": {
        const result = await Compiler.compile(args.source, { format: args.format });
        return text(id, JSON.stringify({ valid: result.valid, diagnostics: result.diagnostics.map((d) => d.toJSON()) }, null, 2));
      }
      case "p2u_compile": {
        const result = await Compiler.compile(args.source, { format: args.format, render: !!args.render, store });
        return text(id, JSON.stringify({
          valid: result.valid,
          manifest: result.manifest?.toJSON() ?? null,
          diagnostics: result.diagnostics.map((d) => d.toJSON()),
          plan: result.plan,
        }, null, 2));
      }
      case "p2u_outline":
        return text(id, JSON.stringify(outline(Parser.parse(args.source, args.format)), null, 2));
      case "p2u_compose": {
        const result = await compose(env, { prompt: args.prompt, sources: args.sources, slides: args.slides, theme: args.theme, provider: args.provider });
        return text(id, JSON.stringify({ provider: result.provider, manifest: result.manifest?.toJSON() ?? null, diagnostics: result.diagnostics.map((d) => d.toJSON()) }, null, 2));
      }
      case "p2u_render": {
        const url = await storeAsset(env, { slide: "mcp", kind: args.kind ?? "d2", source: args.source, options: args.options ?? {} });
        return text(id, JSON.stringify({ url }));
      }
      case "p2u_export": {
        const exporter = new Exporter(Parser.parse(args.source, args.format));
        const content = args.to === "notes" ? exporter.toNotes() : await exporter.toHtml(env, store);
        return text(id, content);
      }
      case "p2u_list_decks": {
        if (!user) return text(id, "Authentication required (Authorization: Bearer <api_token>).", true);
        return text(id, JSON.stringify(await listDecks(env, user.id), null, 2));
      }
      case "p2u_get_deck": {
        if (!user) return text(id, "Authentication required.", true);
        const deck = await getDeck(env, user.id, Number(args.deck_id));
        if (!deck) return text(id, "Deck not found.", true);
        return text(id, JSON.stringify({ id: deck.id, title: deck.title, slides: await listSlides(env, deck.id) }, null, 2));
      }
      default:
        return err(id, -32602, `Unknown tool: ${name}`);
    }
  } catch (error) {
    return text(id, String(error), true);
  }
}

async function assetText(env: Env, raw: Request, path: string): Promise<string> {
  const response = await env.ASSETS.fetch(new Request(new URL(path, raw.url), { method: "GET" }));
  return response.text();
}

function ok(id: unknown, result: unknown) {
  return { jsonrpc: "2.0", id, result };
}
function err(id: unknown, code: number, message: string) {
  return { jsonrpc: "2.0", id, error: { code, message } };
}
function text(id: unknown, content: string, isError = false) {
  return ok(id, { content: [{ type: "text", text: content }], isError });
}