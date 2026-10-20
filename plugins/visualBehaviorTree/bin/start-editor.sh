#!/usr/bin/env bash
set -euo pipefail
plugin_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
editor_dir="$plugin_dir/editor"
node_major="$(node -p 'Number(process.versions.node.split(".")[0])')"
if (( node_major < 20 )); then echo "Node.js 20+ é necessário." >&2; exit 2; fi
if [[ ! -d "$editor_dir/node_modules" ]]; then (cd "$editor_dir" && npm install); fi
if [[ ! -d "$editor_dir/dist" ]]; then (cd "$editor_dir" && npm run build); fi
export BT_SESSION_TOKEN="$(node -e 'process.stdout.write(require("crypto").randomBytes(32).toString("hex"))')"
exec node "$editor_dir/server/index.mjs"
