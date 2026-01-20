{
  description = "Deterministic Frida setup for Android Emulator (no local Frida build)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs { inherit system; };

      fridaVersion = "17.6.0";

      # === Frida SERVER (pinned, for Android x86_64 emulator) ===
      fridaServer = pkgs.fetchurl {
        url =
          "https://github.com/frida/frida/releases/download/${fridaVersion}/frida-server-${fridaVersion}-android-x86_64.xz";
        sha256 =
          "e98054720372621839469cdb71eb2261c5ec4cddfe4af8eac2eae8864ffd4497";
      };

      # === Helper that pushes + starts frida-server on the emulator ===
      fridaAdbBootstrap = pkgs.writeShellScriptBin "frida-emu-bootstrap" ''
        set -euo pipefail

        echo "[*] Checking for authorized device..."
        if ! adb devices | grep -q "device"; then
          echo "[!] No authorized device detected."
          echo "    Make sure your emulator is running and USB debugging is allowed."
          exit 1
        fi

        echo "[*] Decompressing pinned frida-server..."
        TMPDIR=$(mktemp -d)
        cp ${fridaServer} "$TMPDIR/frida-server.xz"
        unxz "$TMPDIR/frida-server.xz"

        echo "[*] Pushing to emulator..."
        adb push "$TMPDIR/frida-server" /data/local/tmp/frida-server
        adb shell chmod 755 /data/local/tmp/frida-server

        echo "[*] Starting frida-server..."
        adb shell "nohup /data/local/tmp/frida-server > /data/local/tmp/frida.log 2>&1 &"

        echo "[*] Waiting for frida-server to be ready..."
        for i in $(seq 1 10); do
          if adb shell netstat -lnt | grep -q "27042"; then
            echo "[+] frida-server is listening on 27042"
            break
          fi
          sleep 1
        done

        echo "[*] Testing connection from host..."
        if ! frida-ps -U >/dev/null; then
          echo "[!] frida-ps failed — check /data/local/tmp/frida.log"
          exit 1
        fi

        echo "[+] Frida is fully operational"
      '';

      devShell = pkgs.mkShell {
        packages = [
          pkgs.frida-tools     # STOCK client (known-good on your system)
          pkgs.android-tools   # adb
          pkgs.xz              # for unxz
          fridaAdbBootstrap    # your helper script
        ];

        FRIDA_VERSION = fridaVersion;
        FRIDA_SERVER_XZ = fridaServer;

        shellHook = ''
          printf "\n========================================\n"
          printf " Frida (server ${fridaVersion}) ready\n\n"
          printf "  1) Start your Android emulator\n"
          printf "  2) Run:  frida-emu-bootstrap\n\n"
          printf "Check:\n"
          printf "  frida --version\n"
          printf "  frida-ps -U\n"
          printf "========================================\n\n"
        '';
      };

    in {
      default = devShell;
      devShells.${system}.default = devShell;
      devShells.default = devShell;
    };
}

