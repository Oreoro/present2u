#!/usr/bin/env bash
# Deploy the Present2u edge site + remote MCP to Cloudflare Workers.
#
#   ./deploy.sh            # sync docs from the app, then deploy
#   ./deploy.sh --no-sync  # deploy only
#
# Requires: node/npx, and `wrangler login` (or CLOUDFLARE_API_TOKEN).
set -euo pipefail

cd "$(dirname "$0")"
ROOT="$(cd .. && pwd)"
APP="$ROOT/writebook"

if [[ "${1:-}" != "--no-sync" ]]; then
  echo "→ syncing agent docs from the app"
  cp "$APP/llms.txt" public/llms.txt
  cp "$APP/SKILL.md" public/skill.md
  cp "$APP/public/favicon.svg" public/favicon.svg 2>/dev/null || true

  if [[ -f "$APP/config/schemas/p2u-1.schema.json" ]]; then
    cp "$APP/config/schemas/p2u-1.schema.json" public/schema.json
  fi

  if command -v ruby >/dev/null 2>&1 && [[ -x "$APP/bin/p2u" ]]; then
    echo "→ refreshing toolchain + templates (via p2u doctor / templates)"
    ( cd "$APP" && bin/p2u doctor --json > "$OLDPWD/public/toolchain.json" 2>/dev/null ) || true
  fi
fi

echo "→ deploying to Cloudflare Workers"
npx --yes wrangler deploy

echo "✓ deployed — https://p2u.focuslab.pk"