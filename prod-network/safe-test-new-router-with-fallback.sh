#!/run/current-system/sw/bin/bash
# safe-test-new-router-with-fallback.sh
#
# Generic safe trial for s-router-<router>-new with s-router-<router>-prod as
# the fallback. The new image is built/updated BEFORE prod is stopped, then a
# short health-checked trial runs and prod is always restored.
#
# Usage:
#   sudo ./prod-network/safe-test-new-router-with-fallback.sh cobalt --yes
#   sudo ./prod-network/safe-test-new-router-with-fallback.sh cobalt --yes --hold 600
#   sudo ./prod-network/safe-test-new-router-with-fallback.sh cobalt --yes --image /nix/store/...-nixos-vm
#   sudo ./prod-network/safe-test-new-router-with-fallback.sh cobalt --yes --no-update
#
# The script deliberately has no default "go" behaviour: --yes is required
# because the trial stops the production router for the hold window.

set -Eeuo pipefail

export PATH=/run/current-system/sw/bin:/run/current-system/sw/sbin:/usr/bin:/bin

usage() {
  cat <<'EOF'
Usage: safe-test-new-router-with-fallback.sh <router> --yes [options]

  <router>              Router name; derives s-router-<router>-prod and
                        s-router-<router>-new.

Options:
  --yes                 Required. Confirm the trial may stop prod temporarily.
  --hold SECONDS        Healthy hold window (default: 600).
  --source PATH         NixOS source worktree (default: /home/deadbeef/github/nixos).
  --image PATH          Register this prebuilt nixos-vm image instead of vm-update.
  --no-update           Skip vm-update/register; use the already-updated new instance.
  --diagnostics PATH    Optional script run as: bash PATH <new-name>
  --no-failsafe         Do not install the independent systemd-run failsafe timer.
  -h, --help            Show this help.

Safety:
  - Prod stays active while the new image is built/registered.
  - The new instance is stopped before the trial.
  - Prod is stopped only after the new image is ready.
  - EXIT/TERM/INT/HUP always restore prod.
  - An independent systemd-run timer restores prod if this script is killed.
EOF
}

die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
ts() { date -Is; }

ROUTER=""
HOLD=600
SOURCE="/home/deadbeef/github/nixos"
IMAGE=""
NO_UPDATE=0
NO_FAILSAFE=0
DIAG=""
ASSUME_YES=0

if [ "$(id -u)" -ne 0 ]; then
  exec sudo -n -- "$0" "$@"
fi

while [ "$#" -gt 0 ]; do
  case "$1" in
    --yes) ASSUME_YES=1; shift ;;
    --hold) [ "$#" -ge 2 ] || die "--hold needs a value"; HOLD="$2"; shift 2 ;;
    --source) [ "$#" -ge 2 ] || die "--source needs a value"; SOURCE="$2"; shift 2 ;;
    --image) [ "$#" -ge 2 ] || die "--image needs a value"; IMAGE="$2"; shift 2 ;;
    --no-update) NO_UPDATE=1; shift ;;
    --diagnostics) [ "$#" -ge 2 ] || die "--diagnostics needs a value"; DIAG="$2"; shift 2 ;;
    --no-failsafe) NO_FAILSAFE=1; shift ;;
    -h|--help) usage; exit 0 ;;
    --*) die "unknown option: $1" ;;
    *)
      [ -z "$ROUTER" ] || die "unexpected argument: $1"
      ROUTER="$1"
      shift
      ;;
  esac
done

[ -n "$ROUTER" ] || { usage; exit 1; }
[ "$ASSUME_YES" -eq 1 ] || die "refusing to stop prod without --yes"
[[ "$ROUTER" =~ ^[A-Za-z0-9._-]+$ ]] || die "invalid router name: $ROUTER"
[[ "$HOLD" =~ ^[0-9]+$ ]] || die "--hold must be an integer"
[ -d "$SOURCE" ] || die "source worktree not found: $SOURCE"
[ -n "$DIAG" ] && [ ! -r "$DIAG" ] && die "diagnostics script not readable: $DIAG"

PROD="s-router-${ROUTER}-prod"
NEW="s-router-${ROUTER}-new"
PROD_UNIT="${PROD}-vm.service"
NEW_UNIT="${NEW}-vm.service"
CONF_DIR="/etc/nixos-shell-vm-manager/instances"
NEW_CONF="${CONF_DIR}/${NEW}.conf"
PROD_CONF="${CONF_DIR}/${PROD}.conf"
RUN_DIR="/run/safe-test-${ROUTER}"
LOG="${RUN_DIR}/trial.log"
MARKER="${RUN_DIR}/done"
FAILSAFE="${RUN_DIR}/failsafe.sh"
FAILSAFE_LOG="${RUN_DIR}/failsafe.log"
LOCK="${RUN_DIR}/lock"
FAILSAFE_SECONDS=$((HOLD + 300))

mkdir -p "$RUN_DIR"
chmod 700 "$RUN_DIR"

exec 9>"$LOCK"
flock -n 9 || die "another safe test for ${ROUTER} is already running"

exec >>"$LOG" 2>&1

echo "[$(ts)] === safe trial ${NEW} with fallback ${PROD} ==="
echo "[$(ts)] source=${SOURCE} image=${IMAGE:-<vm-update>} hold=${HOLD}s update=$((1 - NO_UPDATE)) failsafe=$((1 - NO_FAILSAFE))"

is_active() { systemctl is-active --quiet "$1"; }

[ -r "$NEW_CONF" ] || die "missing manager config: $NEW_CONF"
[ -r "$PROD_CONF" ] || die "missing manager config: $PROD_CONF"

if ! is_active "$PROD_UNIT"; then
  die "prod is not active: $PROD_UNIT"
fi
if is_active "$NEW_UNIT"; then
  die "new is already active; stop it before starting a new safe test"
fi

# shellcheck disable=SC1090
. "$NEW_CONF"
HEALTH_RETRIES="${HEALTH_RETRIES:-60}"
# The managed conf carries the steady-state tolerance. A candidate still has its
# 15 containers converging while the hold runs, so the QEMU guest agent can miss
# a short deadline while the router is demonstrably healthy: measured during a
# trial, health passed every 10s for the first minute and then failed in bursts,
# with the VM unit itself still active/running and zero failed units in the guest.
# Give the agent room to answer instead of rolling back a working router.
HEALTH_TIMEOUT_SECONDS="${TRIAL_HEALTH_TIMEOUT_SECONDS:-60}"

health() {
  if [ -n "${HEALTH_COMMAND:-}" ]; then
    timeout "$HEALTH_TIMEOUT_SECONDS" bash -lc "$HEALTH_COMMAND" >/dev/null 2>&1
  else
    is_active "$NEW_UNIT"
  fi
}

guest_bash() {
  vm-exec "$NEW" /run/current-system/sw/bin/bash -lc "$1"
}

# Enter a container network namespace.
#
# The containers run inside the GUEST, not on the hypervisor host: `container@`
# units and /proc/<pid> only exist there. Resolve both the nspawn MainPID and
# its guest-init child from inside the guest, then nsenter into that netns.
container_init_pid() {
  local c="$1" pid child
  pid=$(guest_bash "systemctl show -p MainPID --value container@${c}.service" 2>/dev/null | tr -d ' \r\n')
  [ -n "${pid:-}" ] && [ "$pid" != "0" ] || return 1
  child=$(guest_bash "tr ' ' '\\n' < /proc/${pid}/task/${pid}/children | grep -E '^[0-9]+\$' | sort -n | head -1" 2>/dev/null | tr -d ' \r\n')
  [ -n "${child:-}" ] || return 1
  echo "$child"
}

run_in() {
  local c="$1" pid
  shift
  pid=$(container_init_pid "$c") || {
    echo "### ${c}: cannot resolve container init pid (guest-side lookup)" >&2
    return 1
  }
  # Build one argv for the guest shell so quoting survives the QGA hop.
  local q="" a
  for a in "$@"; do q="$q $(printf '%q' "$a")"; done
  guest_bash "/run/current-system/sw/bin/nsenter -t ${pid} -n --${q}"
}

diagnostics() {
  echo "[$(ts)] === diagnostics begin ==="
  guest_bash 'hostname; systemctl is-system-running; echo "--- failed units"; systemctl list-units --state=failed --no-pager; echo "--- containers"; nixos-container list'

  guest_bash '
    for c in $(nixos-container list); do
      echo "### $c"
      pid=$(systemctl show -p MainPID --value "container@$c.service" 2>/dev/null || true)
      [ -n "$pid" ] || continue
      child=$(cat "/proc/$pid/task/$pid/children" 2>/dev/null | awk "{print \$1}")
      [ -n "$child" ] && pid=$child
      /run/current-system/sw/bin/nsenter -t "$pid" -n -- /run/current-system/sw/bin/ip -4 route show table all 2>/dev/null | head -20
      /run/current-system/sw/bin/nsenter -t "$pid" -n -- /run/current-system/sw/bin/ip -6 route show table all 2>/dev/null | grep -E "^default" | head -10
    done
  '

  # A caller-provided script can add workload-specific checks (access, VPN,
  # core egress, DNS, etc.) without hard-coding router names here.
  if [ -n "$DIAG" ]; then
    echo "[$(ts)] custom diagnostics: $DIAG"
    bash "$DIAG" "$NEW" || echo "[$(ts)] custom diagnostics failed"
  fi
  echo "[$(ts)] === diagnostics end ==="
}

# A healthy image must have real routes, not just loopback. This is the
# assertion the previous trial lacked; it fails before the hold window.
assert_routes() {
  local c raw routes bad=0 pid
  for c in $(guest_bash 'nixos-container list' 2>/dev/null); do
    pid=$(container_init_pid "$c" 2>/dev/null || true)
    raw=$(run_in "$c" /run/current-system/sw/bin/ip -4 route show table all 2>&1)
    routes=$(printf '%s\n' "$raw" | grep -vE '^(local |broadcast )' | grep -E '^[^ ]' | head -3)
    if [ -z "$routes" ]; then
      echo "[$(ts)] ASSERT: $c has no non-loopback IPv4 route (init_pid=${pid:-none})"
      printf '%s\n' "$raw" | head -12 | sed 's/^/[$(ts)]   raw: /'
      bad=1
    fi
  done

  pid=$(container_init_pid access-clients-vpn 2>/dev/null || true)
  raw=$(run_in access-clients-vpn /run/current-system/sw/bin/ip -6 route show table all 2>&1)
  if ! printf '%s\n' "$raw" | grep -vE '^(local |broadcast )' | grep -qE '^[^ ]'; then
    echo "[$(ts)] ASSERT: access-clients-vpn has no non-loopback IPv6 route (init_pid=${pid:-none})"
    printf '%s\n' "$raw" | head -12 | sed 's/^/[$(ts)]   raw: /'
    bad=1
  fi

  # The WAN must hold a real (non-link-local) IPv4 address: the ISP hands the
  # core its public lease over s88-udhcpc-wan, and a vhost NIC whose tap was
  # never enslaved silently keeps the interface up but addressless, which every
  # route assertion above still passes. Observed exactly that on the first
  # vhost trial, so assert the lease explicitly.
  local wan_raw wan_addr
  wan_raw=$(run_in core /run/current-system/sw/bin/ip -4 -o addr show wan 2>&1)
  wan_addr=$(printf '%s\n' "$wan_raw" | sed -n 's/.* inet \([0-9.]*\/[0-9]*\) .*/\1/p' | head -1)
  if [ -z "$wan_addr" ]; then
    echo "[$(ts)] ASSERT: core wan has no IPv4 address (no ISP lease)"
    printf '%s\n' "$wan_raw" | head -6 | sed 's/^/[$(ts)]   raw: /'
    bad=1
  else
    echo "[$(ts)] WAN lease on core wan: $wan_addr"
  fi

  # The VPN underlays must themselves reach core: that is the "underlays
  # connect to core" requirement. Assert a default-carrying route exists via
  # each overlay interface rather than a fixed address, so the check tracks
  # whatever the model allocates.
  local u
  for u in core-vpn-onyx core-vpn-opal; do
    out=$(run_in "$u" /run/current-system/sw/bin/ip -4 route show table all 2>&1 | grep -m1 '^default')
    echo "[$(ts)] EGRESS $u -> upstream: ${out:-<none>}"
    if [ -z "$out" ]; then
      echo "[$(ts)] ASSERT: $u has no default route to its underlay"
      bad=1
    fi
  done

  return "$bad"
}

# Prove the intended lanes actually carry traffic, not just that routes exist.
# access-clients must reach core, and access-clients-vpn must leave via its VPN
# underlay; both are probed from inside the container that owns the lane.
assert_egress() {
  local bad=0 out
  out=$(run_in access-clients /run/current-system/sw/bin/ip -4 route get 10.1.0.1 2>&1 | head -2)
  echo "[$(ts)] EGRESS access-clients -> core: $(printf '%s' "$out" | tr '\n' ' ')"
  printf '%s' "$out" | grep -q 'dev access-clients' || { echo "[$(ts)] ASSERT: access-clients does not route via its fabric interface"; bad=1; }

  out=$(run_in access-clients-vpn /run/current-system/sw/bin/ip -4 route get 10.1.0.3 2>&1 | head -2)
  echo "[$(ts)] EGRESS access-clients-vpn -> vpn underlay: $(printf '%s' "$out" | tr '\n' ' ')"
  printf '%s' "$out" | grep -q 'dev acce-clie-vpn' || { echo "[$(ts)] ASSERT: access-clients-vpn does not route via its vpn interface"; bad=1; }

  out=$(run_in core /run/current-system/sw/bin/ip -4 route get 10.1.0.1 2>&1 | head -2)
  echo "[$(ts)] EGRESS core -> access fabric: $(printf '%s' "$out" | tr '\n' ' ')"
  printf '%s' "$out" | grep -qE 'dev (ens3|eth0|core)' || { echo "[$(ts)] ASSERT: core has no fabric route"; bad=1; }

  return "$bad"
}

rolled=0
rollback() {
  [ "$rolled" -eq 1 ] && return 0
  rolled=1
  echo "[$(ts)] ROLLBACK start"
  systemctl stop "$NEW_UNIT" >/dev/null 2>&1 || true
  for _ in $(seq 1 60); do
    is_active "$NEW_UNIT" || break
    sleep 1
  done
  local attempt
  for attempt in 1 2 3; do
    systemctl start "$PROD_UNIT" >/dev/null 2>&1 || true
    for _ in $(seq 1 90); do
      is_active "$PROD_UNIT" && break
      sleep 1
    done
    is_active "$PROD_UNIT" && break
    echo "[$(ts)] prod start attempt ${attempt} failed; retrying"
    sleep 5
  done
  touch "$MARKER" 2>/dev/null || true
  echo "[$(ts)] prod_active=$(systemctl is-active "$PROD_UNIT" 2>&1) new_active=$(systemctl is-active "$NEW_UNIT" 2>&1)"
  echo "[$(ts)] ROLLBACK done"
}
trap 'rollback' EXIT TERM INT HUP

# Prebuild/update while prod is still serving traffic.
if [ "$NO_UPDATE" -eq 1 ]; then
  echo "[$(ts)] prebuild skipped (--no-update)"
else
  echo "[$(ts)] prebuild $NEW (prod remains active)"
  # Keep the update output so spec warnings can be reported instead of scrolling
  # past. `vm-update`/register warnings are findings, not failures: they name a
  # requirement (e.g. FS-540 recursion intent) whose fix is an intent change.
  PREBUILD_LOG=$(mktemp)
  if [ -n "$IMAGE" ]; then
    nixos-shell-vm-manager register "$NEW_CONF" "$IMAGE" local-working-tree "$SOURCE" 2>&1 | tee "$PREBUILD_LOG"
  else
    vm-update "$NEW" "$SOURCE" 2>&1 | tee "$PREBUILD_LOG"
  fi
  echo "[$(ts)] prebuild complete"
  if grep -q 'evaluation warning' "$PREBUILD_LOG"; then
    while IFS= read -r line; do
      echo "[$(ts)] SPEC-WARNING: $line"
    done < <(grep -o 'evaluation warning: .*' "$PREBUILD_LOG" | sed -e 's/[[:space:]]*$//' | sort -u)
  else
    echo "[$(ts)] SPEC-WARNING: none"
  fi
  rm -f "$PREBUILD_LOG"
fi
systemctl stop "$NEW_UNIT" >/dev/null 2>&1 || true

# Independent backstop: if this script is SIGKILLed or wedged, prod still
# comes back after the hold window plus five minutes.
if [ "$NO_FAILSAFE" -eq 0 ]; then
  cat >"$FAILSAFE" <<EOF
#! /run/current-system/sw/bin/bash
set -u
export PATH=/run/current-system/sw/bin:/run/current-system/sw/sbin:/usr/bin:/bin
exec >>"${FAILSAFE_LOG}" 2>&1
ts() { date -Is; }
echo "[\$(ts)] failsafe check"
[ -e "${MARKER}" ] && exit 0
if systemctl is-active --quiet "${PROD_UNIT}"; then
  echo "[\$(ts)] prod already active"
  exit 0
fi
systemctl stop "${NEW_UNIT}" >/dev/null 2>&1 || true
for attempt in 1 2 3; do
  systemctl start "${PROD_UNIT}" >/dev/null 2>&1 || true
  for _ in \$(seq 1 90); do
    systemctl is-active --quiet "${PROD_UNIT}" && break
    sleep 1
  done
  systemctl is-active --quiet "${PROD_UNIT}" && break
  sleep 5
done
echo "[\$(ts)] failsafe prod_active=\$(systemctl is-active "${PROD_UNIT}" 2>&1) new_active=\$(systemctl is-active "${NEW_UNIT}" 2>&1)"
EOF
  chmod 700 "$FAILSAFE"
  systemctl stop "safe-test-${ROUTER}-failsafe.timer" >/dev/null 2>&1 || true
  systemd-run \
    --unit="safe-test-${ROUTER}-failsafe" \
    --on-active="$FAILSAFE_SECONDS" \
    --collect \
    "$FAILSAFE" >/dev/null 2>&1 || echo "[$(ts)] WARNING: could not install failsafe timer"
  echo "[$(ts)] failsafe armed for ${FAILSAFE_SECONDS}s"
fi

echo "[$(ts)] stopping prod"
systemctl stop "$PROD_UNIT" >/dev/null 2>&1 || true
for _ in $(seq 1 60); do
  is_active "$PROD_UNIT" || break
  sleep 1
done
is_active "$PROD_UNIT" && die "prod did not stop; aborting before starting new"

echo "[$(ts)] starting new"
systemctl start "$NEW_UNIT" >/dev/null 2>&1 || true
ok=0
for i in $(seq 1 "$HEALTH_RETRIES"); do
  if health; then
    ok=1
    echo "[$(ts)] health OK after $((i * 2))s"
    break
  fi
  sleep 2
done
[ "$ok" -eq 1 ] || die "new health check failed"

# QGA liveness fires long before the guest finishes booting (containers only
# get their routes once their own network units run). Wait for real boot
# completion first, otherwise the route assertions race the boot and report a
# false failure while prod is already stopped.
echo "[$(ts)] waiting for guest boot completion"
# Bounded on purpose: every second spent here is a second prod is stopped, so a
# candidate that never stops booting must roll back quickly rather than hold the
# site offline for the length of the old 10 minute budget. The budget is set from
# measurement: `systemd-analyze critical-chain` on a converged router shows
# multi-user.target at 3min27s, because each rendered container's own
# systemd-networkd-wait-online takes 90s. 300s covers that with margin while
# still failing an actually-stuck guest in five minutes rather than ten.
#
# Verified end-to-end on 2026-11-06 with image /nix/store/01jic3m8... (cobalt-new):
#   guest reached running after 290s; routes settled after 1 attempt(s)
#   WAN lease on core wan: <wan-ip>/23 (address redacted: public)
#   EGRESS access-clients -> core: 10.1.0.1 dev access-clients
#   EGRESS access-clients-vpn -> vpn underlay: 10.1.0.3 dev acce-clie-vpn
#   EGRESS core -> access fabric: 10.1.0.1 via 10.1.0.17 dev ens3
#   === 600s trial complete; restoring prod === (rollback 3s, prod active)
# and on the candidate itself: unbound `. IN forward 9.9.9.9 1.1.1.1` without any
# manual step, download 52.34 MB/s / upload 33.13 MB/s from the guest, where the
# production shape measured 12.86 MB/s up.
booted=0
for i in $(seq 1 60); do
  # `degraded` means boot finished with some unit failed: accepted here, because
  # a diagnostics unit that fails must not make a working router look unbooted.
  # Only `starting`/`initializing` mean boot is still in progress.
  if guest_bash 'test "$(systemctl is-system-running)" != starting -a "$(systemctl is-system-running)" != initializing' >/dev/null 2>&1; then
    booted=1
    echo "[$(ts)] guest reached running after $((i * 5))s"
    break
  fi
  sleep 5
done
if [ "$booted" -ne 1 ]; then
  # Dump what is holding boot before rolling back, otherwise the evidence dies
  # with the candidate.
  echo "[$(ts)] guest state: $(guest_bash 'systemctl is-system-running' 2>&1 | tail -1)"
  echo "[$(ts)] still-activating units:"
  guest_bash 'systemctl list-jobs --no-pager' 2>&1 | tail -20 || true
  echo "[$(ts)] failed units:"
  guest_bash 'systemctl list-units --state=failed --no-pager' 2>&1 | tail -20 || true
  die "guest did not reach running state within $((60 * 5))s"
fi

diagnostics
# Containers are still converging when the guest first answers: one trial
# failed here with the container's IPv6 routes visible in the raw dump taken
# immediately *after* the check, i.e. they landed microseconds too late. Retry
# until the routing table settles instead of asserting once.
routes_ok=0
for attempt in 1 2 3 4 5 6; do
  if assert_routes; then
    routes_ok=1
    echo "[$(ts)] routes settled after ${attempt} attempt(s)"
    break
  fi
  echo "[$(ts)] routes not settled yet (attempt ${attempt}/6); retrying in 10s"
  sleep 10
done
[ "$routes_ok" -eq 1 ] || die "route assertion failed"
assert_egress || die "egress assertion failed"

fails=0
for i in $(seq 1 "$HOLD"); do
  sleep 1
  if ! is_active "$NEW_UNIT"; then
    echo "[$(ts)] new went inactive at ${i}s"
    exit 1
  fi
  if [ $((i % 10)) -eq 0 ] && ! health; then
    fails=$((fails + 1))
    # Record the state that failed the check: "health lost" alone cannot tell a
    # stopped unit from one that is still activating, and that ambiguity has
    # already sent this investigation the wrong way once.
    echo "[$(ts)] health lost ${fails}/3 at ${i}s (state=$(systemctl show "$NEW_UNIT" -p ActiveState,SubState --value 2>/dev/null | tr '\n' '/'))"
    # The guest-side health command is "no failed units", so name them here:
    # "health lost" alone has already hidden a diagnostics unit failing.
    echo "[$(ts)] failed units: $(guest_bash 'systemctl list-units --state=failed --no-legend --plain --no-pager' 2>&1 | tr '\n' ';' | cut -c1-160)"
    # Name the failure mode of each failed unit: a timeout, an exit code and a
    # missing binary all look identical from "health lost" alone.
    echo "[$(ts)] failed detail: $(guest_bash 'for u in $(systemctl list-units --state=failed --no-legend --plain --no-pager | awk "{print \$1}"); do printf "%s result=%s status=%s; " "$u" "$(systemctl show "$u" -p Result --value)" "$(systemctl show "$u" -p ExecMainStatus --value)"; done' 2>&1 | tr '\n' ' ' | cut -c1-200)"
    echo "[$(ts)] failed journal: $(guest_bash 'journalctl -u router-selftest --no-pager -n 4 2>&1' 2>&1 | tr '\n' '|' | cut -c1-300)"
    [ "$fails" -ge 3 ] && exit 1
  fi
done

echo "[$(ts)] === ${HOLD}s trial complete; restoring prod ==="
exit 0
