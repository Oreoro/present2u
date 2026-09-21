#!/usr/bin/env bash
# Provision the Cloudflare resources for Present2u Cloud and patch wrangler.jsonc.
#
#   ./setup.sh
#
# Requires an interactive login: `npx wrangler login` (or CLOUDFLARE_API_TOKEN).
# Idempotent-ish: existing resources are detected and left alone.
set -euo pipefail

cd "$(dirname "$0")"

if ! npx wrangler whoami >/dev/null 2>&1; then
  echo "✘ Not authenticated. Run: npx wrangler login" >&2
  exit 1
fi

echo "→ D1 database (present2u)"
D1_OUT="$(npx wrangler d1 create present2u 2>&1 || true)"
D1_ID="$(printf '%s\n' "$D1_OUT" | sed -n 's/.*database_id *= *"\([^"]*\)".*/\1/p' | head -1)"
if [[ -z "${D1_ID}" ]]; then
  D1_ID="$(npx wrangler d1 list --json 2>/dev/null | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{try{const j=JSON.parse(s);const m=(j.result||j).find(x=>x.name==="present2u");if(m)console.log(m.uuid||m.id)}catch{}})' || true)"
fi

echo "→ KV namespace (present2u-cache)"
KV_OUT="$(npx wrangler kv namespace create present2u-cache 2>&1 || true)"
KV_ID="$(printf '%s\n' "$KV_OUT" | sed -n 's/.*id *= *"\([^"]*\)".*/\1/p' | head -1)"
if [[ -z "${KV_ID}" ]]; then
  KV_ID="$(npx wrangler kv namespace list --json 2>/dev/null | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{try{const j=JSON.parse(s);const m=(j.result||j).find(x=>x.title==="present2u-cache");if(m)console.log(m.id)}catch{}})' || true)"
fi

echo "→ R2 bucket (present2u-blobs)"
npx wrangler r2 bucket create present2u-blobs >/dev/null 2>&1 || true

if [[ -z "${D1_ID}" || -z "${KV_ID}" ]]; then
  echo "✘ Could not resolve D1/KV ids automatically." >&2
  echo "  D1 output: ${D1_OUT}" >&2
  echo "  KV output: ${KV_OUT}" >&2
  exit 1
fi

echo "→ patching wrangler.jsonc (d1=${D1_ID}, kv=${KV_ID})"
D1_ID="${D1_ID}" KV_ID="${KV_ID}" node -e '
  const fs = require("node:fs");
  const path = "wrangler.jsonc";
  let text = fs.readFileSync(path, "utf8");
  text = text.replace(/REPLACE_WITH_D1_ID/g, process.env.D1_ID);
  text = text.replace(/REPLACE_WITH_KV_ID/g, process.env.KV_ID);
  fs.writeFileSync(path, text);
  console.log("  ✓ wrangler.jsonc updated");
'

echo "→ applying D1 migrations (remote)"
npx wrangler d1 migrations apply present2u --remote

echo "→ setting SESSION_SECRET"
if ! npx wrangler secret put SESSION_SECRET --name present2u < <(openssl rand -hex 32) 2>/dev/null; then
  echo "  ⚠ Could not set SESSION_SECRET automatically; run: npx wrangler secret put SESSION_SECRET"
fi

echo
echo "✓ provisioned. Next:"
echo "    npm run dev        # local edge (D1/KV/R2 local)"
echo "    npm run deploy     # build the render container + deploy"