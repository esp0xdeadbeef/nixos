#!/usr/bin/env bash
set -euo pipefail

echo "=============================================="
echo "  Frida Auto-Setup (STABLE: ADB FORWARD MODE)"
echo "=============================================="

# Force ONLY our venv tools (avoid base image venv)
export PATH="/opt/frida/venv/bin:/usr/bin:/bin"
unset VIRTUAL_ENV PYTHONPATH PYTHONHOME PIP_REQUIRE_VIRTUALENV

# Small helpers
log() { echo "[*] $*"; }
ok()  { echo "[+] $*"; }
die() { echo "[-] $*" >&2; exit 1; }

need() { command -v "$1" >/dev/null 2>&1 || die "Missing required binary: $1"; }

need adb
need curl
need xz
need nc
need python3

# 1) Determine Frida version from our venv (this is the client version we must match)
FRIDA_VER="$(python3 - << 'EOF'
import frida
print(frida.__version__)
EOF
)"
ok "Using Frida client version (venv): $FRIDA_VER"
ok "frida CLI: $((frida --version) 2>/dev/null || true)"
ok "frida-ps:  $((frida-ps --version) 2>/dev/null || true)"

# 2) Make sure ADB is up and device present
log "Starting adb server..."
adb start-server >/dev/null 2>&1 || true

log "Waiting for ADB device..."
adb wait-for-device

# 3) Ensure adbd root (your request: adb_root, no su)
log "Ensuring adb is running as root..."
adb root >/dev/null 2>&1 || true
adb wait-for-device

# 4) Detect ABI (minimal work in adb shell; just one getprop)
ABI="$(adb shell getprop ro.product.cpu.abi | tr -d '\r')"
ok "Detected ABI: $ABI"

case "$ABI" in
  arm64-v8a) ARCH="arm64" ; GADGET_ARCH="arm64" ; GADGET_DST="gadget-android-arm64.so" ;;
  x86_64)    ARCH="x86_64"; GADGET_ARCH="x86_64"; GADGET_DST="gadget-android-x86_64.so" ;;
  armeabi-v7a|armeabi) ARCH="arm"; GADGET_ARCH="arm"; GADGET_DST="gadget-android-arm.so" ;;
  *) die "Unsupported ABI: $ABI" ;;
esac

# 5) Download MATCHING frida-server
URL_SERVER="https://github.com/frida/frida/releases/download/${FRIDA_VER}/frida-server-${FRIDA_VER}-android-${ARCH}.xz"
OUT_XZ="/opt/frida/frida-server-${FRIDA_VER}-android-${ARCH}.xz"
OUT_BIN="/opt/frida/frida-server-${FRIDA_VER}-android-${ARCH}"

log "Downloading frida-server: $URL_SERVER"
curl -fsSL -o "$OUT_XZ" "$URL_SERVER"
xz -df "$OUT_XZ"
chmod +x "$OUT_BIN"

# 6) Kill old server(s) + helpers, push new, start
log "Killing old frida-server + helpers (best-effort)..."
adb shell 'pkill -9 frida-server 2>/dev/null || true; pkill -9 re.frida.helper 2>/dev/null || true' >/dev/null 2>&1 || true

log "Pushing fresh frida-server to /tmp/frida-server ..."
adb push "$OUT_BIN" /tmp/frida-server >/dev/null
adb shell 'chmod 755 /tmp/frida-server' >/dev/null

# Optional: permissive SELinux (best-effort, don’t fail if not allowed)
log "Best-effort: setenforce 0 (ignore failures)..."
adb shell 'setenforce 0 2>/dev/null || true' >/dev/null 2>&1 || true

# Start frida-server (DEFAULT: local-only on device; we use adb forward)
# Capture logs so we can debug crashes deterministically.
log "Starting frida-server (device-local) with log capture..."
adb shell 'nohup /tmp/frida-server >/data/local/tmp/frida-server.log 2>&1 & disown || true' >/dev/null 2>&1 || true

# 7) Set up ADB port forwarding (THIS is the stable part)
log "Setting up adb forward localhost:27042 -> device:27042 ..."
adb forward --remove tcp:27042 >/dev/null 2>&1 || true
adb forward tcp:27042 tcp:27042 >/dev/null

# 8) Verify port reachable locally, then verify Frida handshake via frida-ps -U
log "Waiting for local port 27042 to accept connections..."
for i in $(seq 1 30); do
  if nc -z 127.0.0.1 27042 >/dev/null 2>&1; then
    ok "Local forward is up: 127.0.0.1:27042"
    break
  fi
  sleep 0.2
done

if ! nc -z 127.0.0.1 27042 >/dev/null 2>&1; then
  echo "[-] Port 27042 not reachable locally. Dumping device log:"
  adb shell 'tail -n 200 /data/local/tmp/frida-server.log 2>/dev/null || true'
  die "frida-server didn't come up (or forward failed)"
fi

# Check versions *from device binary* too (not network)
SERVER_VER="$(adb shell '/tmp/frida-server --version 2>/dev/null' | tr -d '\r' || true)"
ok "Server version (device binary): ${SERVER_VER:-unknown}"

log "Testing Frida handshake via: frida-ps -U"
if ! frida-ps -U >/dev/null 2>&1; then
  echo "[-] frida-ps -U failed. Dumping device log (last 200 lines):"
  adb shell 'tail -n 200 /data/local/tmp/frida-server.log 2>/dev/null || true'
  echo ""
  echo "[-] Also show whether anything is listening on device 27042:"
  adb shell 'netstat -lntp 2>/dev/null | grep 27042 || ss -lntp 2>/dev/null | grep 27042 || true' || true
  die "Frida client could not speak to frida-server (even though TCP is up). Log above shows why."
fi
ok "Frida works (frida-ps -U succeeded)."

# 9) Download matching Frida Gadget locally (for jailed attach workflows)
# (Not always needed on rooted devices, but you asked for automation.)
URL_GADGET="https://github.com/frida/frida/releases/download/${FRIDA_VER}/frida-gadget-${FRIDA_VER}-android-${GADGET_ARCH}.so.xz"
DL_DIR="/root/Downloads"
mkdir -p "$DL_DIR" /root/.cache/frida

log "Downloading Frida Gadget: $URL_GADGET"
curl -fsSL -o "${DL_DIR}/frida-gadget-${FRIDA_VER}-android-${GADGET_ARCH}.so.xz" "$URL_GADGET"
xz -df "${DL_DIR}/frida-gadget-${FRIDA_VER}-android-${GADGET_ARCH}.so.xz"
cp -f "${DL_DIR}/frida-gadget-${FRIDA_VER}-android-${GADGET_ARCH}.so" "/root/.cache/frida/${GADGET_DST}"
ok "Gadget installed: /root/.cache/frida/${GADGET_DST}"


echo ""
echo "================ READY ================="
echo "Frida (stable):"
echo "  frida-ps -U"
echo ""
echo "Objection:"
#echo "  objection -g com.aurora.store explore"
echo "  objection -n com.aurora.store start"
echo "  # or: objection -g \"Aurora Store\" explore"
echo ""
echo "If you REALLY want remote mode later:"
echo "  (Start server with --listen 0.0.0.0:27042 and then use frida-ps -H <ip>:27042)"
echo "  But for you this has been flaky; -U + adb forward is stable."
echo "======================================="
echo ""
echo "A nice cheatsheet:"
echo "https://github.com/ivan-sincek/android-penetration-testing-cheat-sheet?tab=readme-ov-file#decode"
echo ""

# 10) Drop into a clean shell that cannot auto-activate base image venv
# - bash --noprofile --norc avoids sourcing anything that reactivates "mobile-setup-ubuntu"
exec env -i \
  HOME=/root \
  USER=root \
  PATH="/opt/frida/venv/bin:/usr/bin:/bin" \
  TERM="${TERM:-xterm-256color}" \
  PS1='(frida-venv) \u@\h:\w$ ' \
  /bin/bash --noprofile --norc -i

