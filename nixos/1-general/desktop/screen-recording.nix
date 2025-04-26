{
  pkgs,
  config,
  lib,
  ...
}:

{
  environment.systemPackages = with pkgs; [
	peek
        obs-studio
  ];
}
