{
  description = "MITM CA injector for rooted OnePlus 5 (LineageOS) - smart IP detection + adb root only";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs =
    { self
    , nixpkgs
    , flake-utils
    ,
    }:
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = import nixpkgs { inherit system; };

        injectFullScript = pkgs.writeShellScript "inject-mitm-android-full" ''
                    set -euo pipefail
                    export PATH=${
                      pkgs.lib.makeBinPath [
                        pkgs.android-tools # adb
                        pkgs.iproute2 # ip
                        pkgs.gawk # awk
                        pkgs.openssl # openssl
                        pkgs.coreutils # cp, mkdir, chmod, etc
                        pkgs.gnugrep # grep
                        pkgs.gnused # sed (just in case)
                      ]
                    }
                    PROXY_PORT=8082

                    # --- SMART LAPTOP IP DETECTION ---
                    # 1) If user sets MITM_IP, trust it.
                    # 2) Otherwise pick the first global IPv4 address that is NOT the gateway (.1)
                    if [ -n "''${MITM_IP:-}" ]; then
                      LAPTOP_IP="$MITM_IP"
                      echo "[*] Using user-provided MITM_IP: $LAPTOP_IP"
                    else
                      GATEWAY=$(ip -4 route show default | awk '{print $3}')
                      LAPTOP_IP=$(ip -4 -o addr show scope global \
                        | awk '{split($4,a,"/"); print a[1]}' \
                        | grep -v "^$GATEWAY$" \
                        | head -n1)

                      if [ -z "$LAPTOP_IP" ]; then
                        echo "[!] Could not auto-detect a suitable laptop IP."
                        echo "    Set it manually: MITM_IP=192.168.1.xxx nix run path:.#inject-mitm-android-full"
                        exit 1
                      fi
                    fi

                    echo "[*] Using laptop IP for proxy: $LAPTOP_IP"

                    CERT="$HOME/.mitmproxy/mitmproxy-ca-cert.pem"

                    if [ ! -f "$CERT" ]; then
                      echo "[!] Cannot find $CERT"
                      exit 1
                    fi

                    echo "[*] Restarting ADB as root..."
                    adb root || true
                    sleep 2
                    adb wait-for-device

                    echo "[*] Calculating Android CA hash..."
                    HASH=$(openssl x509 -subject_hash_old -in "$CERT" | head -n1)
                    echo "[*] Hash: $HASH"

                    TMP_CERT="/tmp/$HASH.0"
                    cp "$CERT" "$TMP_CERT"

                    echo "[*] Pushing cert to device..."
                    adb push "$TMP_CERT" "/sdcard/$HASH.0"

                    echo "[*] Creating installer script on host..."
                    INSTALLER="/tmp/install-mitm.sh"

                    cat > "$INSTALLER" <<EOF
          #!/system/bin/sh
          set -e

          echo "[*] Remounting /system..."
          mount -o rw,remount / || mount -o rw,remount /system || true

          # Determine correct system CA path
          if [ -d /system/etc/security/cacerts ]; then
            SYS_DEST=/system/etc/security/cacerts
          else
            SYS_DEST=/system/system/etc/security/cacerts
          fi

          USER_DEST=/data/misc/user/0/cacerts-added

          echo "[*] Using system store: \$SYS_DEST"
          echo "[*] Using user store: \$USER_DEST"

          mkdir -p "\$SYS_DEST"
          mkdir -p "\$USER_DEST"

          cp "/sdcard/$HASH.0" "\$SYS_DEST/$HASH.0"
          cp "/sdcard/$HASH.0" "\$USER_DEST/$HASH.0"

          chmod 644 "\$SYS_DEST/$HASH.0"
          chmod 644 "\$USER_DEST/$HASH.0"

          echo "[*] Installed $HASH.0 to both stores"
          EOF

                    echo "[*] Pushing installer script to device..."
                    adb push "$INSTALLER" /sdcard/install-mitm.sh

                    echo "[*] Running installer script on device (as adb-root)..."
                    adb shell "sh /sdcard/install-mitm.sh"

                    echo "[*] Rebooting device..."
                    adb reboot

                    echo "[*] Waiting for device USB..."
                    adb wait-for-device

                    echo "[*] Restarting ADB as root again after reboot..."
                    adb root || true
                    sleep 2
                    adb wait-for-device

                    echo "[*] Waiting for Android framework (settings service)..."
                    for i in $(seq 1 60); do
                      if adb shell "cmd -l | grep -q settings"; then
                        echo "[*] Settings service is ready."
                        break
                      fi
                      echo "[*] Settings not ready yet... ($i/60)"
                      sleep 1
                    done

                    echo "[*] Setting global HTTP proxy to $LAPTOP_IP:$PROXY_PORT"
                    adb shell "settings put global http_proxy \"$LAPTOP_IP:$PROXY_PORT\""

                    echo "[*] All done."
        '';
      in
      {
        apps = {
          inject-mitm-android-full = {
            type = "app";
            program = "${injectFullScript}";
          };
        };
      }
    );
}
