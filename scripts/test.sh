#!/bin/zsh
set -euo pipefail
ROOT=${0:A:h:h}
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

"$ROOT/scripts/build.sh"
/usr/bin/swiftc -parse-as-library "$ROOT/scripts/Attachments.swift" \
  "$ROOT/tests/AttachmentsTests.swift" -o "$TMP/attachment-tests"
"$TMP/attachment-tests"

# These CLI checks never activate WeChat or require Accessibility permission.
printf 'test attachment\n' > "$TMP/example.txt"
"$ROOT/scripts/run.sh" validate-file "$TMP/example.txt"
expect_error() {
  local expected="$1"
  shift
  local actual
  if actual=$("$ROOT/scripts/run.sh" "$@" 2>&1); then
    echo "ERROR expected $expected but command succeeded" >&2
    exit 1
  fi
  if [[ "$actual" != "ERROR $expected" ]]; then
    echo "ERROR expected $expected, got: $actual" >&2
    exit 1
  fi
}
expect_error attachment_not_decodable_image validate-image "$TMP/example.txt"
expect_error attachment_not_readable_regular_file send-file 'Example Contact' "$TMP/missing"
expect_error invalid_argument_count send-image 'Example Contact'
echo TESTS_OK
