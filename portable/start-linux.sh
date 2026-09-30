#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export EMBER_VAULT_DATA_DIR="${EMBER_VAULT_DATA_DIR:-$ROOT/storage}"
export EMBER_VAULT_PORTABLE=1
cd "$ROOT"
"$ROOT/bin/ember-vault" start
python3 -m webbrowser "http://localhost:${PORT:-3000}" >/dev/null 2>&1 || true
echo "Ember Vault is running at http://localhost:${PORT:-3000}"
