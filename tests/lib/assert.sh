#!/usr/bin/env bash
# assert.sh — result helpers sourced by every test script.
#
# Scripts set env: RESULT_DIR, DOMAIN, PROFILE, ARCH, OS (optional DETAIL_FILE).
# Each helper appends one tab-separated line:
#   RESULT<TAB>id<TAB>domain<TAB>profile<TAB>arch<TAB>os<TAB>STATUS<TAB>reason
# Scripts speak FACTUALLY (ok = operation succeeded / boundary held).
# The runner.sh engine reconciles that against the manifest's expectation.

# Run standalone, a script has no DOMAIN; take it from the script's folder
# (tests/security/x.sh -> security) so its details land in detail-security.tsv.
if [ -z "${DOMAIN:-}" ] && [ -n "${BASH_SOURCE[1]:-}" ]; then
  DOMAIN="$(basename "$(dirname "${BASH_SOURCE[1]}")")"
fi

_detail_file() { echo "${DETAIL_FILE:-${RESULT_DIR:-/tmp/results}/detail-${DOMAIN:-unknown}.tsv}"; }

_emit() { # status id reason
  local f; f="$(_detail_file)"
  mkdir -p "$(dirname "$f")"
  # One record per line: reasons can carry multi-line commands, so flatten
  # newlines/tabs, squeeze spaces, and cap the length.
  local r="${3:-}"
  r="${r//$'\n'/ }"; r="${r//$'\t'/ }"
  r="$(printf '%s' "$r" | tr -s ' ')"; r="${r:0:200}"
  printf 'RESULT\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$2" "${DOMAIN:-unknown}" "${PROFILE:-unknown}" "${ARCH:-unknown}" "${OS:-unknown}" "$1" "$r" \
    >> "$f"
}

_HARD_FAIL=0
ok()    { _emit PASS  "$1" "${2:-}"; }
fail()  { _emit FAIL  "$1" "${2:-}"; _HARD_FAIL=1; }
xfail() { _emit XFAIL "$1" "${2:-}"; }
skip()  { _emit SKIP  "$1" "${2:-}"; }
# Whole test does not apply on this runner (wrong arch, tool absent): exit 77,
# the automake SKIP code, which runner.sh reports as SKIP whatever is expected.
skip_test() { skip "$1" "${2:-}"; exit 77; }

# cmd must succeed (exit 0) -> ok, else fail.
expect_ok()      { local id="$1"; shift; if "$@" >/dev/null 2>&1; then ok "$id" "ran: $*"; else fail "$id" "failed (wanted success): $*"; fi; }
# cmd must be denied (exit non-zero) -> ok, else fail (boundary breached).
expect_blocked() { local id="$1"; shift; if "$@" >/dev/null 2>&1; then fail "$id" "permitted (wanted blocked): $*"; else ok "$id" "blocked as expected: $*"; fi; }

# Every script ends with this: non-zero exit iff any fail was emitted.
assert_finish() { return "$_HARD_FAIL"; }

if [ "${1:-}" = "--selftest" ]; then
  set -u
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' EXIT
  export RESULT_DIR="$tmp" DOMAIN="self" PROFILE="p" ARCH="a" OS="o"
  export DETAIL_FILE="$tmp/d.tsv"
  ok   "t-ok"   "r1"
  fail "t-fail" "r2"
  xfail "t-xf"  "r3"
  skip "t-skip" "r4"
  expect_ok      "t-eok"  true
  expect_blocked "t-eblk" false
  expect_ok      "t-eok2" false   # should record FAIL
  expect_blocked "t-eblk2" true   # permitted -> boundary breached -> FAIL
  grep -q $'RESULT\tt-ok\tself\tp\ta\to\tPASS\tr1'  "$DETAIL_FILE" || { echo "ok line wrong"; exit 1; }
  grep -q $'\tt-fail\t.*\tFAIL\tr2'  "$DETAIL_FILE" || { echo "fail line wrong"; exit 1; }
  grep -q $'\tt-xf\t.*\tXFAIL\tr3'   "$DETAIL_FILE" || { echo "xfail wrong"; exit 1; }
  grep -q $'\tt-skip\t.*\tSKIP\tr4'  "$DETAIL_FILE" || { echo "skip wrong"; exit 1; }
  grep -q $'\tt-eblk\t.*\tPASS\t'    "$DETAIL_FILE" || { echo "expect_blocked wrong"; exit 1; }
  grep -q $'\tt-eok2\t.*\tFAIL\t'    "$DETAIL_FILE" || { echo "expect_ok fail path wrong"; exit 1; }
  grep -q $'\tt-eblk2\t.*\tFAIL\t'   "$DETAIL_FILE" || { echo "expect_blocked breach path wrong"; exit 1; }
  assert_finish && { echo "assert_finish should be non-zero after a fail"; exit 1; }
  ok "t-multi" $'line one\n\tline two'   # multi-line reason must stay one record
  [ "$(grep -c '^RESULT' "$DETAIL_FILE")" -eq "$(wc -l < "$DETAIL_FILE" | tr -d ' ')" ] \
    || { echo "a reason broke a record across lines"; exit 1; }
  grep -q $'\tt-multi\t.*\tPASS\tline one line two$' "$DETAIL_FILE" || { echo "reason not flattened"; exit 1; }
  echo "assert.sh selftest: OK"
fi
