#!/usr/bin/env bash
# runner.sh <domain> — run a test domain for the current PROFILE.
#
# Reads tests/<domain>/manifest.tsv, runs each applicable script, and writes
# $RESULT_DIR/verdict-<domain>.tsv by reconciling each script's factual exit
# code against the per-profile expectation. Exits non-zero iff any FAIL.
# PROFILE=hosted (GitHub-hosted reference, a VM) runs the vm rows. Each verdict
# lists the check ids that failed (fails=a,b) for the aggregate's parity gate.
set -uo pipefail

run_domain() {
  local domain="$1"
  local base; base="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
  local manifest="$base/$domain/manifest.tsv"
  : "${PROFILE:?PROFILE required}"; : "${RESULT_DIR:?RESULT_DIR required}"
  [ -f "$manifest" ] || { echo "runner.sh: no manifest at $manifest" >&2; return 2; }
  mkdir -p "$RESULT_DIR/logs"
  local verdict="$RESULT_DIR/verdict-$domain.tsv"; : > "$verdict"
  local gate=0 id script profiles exp_c exp_v issue expected v c t0 n0 fails
  local detail="$RESULT_DIR/detail-$domain.tsv" prof="$PROFILE"
  [ "$prof" = hosted ] && prof=vm   # GitHub-hosted runners are VMs
  # issue column is part of the manifest schema but unused by the engine.
  # shellcheck disable=SC2034
  while IFS=$'\t' read -r id script profiles exp_c exp_v issue; do
    case "$id" in ''|\#*) continue;; esac
    case ",$profiles," in *",$prof,"*) ;; *) continue;; esac
    if [ "$prof" = container ]; then expected="$exp_c"; else expected="$exp_v"; fi
    if [ "$expected" = "-" ]; then
      printf 'RESULT\t%s\t%s\t%s\t%s\t%s\tSKIP\tnot-applicable\n' \
        "$id" "$domain" "$PROFILE" "${ARCH:-?}" "${OS:-?}" >> "$verdict"; continue
    fi
    t0=$SECONDS; n0=$(cat "$detail" 2>/dev/null | wc -l)
    DOMAIN="$domain" PROFILE="$PROFILE" ARCH="${ARCH:-?}" OS="${OS:-?}" \
      DETAIL_FILE="$detail" \
      bash "$base/$domain/$script" > "$RESULT_DIR/logs/$id.log" 2>&1
    c=$?
    fails=$(tail -n +"$((n0 + 1))" "$detail" 2>/dev/null | awk -F'\t' '$7 == "FAIL" { printf "%s%s", s, $2; s = "," }')
    if [ "$c" -eq 77 ]; then
      v=SKIP   # script declared itself not applicable here (skip_test)
    else
      case "$expected" in
        INFO)  v=INFO ;;
        PASS)  if [ "$c" -eq 0 ]; then v=PASS; else v=FAIL; gate=1; fi ;;
        XFAIL) if [ "$c" -ne 0 ]; then v=XFAIL; else v=WARN; fi ;;
        *)     v=FAIL; gate=1 ;;
      esac
    fi
    printf 'RESULT\t%s\t%s\t%s\t%s\t%s\t%s\texit=%s dur=%ss%s\n' \
      "$id" "$domain" "$PROFILE" "${ARCH:-?}" "${OS:-?}" "$v" "$c" "$((SECONDS - t0))" \
      "${fails:+ fails=$fails}" >> "$verdict"
  done < "$manifest"
  return "$gate"
}

if [ "${1:-}" = "--selftest" ]; then
  set -u
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' EXIT
  # container run: good=PASS, bad=FAIL, onlyvm=SKIP, capab=XFAIL(expected fail) -> gate FAIL (from bad)
  RESULT_DIR="$tmp/c" PROFILE="container" ARCH="x" OS="y" \
    bash "${BASH_SOURCE[0]}" _fixtures; rc=$?
  v="$tmp/c/verdict-_fixtures.tsv"
  grep -q $'\tgood\t.*\tPASS\t'   "$v" || { echo "good!=PASS"; exit 1; }
  grep -q $'\tbad\t.*\tFAIL\t'    "$v" || { echo "bad!=FAIL"; exit 1; }
  grep -q $'\tonlyvm\t.*\tSKIP\t' "$v" || { echo "onlyvm!=SKIP"; exit 1; }
  grep -q $'\tcapab\t.*\tXFAIL\t' "$v" || { echo "capab!=XFAIL"; exit 1; }
  grep -q $'\tnotapp\t.*\tSKIP\t' "$v" || { echo "skip_test on container!=SKIP (would read WARN)"; exit 1; }
  [ "$rc" -ne 0 ] || { echo "gate should fail (bad present)"; exit 1; }
  # vm run: capab expected PASS but script fails -> FAIL
  RESULT_DIR="$tmp/v" PROFILE="vm" ARCH="x" OS="y" \
    bash "${BASH_SOURCE[0]}" _fixtures; rc2=$?
  grep -q $'\tcapab\t.*\tvm.*\tFAIL\t' "$tmp/v/verdict-_fixtures.tsv" || { echo "capab vm!=FAIL"; exit 1; }
  grep -q $'\tnotapp\t.*\tSKIP\t' "$tmp/v/verdict-_fixtures.tsv" || { echo "skip_test on vm!=SKIP (would read PASS)"; exit 1; }
  [ "$rc2" -ne 0 ] || { echo "vm gate should fail"; exit 1; }
  grep -q $'\tgood\t.* dur=[0-9]*s$' "$v" || { echo "duration missing"; exit 1; }
  grep -q $'\tbad\t.* fails=f1$' "$v" || { echo "failing check ids missing"; exit 1; }
  # hosted reference runs the vm rows under its own profile name
  RESULT_DIR="$tmp/h" PROFILE="hosted" ARCH="x" OS="y" bash "${BASH_SOURCE[0]}" _fixtures
  grep -q $'\tonlyvm\t_fixtures\thosted\t.*\tPASS\t' "$tmp/h/verdict-_fixtures.tsv" || { echo "hosted!=vm rows"; exit 1; }
  # a domain with no manifest must fail loudly, never pass with zero tests
  RESULT_DIR="$tmp/m" PROFILE="container" bash "${BASH_SOURCE[0]}" no-such-domain 2>/dev/null; rc3=$?
  [ "$rc3" -eq 2 ] || { echo "missing manifest should exit 2, got $rc3"; exit 1; }
  # a script run standalone (no DOMAIN) names its detail file after its folder
  RESULT_DIR="$tmp/d" bash "$(dirname "${BASH_SOURCE[0]}")/../_fixtures/pass.sh"
  [ -f "$tmp/d/detail-_fixtures.tsv" ] || { echo "standalone run wrote $(ls "$tmp/d"), want detail-_fixtures.tsv"; exit 1; }
  echo "runner.sh selftest: OK"
  exit 0
fi

[ $# -ge 1 ] || { echo "usage: runner.sh <domain>"; exit 2; }
run_domain "$1"
