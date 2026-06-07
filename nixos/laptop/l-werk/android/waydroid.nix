{
  config,
  pkgs,
  lib,
  ...
}:

let
  # ==========================
  # USER SETTINGS
  # ==========================
  waydroidBridge = "lxcbr0";
  enableMitmForWaydroid = true;

  # Path to your cert on the HOST
  certOnHost = "/home/deadbeef/.mitmproxy/mitmproxy-ca-cert.pem";

  # Waydroid system overlay trust store
  systemStoreOverlay = "/var/lib/waydroid/overlay/system/etc/security/cacerts";

  # ===========================================================
  # SCRIPT: PHASE 1 — SYSTEM STORE INJECTION
  # ===========================================================
  waydroidSetup = pkgs.writeShellScript "waydroid-setup" ''
    #!/bin/sh
    set -e

    if [ ! -f /var/lib/waydroid/lxc/waydroid/config ]; then
      echo "[*] Waydroid not initialized — running waydroid init..."
      ${pkgs.waydroid}/bin/waydroid init -s VANILLA || \
        ${pkgs.waydroid}/bin/waydroid init
    fi

    # Ensure correct bridge
    if grep -q 'lxc.net.0.link' /var/lib/waydroid/lxc/waydroid/config; then
      sed -i 's|^lxc.net.0.link = .*|lxc.net.0.link = ${waydroidBridge}|' \
        /var/lib/waydroid/lxc/waydroid/config
    else
      echo "lxc.net.0.link = ${waydroidBridge}" >> \
        /var/lib/waydroid/lxc/waydroid/config
    fi

    ${lib.optionalString enableMitmForWaydroid ''
      # ---- Inject MITM cert into SYSTEM store (overlay) ----
      CERT="${certOnHost}"
      OVERLAY_DIR="${systemStoreOverlay}"

      if [ -f "$CERT" ]; then
        HASH=$(${pkgs.openssl}/bin/openssl x509 \
          -subject_hash_old -in "$CERT" | head -n1)

        TARGET="$OVERLAY_DIR/$HASH.0"
        mkdir -p "$OVERLAY_DIR"

        if [ -f "$TARGET" ]; then
          echo "[*] MITM cert already present in SYSTEM store — skipping"
        else
          echo "[*] Installing MITM cert into Waydroid SYSTEM store..."
          cp "$CERT" "$TARGET"
          chmod 644 "$TARGET"
          echo "[*] Installed MITM CA as $TARGET"
        fi
      else
        echo "[!] MITM cert not found at $CERT — skipping injection"
      fi
    ''}
  '';

  # ===========================================================
  # SCRIPT: PHASE 2 — ROOT (USER STORE + PROXY)
  # ===========================================================
  waydroidMitmRoot = pkgs.writeShellScript "waydroid-mitm-root" ''
    #!/bin/sh
    set -e

    echo "[*] Waiting for Waydroid shell (root)..."

    for i in $(seq 1 120); do
      if ${pkgs.waydroid}/bin/waydroid shell -- true >/dev/null 2>&1; then
        break
      fi
      sleep 1
    done

    if ! ${pkgs.waydroid}/bin/waydroid shell -- true >/dev/null 2>&1; then
      echo "[!] Waydroid shell not ready — retrying"
      exit 1
    fi

    CERT="${certOnHost}"
    if [ ! -f "$CERT" ]; then
      echo "[!] MITM cert not found — nothing to do"
      exit 0
    fi

    HASH=$(${pkgs.openssl}/bin/openssl x509 \
      -subject_hash_old -in "$CERT" | head -n1)

    USER_STORE=/data/misc/user/0/cacerts-added

    echo "[*] Installing cert into Waydroid USER store..."

    ${pkgs.waydroid}/bin/waydroid shell -- mkdir -p $USER_STORE
    ${pkgs.waydroid}/bin/waydroid shell -- \
      cp /system/etc/security/cacerts/$HASH.0 $USER_STORE/$HASH.0
    ${pkgs.waydroid}/bin/waydroid shell -- \
      chmod 644 $USER_STORE/$HASH.0

    echo "[*] Determining gateway (HOST awk, from Waydroid output)..."

    GATEWAY=$(
      ${pkgs.waydroid}/bin/waydroid shell -- ip route show table eth0 \
      | ${pkgs.gawk}/bin/awk '/default/ {print $3}'
    )

    if [ -z "$GATEWAY" ]; then
      echo "[!] Could not determine Waydroid gateway — retrying"
      exit 1
    fi

    echo "[*] Waydroid gateway detected: $GATEWAY"
    echo "[*] Setting HTTP proxy inside Waydroid to $GATEWAY:8082"

    ${pkgs.waydroid}/bin/waydroid shell -- \
      settings put global http_proxy "$GATEWAY:8082"

    echo "[*] Done."
  '';

in
{
  environment.systemPackages = with pkgs; [
    waydroid
    cage
    lxc
    dbus
    iproute2
    gawk
    coreutils
  ];

  # ===========================================================
  # PHASE 1 — SYSTEM SERVICE (start container + inject SYSTEM cert)
  # ===========================================================
  systemd.services.waydroid-container = {
    description = "Waydroid Android container";
    wantedBy = [ "multi-user.target" ];
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];

    serviceConfig = {
      Type = "simple";
      ExecStartPre = waydroidSetup;
      ExecStart = "${pkgs.waydroid}/bin/waydroid container start";
      ExecStop = "${pkgs.waydroid}/bin/waydroid container stop";
      Restart = "on-failure";
    };
  };

  systemd.user.services."waydroid-cage" = {
    description = "Launch Waydroid Android UI in Cage";
    after = [ "graphical-session.target" ];
    wantedBy = [ "graphical-session.target" ];
    serviceConfig = {
      ExecStart = "${pkgs.cage}/bin/cage ${pkgs.waydroid}/bin/waydroid show-full-ui";
      Restart = "on-failure";
    };
  };

  #programs.adb.enable = true;

  systemd.services."waydroid-mitm-root" = {
    description = "Inject MITM cert into Waydroid USER store + set proxy (root)";

    after = [ "waydroid-container.service" ];
    wants = [ "waydroid-container.service" ];
    wantedBy = [ "multi-user.target" ];

    serviceConfig = {
      Type = "oneshot";
      Restart = "on-failure";
      RestartSec = "3s";
      StartLimitIntervalSec = 0;
      ExecStart = waydroidMitmRoot;
    };
  };
}
