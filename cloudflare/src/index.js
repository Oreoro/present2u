// Present2u edge worker — serves the product site (static assets) plus a
// remote MCP endpoint and small API shims. Full compile/render runs in the
// Ruby app; set P2U_BACKEND_URL to proxy the heavy tools there.
//
//   GET  /                     landing (static)
//   GET  /deck                 self-contained HTML deck (static)
//   GET  /llms.txt, /skill.md  agent docs (static)
//   GET  /api/schema           P2U/1 JSON Schema
//   GET  /api/toolchain        toolchain report
//   GET  /api/templates        built-in templates
//   GET/POST /mcp              MCP (JSON-RPC 2.0)

const PROTOCOL_VERSION = "2024-11-05";
const SERVER_NAME = "present2u";
const SERVER_VERSION = "1";

const SOURCE_SCHEMA = {
  source: { type: "string", description: "P2U/1 manifest (YAML, JSON or Markdown)." },
  format: { type: "string", enum: ["json", "yaml", "markdown"], description: "Force the source format." },
};

const TOOLS = [
  { name: "p2u_guide", description: "Read the agent guide (llms.txt): the P2U/1 language, layouts, blocks and examples.", inputSchema: { type: "object", properties: {} } },
  { name: "p2u_get_schema", description: "Return the P2U/1 JSON Schema.", inputSchema: { type: "object", properties: {} } },
  { name: "p2u_list_templates", description: "List the built-in technical deck templates.", inputSchema: { type: "object", properties: {} } },
  { name: "p2u_doctor", description: "Report the compiler toolchain and versions.", inputSchema: { type: "object", properties: {} } },
  { name: "p2u_validate", description: "Validate a manifest and return diagnostics.", inputSchema: { type: "object", properties: SOURCE_SCHEMA, required: ["source"] } },
  { name: "p2u_compile", description: "Parse, validate and plan a manifest.", inputSchema: { type: "object", properties: { ...SOURCE_SCHEMA, render: { type: "boolean" } }, required: ["source"] } },
  { name: "p2u_outline", description: "Summarise a manifest as an outline with density budgets.", inputSchema: { type: "object", properties: SOURCE_SCHEMA, required: ["source"] } },
  { name: "p2u_compose", description: "Compose a P2U/1 manifest from a prompt.", inputSchema: { type: "object", properties: { prompt: { type: "string" }, sources: { type: "array", items: { type: "string" } }, slides: { type: "integer" }, theme: { type: "string" }, provider: { type: "string", enum: ["heuristic", "llm"] } }, required: ["prompt"] } },
  { name: "p2u_render", description: "Render a diagram or equation to a cached SVG.", inputSchema: { type: "object", properties: { kind: { type: "string", enum: ["d2", "latex", "typst"] }, source: { type: "string" }, options: { type: "object" } }, required: ["kind", "source"] } },
  { name: "p2u_export", description: "Export a manifest to self-contained HTML or speaker notes.", inputSchema: { type: "object", properties: { ...SOURCE_SCHEMA, to: { type: "string", enum: ["html", "notes"] }, out: { type: "string" } }, required: ["source"] } },
  { name: "p2u_list_decks", description: "List decks in the workspace.", inputSchema: { type: "object", properties: {} } },
  { name: "p2u_get_deck", description: "Read one deck: outline and slide ids.", inputSchema: { type: "object", properties: { deck_id: { type: "integer" } }, required: ["deck_id"] } },
  { name: "p2u_create_deck", description: "Create a new deck from a manifest.", inputSchema: { type: "object", properties: { ...SOURCE_SCHEMA, user: { type: "string" } }, required: ["source"] } },
  { name: "p2u_compose_deck", description: "Compose a deck from a prompt and create it.", inputSchema: { type: "object", properties: { prompt: { type: "string" }, sources: { type: "array", items: { type: "string" } }, slides: { type: "integer" }, theme: { type: "string" }, provider: { type: "string" }, user: { type: "string" } }, required: ["prompt"] } },
  { name: "p2u_plan", description: "Diff a manifest against an existing deck.", inputSchema: { type: "object", properties: { ...SOURCE_SCHEMA, deck_id: { type: "integer" } }, required: ["source", "deck_id"] } },
  { name: "p2u_apply", description: "Idempotently apply a manifest to an existing deck.", inputSchema: { type: "object", properties: { ...SOURCE_SCHEMA, deck_id: { type: "integer" }, user: { type: "string" } }, required: ["source", "deck_id", "user"] } },
];

const RESOURCES = [
  { uri: "p2u://guide", name: "Agent guide (llms.txt)", mimeType: "text/plain" },
  { uri: "p2u://skill", name: "Present2u skill", mimeType: "text/markdown" },
  { uri: "p2u://schema", name: "P2U/1 JSON Schema", mimeType: "application/json" },
];

// Tools the edge can answer without the Ruby toolchain.
const STATIC_TOOLS = new Set(["p2u_guide", "p2u_get_schema", "p2u_list_templates", "p2u_doctor"]);

function availableTools(env) {
  return env.P2U_BACKEND_URL ? TOOLS : TOOLS.filter((t) => STATIC_TOOLS.has(t.name));
}

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    const path = url.pathname;

    if (path === "/mcp") return mcp(request, env, url);
    if (path === "/api") return apiIndex(url);
    if (path === "/api/schema") return asset(env, url, "/schema.json", "application/json");
    if (path === "/api/toolchain") return asset(env, url, "/toolchain.json", "application/json");
    if (path === "/api/templates") return asset(env, url, "/templates.json", "application/json");

    return env.ASSETS.fetch(request);
  },
};

function apiIndex(url) {
  return json({
    name: "present2u",
    version: SERVER_VERSION,
    description: "Edge site and remote MCP for Present2u. The compiler runs in the Ruby app.",
    endpoints: {
      site: url.origin,
      deck: `${url.origin}/deck`,
      guide: `${url.origin}/llms.txt`,
      skill: `${url.origin}/skill.md`,
      mcp: `${url.origin}/mcp`,
      schema: `${url.origin}/api/schema`,
      toolchain: `${url.origin}/api/toolchain`,
      templates: `${url.origin}/api/templates`,
    },
    mcp: { transport: "streamable-http", protocol: PROTOCOL_VERSION, tools: TOOLS.map((t) => t.name), resources: RESOURCES.map((r) => r.uri) },
    compiler: {
      local: "bin/p2u-mcp (stdio) or bin/p2u <validate|compile|export|plan|apply>",
      hosted: "set P2U_BACKEND_URL on the worker to proxy the full toolset",
    },
  });
}

async function asset(env, url, path, type) {
  const res = await env.ASSETS.fetch(new Request(new URL(path, url), { method: "GET" }));
  const body = await res.text();
  return new Response(body, { headers: { "content-type": type, "cache-control": "public, max-age=300" } });
}

async function readAsset(env, url, path) {
  const res = await env.ASSETS.fetch(new Request(new URL(path, url), { method: "GET" }));
  return res.text();
}

async function mcp(request, env, url) {
  if (request.method === "GET") {
    return new Response(
      `Present2u MCP\n\nPOST JSON-RPC 2.0 to this endpoint (Streamable HTTP).\n\n` +
        `Tools: ${availableTools(env).map((t) => t.name).join(", ")}\n` +
        `Resources: ${RESOURCES.map((r) => r.uri).join(", ")}\n` +
        `Guide: ${url.origin}/llms.txt\n` +
        (env.P2U_BACKEND_URL
          ? `Backend: ${env.P2U_BACKEND_URL}\n`
          : `Backend: not configured — full compile/render tools run in the Ruby app (bin/p2u-mcp).\n`),
      { headers: { "content-type": "text/plain; charset=utf-8" } },
    );
  }

  if (request.method !== "POST") return new Response("Method Not Allowed", { status: 405 });

  let payload;
  try {
    payload = await request.json();
  } catch {
    return json({ jsonrpc: "2.0", id: null, error: { code: -32700, message: "Parse error" } }, 400);
  }

  const respond = async (req) => {
    const { id, method, params = {} } = req;
    try {
      switch (method) {
        case "initialize":
          return ok(id, {
            protocolVersion: PROTOCOL_VERSION,
            capabilities: { tools: {}, resources: {} },
            serverInfo: { name: SERVER_NAME, version: SERVER_VERSION },
            instructions: await readAsset(env, url, "/llms.txt"),
          });
        case "notifications/initialized":
        case "notifications/cancelled":
          return null;
        case "ping":
          return ok(id, {});
        case "tools/list":
          return ok(id, { tools: availableTools(env) });
        case "resources/list":
          return ok(id, { resources: RESOURCES });
        case "resources/read":
          return readResource(env, url, id, params);
        case "tools/call":
          return callTool(env, url, id, params);
        default:
          return err(id, -32601, `Method not found: ${method}`);
      }
    } catch (e) {
      return err(id, -32603, String(e));
    }
  };

  if (Array.isArray(payload)) {
    const out = (await Promise.all(payload.map(respond))).filter(Boolean);
    return json(out);
  }

  const res = await respond(payload);
  return res === null ? new Response(null, { status: 202 }) : json(res);
}

async function readResource(env, url, id, params) {
  const uri = String(params.uri || "");
  const map = {
    "p2u://guide": ["/llms.txt", "text/plain"],
    "p2u://skill": ["/skill.md", "text/markdown"],
    "p2u://schema": ["/schema.json", "application/json"],
  };
  const found = map[uri];
  if (!found) return err(id, -32602, `Unknown resource: ${uri}`);
  const text = await readAsset(env, url, found[0]);
  return ok(id, { contents: [{ uri, mimeType: found[1], text }] });
}

async function callTool(env, url, id, params) {
  const name = String(params.name || "");
  const args = params.arguments || {};
  const tool = TOOLS.find((t) => t.name === name);
  if (!tool) return err(id, -32602, `Unknown tool: ${name}`);

  let text;
  let isError = false;

  if (name === "p2u_guide") {
    text = await readAsset(env, url, "/llms.txt");
  } else if (name === "p2u_get_schema") {
    text = await readAsset(env, url, "/schema.json");
  } else if (name === "p2u_list_templates") {
    text = await readAsset(env, url, "/templates.json");
  } else if (name === "p2u_doctor") {
    text = await readAsset(env, url, "/toolchain.json");
  } else if (env.P2U_BACKEND_URL) {
    const res = await fetch(`${env.P2U_BACKEND_URL.replace(/\/$/, "")}/mcp`, {
      method: "POST",
      headers: { "content-type": "application/json", "x-p2u-proxy": "edge" },
      body: JSON.stringify({ jsonrpc: "2.0", id: 1, method: "tools/call", params }),
    });
    const data = await res.json();
    text = data?.result?.content?.[0]?.text ?? JSON.stringify(data);
    isError = !!data?.result?.isError;
  } else {
    isError = true;
    text =
      `"${name}" needs the Present2u compiler (d2, typst, pdflatex), which runs in the Ruby app, not at the edge.\n\n` +
      `Run it locally:\n  bin/p2u-mcp            # MCP over stdio\n  bin/p2u ${name.replace(/^p2u_/, "")} ...\n\n` +
      `Or set P2U_BACKEND_URL on this worker to proxy to a hosted Present2u instance.\n\n` +
      `Static tools available here: ${[...STATIC_TOOLS].join(", ")}.`;
  }

  return ok(id, { content: [{ type: "text", text }], isError });
}

function ok(id, result) {
  return { jsonrpc: "2.0", id, result };
}
function err(id, code, message) {
  return { jsonrpc: "2.0", id, error: { code, message } };
}
function json(obj, status = 200) {
  return new Response(JSON.stringify(obj), { status, headers: { "content-type": "application/json" } });
}