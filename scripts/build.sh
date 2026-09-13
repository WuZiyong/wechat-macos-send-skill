#!/bin/zsh
set -euo pipefail

ROOT=${0:A:h}
SRC="$ROOT/wechatctl.swift"
BIN="$ROOT/wechatctl"

[[ -f "$SRC" ]] || { echo "ERROR source missing: $SRC" >&2; exit 2; }
command -v /usr/bin/swiftc >/dev/null || { echo "ERROR swiftc unavailable" >&2; exit 3; }

if [[ -x "$BIN" && ! "$SRC" -nt "$BIN" ]]; then
  echo "BUILD_UP_TO_DATE $BIN"
  exit 0
fi

TMP="$BIN.tmp.$$"
trap 'rm -f "$TMP"' EXIT
/usr/bin/swiftc -O "$SRC" -o "$TMP"
/bin/chmod 755 "$TMP"
/bin/mv -f "$TMP" "$BIN"
trap - EXIT
echo "BUILD_OK $BIN"
