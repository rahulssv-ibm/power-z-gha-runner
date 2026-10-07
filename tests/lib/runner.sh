#!/usr/bin/env bash
# runner.sh <domain> — run a test domain for the current PROFILE.
#
# Reads tests/<domain>/manifest.tsv, runs each applicable script, and writes
# $RESULT_DIR/verdict-<domain>.tsv by reconciling each script's factual exit
# code against the per-profile expectation. Exits non-zero iff any FAIL.
set -uo pipefail

run_domain() {
  local domain="$1"
  local base; base="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
  local manifest="$base/$domain/manifest.tsv"
  : "${PROFILE:?PROFILE required}"; : "${RESULT_DIR:?RESULT_DIR required}"
  [ -f "$manifest" ] || { echo "runner.sh: no manifest at $manifest" >&2; return 2; }
  mkdir -p "$RESULT_DIR/logs"
  local verdict="$RESULT_DIR/verdict-$domain.tsv"; : > "$verdict"
  local gate=0 id script profiles exp_c exp_v issue expected v c t0
  # issue column is part of the manifest schema but unused by the engine.
  # shellcheck disable=SC2034
  while IFS=$'\t' read -r id script profiles exp_c exp_v issue; do
    case "$id" in ''|\#*) continue;; esac
    case ",$profiles," in *",$PROFILE,"*) ;; *) continue;; esac
    if [ "$PROFILE" = container ]; then expected="$exp_c"; else expected="$exp_v"; fi
    if [ "$expected" = "-" ]; then
      printf 'RESULT\t%s\t%s\t%s\t%s\t%s\tSKIP\tnot-applicable\n' \
        "$id" "$domain" "$PROFILE" "${ARCH:-?}" "${OS:-?}" >> "$verdict"; continue
    fi
    t0=$SECONDS
    DOMAIN="$domain" PROFILE="$PROFILE" ARCH="${ARCH:-?}" OS="${OS:-?}" \
      DETAIL_FILE="$RESULT_DIR/detail-$domain.tsv" \
      bash "$base/$domain/$script" > "$RESULT_DIR/logs/$id.log" 2>&1
    c=$?
    case "$expected" in
      INFO)  v=INFO ;;
      PASS)  if [ "$c" -eq 0 ]; then v=PASS; else v=FAIL; gate=1; fi ;;
      XFAIL) if [ "$c" -ne 0 ]; then v=XFAIL; else v=WARN; fi ;;
      *)     v=FAIL; gate=1 ;;
    esac
    printf 'RESULT\t%s\t%s\t%s\t%s\t%s\t%s\texit=%s dur=%ss\n' \
      "$id" "$domain" "$PROFILE" "${ARCH:-?}" "${OS:-?}" "$v" "$c" "$((SECONDS - t0))" >> "$verdict"
  done < "$manifest"
  return "$gate"
}

if [ "${1:-}" = "--selftest" ]; then
  set -u
  tmp="$(mktemp -d)"
  # container run: good=PASS, bad=FAIL, onlyvm=SKIP, capab=XFAIL(expected fail) -> gate FAIL (from bad)
  RESULT_DIR="$tmp/c" PROFILE="container" ARCH="x" OS="y" \
    bash "${BASH_SOURCE[0]}" _fixtures; rc=$?
  v="$tmp/c/verdict-_fixtures.tsv"
  grep -q $'\tgood\t.*\tPASS\t'   "$v" || { echo "good!=PASS"; exit 1; }
  grep -q $'\tbad\t.*\tFAIL\t'    "$v" || { echo "bad!=FAIL"; exit 1; }
  grep -q $'\tonlyvm\t.*\tSKIP\t' "$v" || { echo "onlyvm!=SKIP"; exit 1; }
  grep -q $'\tcapab\t.*\tXFAIL\t' "$v" || { echo "capab!=XFAIL"; exit 1; }
  [ "$rc" -ne 0 ] || { echo "gate should fail (bad present)"; exit 1; }
  # vm run: capab expected PASS but script fails -> FAIL
  RESULT_DIR="$tmp/v" PROFILE="vm" ARCH="x" OS="y" \
    bash "${BASH_SOURCE[0]}" _fixtures; rc2=$?
  grep -q $'\tcapab\t.*\tvm.*\tFAIL\t' "$tmp/v/verdict-_fixtures.tsv" || { echo "capab vm!=FAIL"; exit 1; }
  [ "$rc2" -ne 0 ] || { echo "vm gate should fail"; exit 1; }
  grep -q $'\tgood\t.* dur=[0-9]*s$' "$v" || { echo "duration missing"; exit 1; }
  # a domain with no manifest must fail loudly, never pass with zero tests
  RESULT_DIR="$tmp/m" PROFILE="container" bash "${BASH_SOURCE[0]}" no-such-domain 2>/dev/null; rc3=$?
  [ "$rc3" -eq 2 ] || { echo "missing manifest should exit 2, got $rc3"; exit 1; }
  echo "runner.sh selftest: OK"
  exit 0
fi

[ $# -ge 1 ] || { echo "usage: runner.sh <domain>"; exit 2; }
run_domain "$1"
