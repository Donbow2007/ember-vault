#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
# Ruby's older support libraries can conflict with newer system GPU drivers.
CLEAN_PATH="$ROOT/lib"
OLD_IFS=$IFS
IFS=:
for directory in ${LD_LIBRARY_PATH:-}; do
  case "$directory" in
    "$ROOT/lib"|"${ROOT%/*}/ruby/lib"|"") ;;
    *) CLEAN_PATH="$CLEAN_PATH:$directory" ;;
  esac
done
IFS=$OLD_IFS
export LD_LIBRARY_PATH="$CLEAN_PATH"
if ! "$ROOT/llama-server.bin" --version >/dev/null 2>&1; then
  export LD_LIBRARY_PATH="$ROOT/compat:$LD_LIBRARY_PATH"
fi
exec "$ROOT/llama-server.bin" "$@"
