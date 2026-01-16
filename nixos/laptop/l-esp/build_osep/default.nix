{ pkgs, ... }:
{
  imports = [
    ./bind-to-lxc.nix
    ./scraping-osep-material.nix
    ./x2go-client.nix
  ];
}
