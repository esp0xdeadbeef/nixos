{ config, pkgs, lib, inputs, ... }:

let
  homeDir   = config.home.homeDirectory;
  targetDir = "${homeDir}/.quickget";
in
{
  # 1) Ensure quickemu is installed in your user profile
  home.packages = with pkgs; [ inputs.nixpkgs-stable.legacyPackages.x86_64-linux.quickemu ];

  # 2) Create the base directory at activation time
  home.activation.ensureQuickgetDir = ''
    mkdir -p ${targetDir}
  '';

  # 3) Define the two one-shot services, using single-quoted shell commands
  systemd.user.services.quickget-windows-10 = {
    Unit = {
      Description = "Download Windows 10 via quickget (user-service)";
      Wants       = [ "network-online.target" ];
      After       = [ "network-online.target" ];
    };
    Service = {
      Type = "oneshot";
      ExecStart = ''
        ${pkgs.bash}/bin/bash -c 'cd ${targetDir} && ${inputs.nixpkgs-stable.legacyPackages.x86_64-linux.quickemu}/bin/quickget windows 10'
      '';
      TimeoutStartSec = "0";
    };
    Install = {
      WantedBy = [ "default.target" ];
    };
  };

  systemd.user.services.quickget-windows-11 = {
    Unit = {
      Description = "Download Windows 11 via quickget (user-service)";
      Wants       = [ "network-online-target" ];
      After       = [ "network-online.target" ];
    };
    Service = {
      Type = "oneshot";
      ExecStart = ''
        ${pkgs.bash}/bin/bash -c 'cd ${targetDir} && ${inputs.nixpkgs-stable.legacyPackages.x86_64-linux.quickemu}/bin/quickget windows 11'
      '';
      TimeoutStartSec = "0";
    };
    Install = {
      WantedBy = [ "default.target" ];
    };
  };
}
