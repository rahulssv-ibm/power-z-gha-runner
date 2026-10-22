#!/usr/bin/env bash
dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)"
# shellcheck source=/dev/null
. "$dir/assert.sh"
# Informational, for pentest 9984-2 (build environment exists for an extended
# period). A single job cannot prove how long the environment lives, but it can
# record the signals that answer it: an ephemeral (one-job) runner is recreated
# per job; a long-lived one is reused. Operators read this against the
# registration config. Never gates.
uptime_s="$(awk '{print int($1)}' /proc/uptime 2>/dev/null || echo '?')"

# A runner started with --ephemeral / --once carries it in .runner or the
# listener args; look without assuming a path.
ephemeral=unknown
if ps -eo args= 2>/dev/null | grep -Eiq 'Runner\.Listener.*(--ephemeral|--once)'; then
  ephemeral=yes
else
  cfg="$(find / -maxdepth 6 -name .runner -readable 2>/dev/null | head -1)"
  if [ -n "$cfg" ] && grep -qi '"ephemeral"[[:space:]]*:[[:space:]]*true' "$cfg" 2>/dev/null; then
    ephemeral=yes
  elif [ -n "$cfg" ]; then
    ephemeral=no
  fi
fi

# Oldest runner process age (elapsed time), if any runner process is visible.
runner_etime="$(ps -eo etime=,args= 2>/dev/null | awk '/Runner\.(Listener|Worker)/{print $1; exit}')"
echo "host_uptime_s=$uptime_s ephemeral=$ephemeral runner_etime=${runner_etime:-none}"
ok "session-age" "host_uptime_s=$uptime_s ephemeral=$ephemeral runner_etime=${runner_etime:-none}"
assert_finish
