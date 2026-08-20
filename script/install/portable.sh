#!/usr/bin/env bash
set -euo pipefail

REPOSITORY_URL="${EMBER_VAULT_REPOSITORY:-https://github.com/Donbow2007/ember-vault.git}"
TARGET="${1:-}"

if [ -z "$TARGET" ]; then
  echo "Usage: script/install/portable.sh /path/on/removable-drive/ember-vault" >&2
  exit 64
fi
if ! command -v git >/dev/null 2>&1; then
  echo "ERROR: Git must be installed for the initial portable installation." >&2
  exit 1
fi
if [ -e "$TARGET" ] && [ -n "$(find "$TARGET" -mindepth 1 -maxdepth 1 -print -quit 2>/dev/null)" ]; then
  echo "ERROR: The destination already exists and is not empty: $TARGET" >&2
  exit 1
fi

mkdir -p "$(dirname -- "$TARGET")"
git clone --branch main --single-branch "$REPOSITORY_URL" "$TARGET"
exec "$TARGET/start-ember-vault" setup
