{ pkgs, ... }:
{
  imports = [
    ./host
    ./hostname.nix
  ];
}
