#!/usr/bin/env bash
set -euo pipefail
trap 'echo "Ember Vault launch failed; check bundled executables, mount permissions and storage logs." >&2' ERR
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export EMBER_VAULT_DATA_DIR="${EMBER_VAULT_DATA_DIR:-$ROOT/storage}"
export EMBER_VAULT_PORTABLE=1
export EMBER_VAULT_BUNDLED_RUNTIME=1
export GEM_HOME="$ROOT/runtime/ruby/lib/ruby/gems/3.3.0"
export GEM_PATH="$GEM_HOME"
export BUNDLE_PATH="$GEM_HOME"
export BUNDLE_WITHOUT=development:test
export BUNDLE_IGNORE_CONFIG=1
export BUNDLE_GEMFILE="$ROOT/Gemfile"
unset RUBYLIB RUBYOPT
export PATH="$ROOT/runtime/ruby/bin:$ROOT/runtime/node/bin:$ROOT/runtime/llama:$PATH"
export LD_LIBRARY_PATH="$ROOT/runtime/llama/lib:$ROOT/runtime/ruby/lib:${LD_LIBRARY_PATH:-}"
export LLAMA_SERVER_PATH="$ROOT/runtime/llama/llama-server"
export BOOTSNAP_CACHE_DIR="$EMBER_VAULT_DATA_DIR/tmp/bootsnap"
export TMPDIR="$EMBER_VAULT_DATA_DIR/tmp"
mkdir -p "$TMPDIR"
cd "$ROOT"
"$ROOT/runtime/ruby/bin/ruby" "$ROOT/bin/ember-vault" "${1:-start}"
if [[ "${1:-start}" == start && "${EMBER_VAULT_NO_BROWSER:-0}" != 1 ]]; then
  xdg-open "$(cat "$EMBER_VAULT_DATA_DIR/ember-vault.url")" >/dev/null 2>&1 || true
fi
