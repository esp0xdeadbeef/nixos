{ config, lib, pkgs, ... }:
let
  cfg = config.local.work.microsoft;
in
{
  options.local.work.microsoft.enable = lib.mkEnableOption "Microsoft work apps";

  config = lib.mkIf cfg.enable {
    home.packages = with pkgs; [
      azure-cli
      intune-portal
      teams-for-linux
    ];
  };
}
