{
  config,
  pkgs,
  lib,
  inputs,
  ...
}:

let
  ##############################################################################
  # 1) Compute the directories we need
  ##############################################################################

  # Your home directory
  homeDir = config.home.homeDirectory;

  # Where quickget drops all the ISOs (i.e. ~/.quickget)
  targetDir = "${homeDir}/.quickget";

  # The Windows-11 folder (and where virtio-win.iso must live)
  vmPath = "${targetDir}/windows-11";

  ##############################################################################
  # 2) Build a “fix-virtio-win11” wrapper that checks for virtio-iso first
  ##############################################################################

  fixVirtio = pkgs.writeShellScriptBin "fix-virtio-win11" ''
    #!${pkgs.bash}/bin/bash
    set -euo pipefail

    vmPath="${vmPath}"
    echo "Running fix-virtio-win11 → vmPath=\"${vmPath}\""



    # (a) Bail out early if the VirtIO ISO doesn’t exist or if virtio-cd #     directory already exists.
    if [[ ! -f "${vmPath}/virtio-win.iso" ]]; then
      echo "Error: virtio-win.iso not found at ${vmPath}/virtio-win.iso" >&2
      exit 1
    fi
    if [[ -d "${vmPath}/virtio-cd" ]]; then
      echo "Error: virtio-cd directory already exists at ${vmPath}/virtio-cd" >&2
      exit 1
    fi
    echo "✔ Found virtio-win.iso at ${vmPath}/virtio-win.iso"

    echo "1) Creating extraction directory..."
    mkdir -p "${vmPath}/virtio-cd"

    echo "2) Extracting virtio-win.iso (drivers only)..."
    "${pkgs.p7zip}/bin/7z" x "${vmPath}/virtio-win.iso" \
      -o"${vmPath}/virtio-cd" -bso0 -bsp0

    echo "3) Verifying extraction..."
    if [[ ! -d "${vmPath}/virtio-cd" ]] || [[ -z "$(ls -A "${vmPath}/virtio-cd")" ]]; then
      echo "Error: Extraction of virtio-cd failed!" >&2
      exit 1
    fi

    echo "4) Pruning everything except NetKVM, vioscsi, viostor, *.msi, and *.exe..."
    pushd "${vmPath}/virtio-cd" >/dev/null
    find . -mindepth 1 -maxdepth 1 \
      ! -name "NetKVM" \
      ! -name "vioscsi" \
      ! -name "viostor" \
      ! -name "*.msi" \
      ! -name "*.exe" \
      -exec rm -rf {} +
    popd >/dev/null

    echo "5) Moving aside old virtio-win.iso and rebuilding..."
    mv "${vmPath}/virtio-win.iso" "${vmPath}/virtio-win-broke-with-quickemu.iso" || true
    "${pkgs.cdrtools}/bin/mkisofs" -quiet \
      -o "${vmPath}/virtio-win.iso" \
      -V "fixed-cd" -J -R "${vmPath}/virtio-cd"

    echo "✔ Rebuilt ${vmPath}/virtio-win.iso successfully."

    # (Optional) If you still want to copy your own Windows 11 ISO here:
    if [[ -f ~/Downloads/windows-11-24h2-iso_202501/Win11_24H2_English_x64.iso ]]; then
      echo "6) Copying custom Windows 11 ISO into ${vmPath}/windows-11.iso..."
      cp ~/Downloads/windows-11-24h2-iso_202501/Win11_24H2_English_x64.iso \
         "${vmPath}/windows-11.iso"
    fi

    echo "Done."
  '';
in
{
  ##############################################################################
  # A) Make sure quickemu, p7zip, cdrtools, and our fixVirtio wrapper end up
  #    in the user’s $PATH.
  ##############################################################################
  home.packages = with pkgs; [
    inputs.nixpkgs-stable.legacyPackages.x86_64-linux.quickemu
    p7zip
    cdrtools
    fixVirtio
  ];

  ##############################################################################
  # B) Ensure ~/.quickget exists on activation
  ##############################################################################
  home.activation.ensureQuickgetDir = ''
    mkdir -p ${targetDir}
  '';

  ##############################################################################
  # C) One-shot service: download Windows 10 (unchanged from before)
  ##############################################################################
  systemd.user.services.quickget-windows-10 = {
    Unit = {
      Description = "Download Windows 10 via quickget (user service)";
      Wants = [ "network.target" ];
      After = [ "network.target" ];
    };
    Service = {
      Type = "oneshot";
      ExecStart = ''
        ${pkgs.bash}/bin/bash -c ' \
          if [ ! -f "${targetDir}/windows-10/virtio-win.iso" ]; then \
            cd "${targetDir}" && ls | grep -i 'windows-10' ||  \
            ${inputs.nixpkgs-stable.legacyPackages.x86_64-linux.quickemu}/bin/quickget windows 10; \
          fi \
        '
      '';
      TimeoutStartSec = "0";
    };
    Install = {
      WantedBy = [ "default.target" ];
    };
  };

  ##############################################################################
  # D) One-shot service: download Windows 11 (now only skips if virtio-win.iso exists)
  ##############################################################################
  systemd.user.services.quickget-windows-11 = {
    Unit = {
      Description = "Download Windows 11 via quickget (user service)";
      Wants = [ "network.target" ];
      After = [ "network.target" ];
    };
    Service = {
      Type = "oneshot";

      # Only run `quickget windows 11` if virtio-win.iso is missing.
      #
      # Note: inside single-quotes, ${targetDir} and ${inputs...quickget} get
      # interpolated at Nix-build time. At runtime, the shell sees something like:
      #   bash -c 'if [ ! -f "/home/you/.quickget/windows-11/virtio-win.iso" ]; then cd /home/you/.quickget && /nix/store/...-quickget/bin/quickget windows 11; fi'
      ExecStart = "${pkgs.bash}/bin/bash -c 'cd \"${targetDir}\"; if [ ! -d windows-11 ]; then ${inputs.nixpkgs-stable.legacyPackages.x86_64-linux.quickemu}/bin/quickget windows 11; fi; if [ -d windows-11 ] && [ ! -f windows-11/virtio-win ]; then ${fixVirtio}/bin/fix-virtio-win11; fi'";

      TimeoutStartSec = "0";
    };
    Install = {
      WantedBy = [ "default.target" ];
    };
  };
}
