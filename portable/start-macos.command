#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export EMBER_VAULT_DATA_DIR="${EMBER_VAULT_DATA_DIR:-$ROOT/storage}"
export EMBER_VAULT_PORTABLE=1
cd "$ROOT"
"$ROOT/bin/ember-vault" start
open "http://localhost:${PORT:-3000}"
