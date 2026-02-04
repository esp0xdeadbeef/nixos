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

# 1) Determine Frida version from our venv
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

# 3) Ensure adbd root (no su yet)
log "Ensuring adb is running as root..."
adb root >/dev/null 2>&1 || true
adb wait-for-device

# ------------------------------------------------------------
# CRITICAL PART: probe remote scratch directory ONCE
# ------------------------------------------------------------

log "Probing remote writable exec directory..."

if adb shell "ls /data/local/tmp >/dev/null 2>&1"; then
  FRIDA_DST_DIR="/data/local/tmp"
elif adb shell "ls /tmp >/dev/null 2>&1"; then
  FRIDA_DST_DIR="/tmp"
else
  die "No usable temp directory found on device"
fi

ok "Using remote directory: $FRIDA_DST_DIR"
FRIDA_REMOTE="$FRIDA_DST_DIR/frida-server"
LOG_FILE="/data/local/tmp/frida-server.log"

# ------------------------------------------------------------

# 4) Detect ABI
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

# 6) Kill old server(s)
log "Killing old frida-server + helpers..."
adb shell 'pkill -9 frida-server 2>/dev/null || true; pkill -9 re.frida.helper 2>/dev/null || true' >/dev/null 2>&1 || true

# 7) Push new server
log "Pushing fresh frida-server to $FRIDA_REMOTE ..."
adb push "$OUT_BIN" "$FRIDA_REMOTE" >/dev/null
adb shell "chmod 755 $FRIDA_REMOTE" >/dev/null

# Optional: permissive SELinux
log "Best-effort: setenforce 0 (ignore failures)..."
adb shell 'setenforce 0 2>/dev/null || true' >/dev/null 2>&1 || true

# 8) Start frida-server (direct first, then su fallback)
have_su() { adb shell "command -v su >/dev/null 2>&1" >/dev/null 2>&1; }
is_running() { adb shell "pidof frida-server >/dev/null 2>&1" >/dev/null 2>&1; }

log "Starting frida-server (direct)..."
adb shell "nohup $FRIDA_REMOTE >$LOG_FILE 2>&1 &" >/dev/null 2>&1 || true
sleep 0.8

if ! is_running && have_su; then
  log "Direct start failed, retrying via su..."
  adb shell "su -c 'nohup $FRIDA_REMOTE >$LOG_FILE 2>&1 &'" >/dev/null 2>&1 || true
  sleep 0.8
fi

if ! is_running; then
  echo "[-] frida-server did not start. Dumping device log:"
  adb shell "tail -n 200 $LOG_FILE 2>/dev/null || true"
  die "frida-server failed to start"
fi
ok "frida-server is running"

# 9) ADB forward
log "Setting up adb forward localhost:27042 -> device:27042 ..."
adb forward --remove tcp:27042 >/dev/null 2>&1 || true
adb forward tcp:27042 tcp:27042 >/dev/null

# 10) Verify port
log "Waiting for local port 27042..."
for i in $(seq 1 30); do
  if nc -z 127.0.0.1 27042 >/dev/null 2>&1; then
    ok "Local forward is up"
    break
  fi
  sleep 0.2
done

if ! nc -z 127.0.0.1 27042 >/dev/null 2>&1; then
  echo "[-] Port not reachable. Device log:"
  adb shell "tail -n 200 $LOG_FILE 2>/dev/null || true"
  die "ADB forward failed"
fi

# 11) Version check
SERVER_VER="$(adb shell "$FRIDA_REMOTE --version 2>/dev/null" | tr -d '\r' || true)"
if [ -z "$SERVER_VER" ] && have_su; then
  SERVER_VER="$(adb shell "su -c '$FRIDA_REMOTE --version 2>/dev/null'" | tr -d '\r' || true)"
fi
ok "Server version: ${SERVER_VER:-unknown}"

# 12) Handshake test
log "Testing Frida handshake..."
if ! frida-ps -U >/dev/null 2>&1; then
  echo "[-] frida-ps failed. Device log:"
  adb shell "tail -n 200 $LOG_FILE 2>/dev/null || true"
  die "Frida client cannot talk to server"
fi
ok "Frida works"

# 13) Gadget
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
echo "frida-ps -U"
echo "objection -n com.aurora.store start"
echo "======================================="

exec env -i \
  HOME=/root \
  USER=root \
  PATH="/opt/frida/venv/bin:/usr/bin:/bin" \
  TERM="${TERM:-xterm-256color}" \
  PS1='(frida-venv) \u@\h:\w$ ' \
  /bin/bash --noprofile --norc -i

