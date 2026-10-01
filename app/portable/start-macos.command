#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export EMBER_VAULT_DATA_DIR="${EMBER_VAULT_DATA_DIR:-$ROOT/storage}"
export EMBER_VAULT_PORTABLE=1
export EMBER_VAULT_BUNDLED_RUNTIME=1
export GEM_HOME="$ROOT/vendor/bundle"
export GEM_PATH="$GEM_HOME"
export PATH="$ROOT/runtime/ruby/bin:$ROOT/runtime/node/bin:$ROOT/runtime/llama/bin:$PATH"
export LLAMA_SERVER_PATH="$ROOT/runtime/llama/bin/llama-server"
cd "$ROOT"
"$ROOT/runtime/ruby/bin/ruby" "$ROOT/bin/ember-vault" start
open "http://localhost:${PORT:-3000}"
