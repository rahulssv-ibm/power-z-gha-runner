#!/usr/bin/env bash
# runner.sh <domain> — run a test domain for the current PROFILE.
#
# Reads tests/<domain>/manifest.tsv, runs each applicable script, and writes
# $RESULT_DIR/verdict-<domain>.tsv by reconciling each script's factual exit
# code against the per-profile expectation. Exits non-zero iff any FAIL.
# PROFILE=hosted (GitHub-hosted reference, a VM) runs the vm rows. Each verdict
# lists the check ids that failed (fails=a,b) for the aggregate's parity gate.
#
# Each script's output streams to stdout (folded into a log group on GitHub
# Actions) and to $RESULT_DIR/logs/<id>.log. A FAIL or WARN then prints an
# unfolded block: the failed checks with their reasons, the end of the log, and
# the manifest's fix column. The same blocks go to $RESULT_DIR/problems-<domain>.md.
set -uo pipefail

LOG_TAIL=25   # log lines a FAIL block repeats outside the folded group

# problem <verdict> <domain> <id> <script> <expected> <exit> <dur> <checks-tsv> <log> <fix>
problem() {
  local v="$1" domain="$2" id="$3" script="$4" expected="$5" c="$6" dur="$7"
  local checks="$8" log="$9" fix="${10}" prof="$PROFILE" what
  [ "$prof" = hosted ] && prof=vm
  [ "$fix" = - ] && fix=""
  if [ "$v" = WARN ]; then
    what="Succeeded, but the manifest expects $expected on $PROFILE: this $PROFILE runner now allows something it did not. If that change was intended, set expected_$prof to PASS for '$id' in tests/$domain/manifest.tsv; if not, find the platform change that loosened isolation."
  else
    what="${fix:-No fix recorded: read the header of tests/$domain/$script.}"
  fi
  {
    echo
    echo "==== $v $domain/$id on ${RUNNER_LABEL:-$PROFILE ${ARCH:-?} ${OS:-?}} (exit=$c, ${dur}s)"
    if [ -n "$checks" ]; then
      echo "Failed checks:"
      printf '%s\n' "$checks" | awk -F'\t' '{ printf "  - %s: %s\n", $2, $8 }'
    elif [ "$v" = FAIL ]; then
      echo "Failed checks: none recorded; the script exited $c before reporting one (see the log below)."
    fi
    echo "How to fix: $what"
    if [ "$v" = FAIL ] && [ -s "$log" ]; then
      echo "Last $LOG_TAIL log lines (full log: the '$domain/$id' group above, or logs/$id.log in the result artifact):"
      tail -n "$LOG_TAIL" "$log" | sed 's/^/  | /'
    fi
  } | tee -a "$RESULT_DIR/problems-$domain.md"
}

run_domain() {
  local domain="$1"
  local base; base="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
  local manifest="$base/$domain/manifest.tsv"
  : "${PROFILE:?PROFILE required}"; : "${RESULT_DIR:?RESULT_DIR required}"
  [ -f "$manifest" ] || { echo "runner.sh: no manifest at $manifest" >&2; return 2; }
  mkdir -p "$RESULT_DIR/logs"
  local verdict="$RESULT_DIR/verdict-$domain.tsv"; : > "$verdict"
  : > "$RESULT_DIR/problems-$domain.md"
  local gate=0 id script profiles exp_c exp_v issue fix expected v c t0 n0 new fails
  local detail="$RESULT_DIR/detail-$domain.tsv" prof="$PROFILE" gha=""
  [ "$prof" = hosted ] && prof=vm   # GitHub-hosted runners are VMs
  [ "${GITHUB_ACTIONS:-}" = true ] && gha=1
  # issue column is part of the manifest schema but unused by the engine.
  # shellcheck disable=SC2034
  while IFS=$'\t' read -r id script profiles exp_c exp_v issue fix; do
    case "$id" in ''|\#*) continue;; esac
    case ",$profiles," in *",$prof,"*) ;; *) continue;; esac
    if [ "$prof" = container ]; then expected="$exp_c"; else expected="$exp_v"; fi
    if [ "$expected" = "-" ]; then
      printf 'RESULT\t%s\t%s\t%s\t%s\t%s\tSKIP\tnot-applicable\n' \
        "$id" "$domain" "$PROFILE" "${ARCH:-?}" "${OS:-?}" >> "$verdict"; continue
    fi
    t0=$SECONDS; n0=$(cat "$detail" 2>/dev/null | wc -l)
    if [ -n "$gha" ]; then echo "::group::$domain/$id ($script)"; else echo "== $domain/$id ($script)"; fi
    # stdin from /dev/null: the loop reads the manifest on stdin.
    DOMAIN="$domain" PROFILE="$PROFILE" ARCH="${ARCH:-?}" OS="${OS:-?}" \
      DETAIL_FILE="$detail" \
      bash "$base/$domain/$script" < /dev/null 2>&1 | tee "$RESULT_DIR/logs/$id.log"
    c=${PIPESTATUS[0]}
    [ -n "$gha" ] && echo "::endgroup::"
    new=$(tail -n +"$((n0 + 1))" "$detail" 2>/dev/null)
    fails=$(printf '%s\n' "$new" | awk -F'\t' '$7 == "FAIL" { printf "%s%s", s, $2; s = "," }')
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
    echo "$v $domain/$id (exit=$c, $((SECONDS - t0))s)"
    printf 'RESULT\t%s\t%s\t%s\t%s\t%s\t%s\texit=%s dur=%ss%s\n' \
      "$id" "$domain" "$PROFILE" "${ARCH:-?}" "${OS:-?}" "$v" "$c" "$((SECONDS - t0))" \
      "${fails:+ fails=$fails}" >> "$verdict"
    case "$v" in
      FAIL|WARN)
        problem "$v" "$domain" "$id" "$script" "$expected" "$c" "$((SECONDS - t0))" \
          "$(printf '%s\n' "$new" | awk -F'\t' '$7 == "FAIL"')" "$RESULT_DIR/logs/$id.log" "$fix" ;;
    esac
  done < "$manifest"
  return "$gate"
}

if [ "${1:-}" = "--selftest" ]; then
  set -u
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' EXIT
  # container run: good=PASS, bad=FAIL, onlyvm=SKIP, capab=XFAIL(expected fail) -> gate FAIL (from bad)
  RESULT_DIR="$tmp/c" PROFILE="container" ARCH="x" OS="y" \
    bash "${BASH_SOURCE[0]}" _fixtures > "$tmp/c.out"; rc=$?
  v="$tmp/c/verdict-_fixtures.tsv"
  # a FAIL prints its failed check, reason, log tail and the manifest's fix
  grep -q '^==== FAIL _fixtures/bad ' "$tmp/c.out" || { echo "no FAIL block for bad"; exit 1; }
  grep -q '^  - f1: always fail$' "$tmp/c.out" || { echo "FAIL block lacks the check's reason"; exit 1; }
  grep -q '^How to fix: fix the fixture$' "$tmp/c.out" || { echo "FAIL block lacks the manifest fix"; exit 1; }
  grep -q '^  | fixture says why it failed$' "$tmp/c.out" || { echo "FAIL block lacks the log tail"; exit 1; }
  grep -q '^==== FAIL _fixtures/bad ' "$tmp/c/problems-_fixtures.md" || { echo "problems file missing the FAIL"; exit 1; }
  ! grep -q '_fixtures/good' "$tmp/c/problems-_fixtures.md" || { echo "a PASS was reported as a problem"; exit 1; }
  grep -q 'fixture says why it failed' "$tmp/c/logs/bad.log" || { echo "log file not written"; exit 1; }
  # succeeding where XFAIL is expected is a WARN, explained, never a gate on its own
  grep -q $'\tloose\t.*\tWARN\t' "$v" || { echo "loose!=WARN"; exit 1; }
  grep -q "^How to fix: Succeeded, but the manifest expects XFAIL on container" "$tmp/c.out" || { echo "no WARN explanation"; exit 1; }
  grep -q $'\tgood\t.*\tPASS\t'   "$v" || { echo "good!=PASS"; exit 1; }
  grep -q $'\tbad\t.*\tFAIL\t'    "$v" || { echo "bad!=FAIL"; exit 1; }
  grep -q $'\tonlyvm\t.*\tSKIP\t' "$v" || { echo "onlyvm!=SKIP"; exit 1; }
  grep -q $'\tcapab\t.*\tXFAIL\t' "$v" || { echo "capab!=XFAIL"; exit 1; }
  grep -q $'\tnotapp\t.*\tSKIP\t' "$v" || { echo "skip_test on container!=SKIP (would read WARN)"; exit 1; }
  [ "$rc" -ne 0 ] || { echo "gate should fail (bad present)"; exit 1; }
  # vm run: capab expected PASS but script fails -> FAIL
  RESULT_DIR="$tmp/v" PROFILE="vm" ARCH="x" OS="y" \
    bash "${BASH_SOURCE[0]}" _fixtures > /dev/null; rc2=$?
  grep -q $'\tcapab\t.*\tvm.*\tFAIL\t' "$tmp/v/verdict-_fixtures.tsv" || { echo "capab vm!=FAIL"; exit 1; }
  grep -q $'\tnotapp\t.*\tSKIP\t' "$tmp/v/verdict-_fixtures.tsv" || { echo "skip_test on vm!=SKIP (would read PASS)"; exit 1; }
  [ "$rc2" -ne 0 ] || { echo "vm gate should fail"; exit 1; }
  grep -q $'\tgood\t.* dur=[0-9]*s$' "$v" || { echo "duration missing"; exit 1; }
  grep -q $'\tbad\t.* fails=f1$' "$v" || { echo "failing check ids missing"; exit 1; }
  # hosted reference runs the vm rows under its own profile name
  RESULT_DIR="$tmp/h" PROFILE="hosted" ARCH="x" OS="y" bash "${BASH_SOURCE[0]}" _fixtures > /dev/null
  grep -q $'\tonlyvm\t_fixtures\thosted\t.*\tPASS\t' "$tmp/h/verdict-_fixtures.tsv" || { echo "hosted!=vm rows"; exit 1; }
  # a domain with no manifest must fail loudly, never pass with zero tests
  RESULT_DIR="$tmp/m" PROFILE="container" bash "${BASH_SOURCE[0]}" no-such-domain 2>/dev/null; rc3=$?
  [ "$rc3" -eq 2 ] || { echo "missing manifest should exit 2, got $rc3"; exit 1; }
  # a script run standalone (no DOMAIN) names its detail file after its folder
  RESULT_DIR="$tmp/d" bash "$(dirname "${BASH_SOURCE[0]}")/../_fixtures/pass.sh" > /dev/null
  [ -f "$tmp/d/detail-_fixtures.tsv" ] || { echo "standalone run wrote $(ls "$tmp/d"), want detail-_fixtures.tsv"; exit 1; }
  echo "runner.sh selftest: OK"
  exit 0
fi

[ $# -ge 1 ] || { echo "usage: runner.sh <domain>"; exit 2; }
run_domain "$1"
