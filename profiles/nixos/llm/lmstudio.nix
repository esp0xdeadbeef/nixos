{ pkgs, ... }:

{
  environment.systemPackages = [
    pkgs.lmstudio
  ];
}
