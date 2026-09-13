#!/bin/zsh
set -euo pipefail

ROOT=${0:A:h}
SRC="$ROOT/wechatctl.swift"
ATTACHMENTS="$ROOT/Attachments.swift"
BIN="$ROOT/wechatctl"

[[ -f "$SRC" ]] || { echo "ERROR source missing: $SRC" >&2; exit 2; }
[[ -f "$ATTACHMENTS" ]] || { echo "ERROR source missing: $ATTACHMENTS" >&2; exit 2; }
command -v /usr/bin/swiftc >/dev/null || { echo "ERROR swiftc unavailable" >&2; exit 3; }

if [[ -x "$BIN" && ! "$SRC" -nt "$BIN" && ! "$ATTACHMENTS" -nt "$BIN" ]]; then
  echo "BUILD_UP_TO_DATE $BIN"
  exit 0
fi

TMP="$BIN.tmp.$$"
trap 'rm -f "$TMP"' EXIT
/usr/bin/swiftc -O -parse-as-library "$SRC" "$ATTACHMENTS" -o "$TMP"
/bin/chmod 755 "$TMP"
/bin/mv -f "$TMP" "$BIN"
trap - EXIT
echo "BUILD_OK $BIN"
