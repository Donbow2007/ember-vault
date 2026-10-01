#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export EMBER_VAULT_DATA_DIR="${EMBER_VAULT_DATA_DIR:-$ROOT/storage}"
export EMBER_VAULT_PORTABLE=1
export EMBER_VAULT_BUNDLED_RUNTIME=1
export BUNDLE_PATH="$ROOT/vendor/bundle"
export GEM_HOME="$ROOT/vendor/bundle"
export GEM_PATH="$GEM_HOME"
export RUBYLIB="$ROOT/runtime/ruby/lib/ruby:$ROOT/runtime/ruby/lib/x86_64-linux-gnu/ruby"
export PATH="$ROOT/runtime/ruby/bin:$ROOT/runtime/node/bin:$ROOT/runtime/llama:$PATH"
export LD_LIBRARY_PATH="$ROOT/runtime/ruby/lib/x86_64-linux-gnu:$ROOT/runtime/node/lib:${LD_LIBRARY_PATH:-}"
export LLAMA_SERVER_PATH="${LLAMA_SERVER_PATH:-$ROOT/runtime/llama/llama-server}"
cd "$ROOT"
"$ROOT/runtime/ruby/bin/ruby" "$ROOT/bin/ember-vault" start
xdg-open "http://localhost:${PORT:-3000}" >/dev/null 2>&1 || true
