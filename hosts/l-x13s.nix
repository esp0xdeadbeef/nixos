{
  mkNixOS,
  home-manager,
  nixpkgs,
  nixos-x13s,
  nixos-aarch64-widevine,
}:

{
  l-x13s =
    mkNixOS "aarch64-linux" "l-x13s"
      [
        nixos-x13s.nixosModules.default
        ./hardware/l-x13s/hardware-configuration.nix
      ]
      [
        home-manager.nixosModules.home-manager
        ./home-manager/l-x13s/home.nix
        ./time/timezone.nix
        {
          networking.hostName = "l-x13s";
          networking.networkmanager.enable = true;
          nixpkgs.config.allowUnfree = true;
          boot.loader.systemd-boot.configurationLimit = 15;
          nixpkgs.overlays = [ nixos-aarch64-widevine.overlays.default ];
        }
        ./secrets/import-secrets.nix
        ./packages/l-x13s/widevine.nix
        ./desktop/fonts.nix
        ./desktop/environment.nix
        ./system/garbage-collection.nix
        ./system/locale.nix
        ./network/firewall.nix
        ./desktop/applets.nix
        ./desktop/darkmode.nix
        ./desktop/shell-env.nix
        ./desktop/users-and-groups.nix
        ./system/version.nix
        ./system/autoupdate.nix
        ./packages/l-x13s/packages.nix
        ./general/tooling.nix
        {
          environment.interactiveShellInit = ''
            ZSH_THEME=trapd00r
          '';
        }
      ]
      true
      false;
}
