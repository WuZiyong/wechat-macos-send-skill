#!/bin/zsh
set -euo pipefail
export PATH=/usr/bin:/bin:/usr/sbin:/sbin:/usr/local/bin:/opt/homebrew/bin

ROOT=${0:A:h:h}
SRC="$ROOT/scripts/wechatctl.swift"
BIN="$ROOT/scripts/wechatctl"
ATTACHMENTS="$ROOT/scripts/Attachments.swift"

build_if_needed() {
  if [[ ! -x "$BIN" || "$SRC" -nt "$BIN" || "$ATTACHMENTS" -nt "$BIN" ]]; then
    echo "Building wechatctl v2..." >&2
    "$ROOT/scripts/build.sh" >&2
  fi
}

build_if_needed
exec "$BIN" "$@"
