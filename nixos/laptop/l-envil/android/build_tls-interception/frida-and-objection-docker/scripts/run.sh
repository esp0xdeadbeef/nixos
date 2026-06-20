#!/usr/bin/env bash
set -euo pipefail

# Manual override (leave empty to auto-discover)
searchForActiveApps="documents"
#targetApp="com.android.documentsui"
targetApp=""

if [[ -n "${targetApp}" ]]; then
  echo "[*] targetApp is defined."
  app="${targetApp}"
else
  echo "[*] targetApp is not defined, looking up at runtime: $searchForActiveApps"

  app="$(
    frida-ps -Uai --json \
    | jq -r --arg q "$searchForActiveApps" '
        .[]
        | select((.identifier // "") | test($q; "i"))
        | .identifier
      ' | head -n1
  )"
fi

if [[ -z "$app" ]]; then
  echo "[-] Could not resolve target app"
  frida-ps -Uai
  exit 1
fi

echo "[+] Target app: $app"

resolve_activity() {
  local pkg="$1"
  adb shell cmd package resolve-activity \
    --brief \
    -c android.intent.category.LAUNCHER \
    "$pkg" \
  | tail -n1 | tr -d '\r'
}

pkg="$app"
act="$(resolve_activity "$pkg")"

if [[ -z "$act" ]]; then
  echo "[-] Could not resolve launcher activity for $pkg"
  exit 1
fi

echo "[+] Launcher activity: $act"

# Kill existing instance
adb shell am force-stop "$pkg"

# Start app explicitly
adb shell am start -n "$act" >/dev/null

# Wait for PID deterministically
pid=""
while :;
do
  pid="$(adb shell pidof "$pkg" | tr -d '\r' || true)"
  [[ -n "$pid" ]] && break
done
if [[ -z "$pid" ]]; then
  echo "[-] Failed to obtain PID for $pkg"
  exit 1
fi

echo "[+] PID: $pid"
echo "[+] Attaching Frida..."

# Attach directly to the real process
frida -U -p "$pid" \
  -l ./http-connect-overwrite-proxy.js \
  -l tls-bypass.js

