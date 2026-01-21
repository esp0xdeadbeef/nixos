{
  description = "pbtk GUI devshell";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = { self, nixpkgs }:
  let
    system = "x86_64-linux";
    pkgs = import nixpkgs { inherit system; };

    python = pkgs.python3.withPackages (ps: with ps; [
      protobuf
      requests
      websocket-client
      pyqt5
      pyqtwebengine
    ]);
  in {
    devShells.${system}.default = pkgs.mkShell {
      packages = [
        python

        # Qt runtime libs (WebEngine + X11 extras)
        pkgs.qt5.qtbase
        pkgs.qt5.qtwebengine
        pkgs.qt5.qtx11extras

        # pbtk mentions Java runtime for extractors; jadx also needs Java
        pkgs.jre

        pkgs.git
      ];

      # Helps QtWebEngine find its resources/plugins in Nix store setups
      shellHook = ''
        export QT_PLUGIN_PATH="${pkgs.qt5.qtbase}/${pkgs.qt5.qtbase.qtPluginPrefix}"
        export QML2_IMPORT_PATH="${pkgs.qt5.qtbase}/${pkgs.qt5.qtbase.qtQmlPrefix}"
        echo "[*] Ready: run ./gui.py"
      '';
    };
  };
}

