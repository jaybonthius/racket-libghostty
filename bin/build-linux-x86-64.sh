#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GHOSTTY_COMMIT="51ed437cd1a202e625feb7fd0577354d81bcc54b"
SOURCE="$ROOT/.build/ghostty-source"
PREFIX="$ROOT/.build/ghostty-prefix"
PACKAGE="$ROOT/libghostty-x86_64-linux"

if [[ "$(uname -s)" != Linux || "$(uname -m)" != x86_64 ]]; then
  echo "error: this build script supports Linux x86-64 only" >&2
  exit 1
fi

for command in git strip zig; do
  if ! command -v "$command" >/dev/null 2>&1; then
    echo "error: missing required command: $command" >&2
    exit 1
  fi
done

if [[ "$(zig version)" != 0.16.0 ]]; then
  echo "error: Ghostty $GHOSTTY_COMMIT requires Zig 0.16.0" >&2
  exit 1
fi

mkdir -p "$(dirname "$SOURCE")" "$PREFIX" "$PACKAGE"
if [[ ! -d "$SOURCE/.git" ]]; then
  git init "$SOURCE"
  git -C "$SOURCE" remote add origin https://github.com/ghostty-org/ghostty.git
fi

git -C "$SOURCE" fetch --depth=1 origin "$GHOSTTY_COMMIT"
git -C "$SOURCE" checkout --detach FETCH_HEAD
rm -rf "$PREFIX"
(
  cd "$SOURCE"
  zig build -Demit-lib-vt=true -Doptimize=ReleaseFast -Dcpu=baseline --prefix "$PREFIX"
)

library="$PREFIX/lib/libghostty-vt.so"
header="$PREFIX/include/ghostty/vt.h"
if [[ ! -f "$library" || ! -f "$header" ]]; then
  echo "error: Ghostty build did not produce the expected shared library and header" >&2
  exit 1
fi

cp -L "$library" "$PACKAGE/libghostty-vt.so"
strip "$PACKAGE/libghostty-vt.so"
printf '%s\n' "$GHOSTTY_COMMIT" > "$PREFIX/GHOSTTY_COMMIT"
printf 'built %s from Ghostty %s with Zig %s\n' \
  "$PACKAGE/libghostty-vt.so" "$GHOSTTY_COMMIT" "$(zig version)"
