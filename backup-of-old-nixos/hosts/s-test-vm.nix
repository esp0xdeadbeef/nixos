{
  mkNixOS,
  nixpkgs,
  nixpkgs-unstable,
  home-manager,
  sops-nix,
}:
{
  # Add the sops-nix module import.
  s-test-vm =
    mkNixOS "x86_64-linux" "s-test-vm"
      [
        ./hardware/s-test-vm/hardware-configuration.nix
        ./hardware/s-test-vm/swap-and-tmpfs.nix
        ./hardware/s-test-vm/bootloader.nix
        ./hardware/is-vm/qemu-guest.nix
      ]
      [
        # (
        #   { config, pkgs, ... }:
        #   {
        #     imports = [ sops-nix.nixosModules ];

        #     sops = {
        #       unwrap = true;
        #       secrets = {
        #         mysecret = {
        #           file = ./hosts/secrets/secrets.yaml;
        #         };
        #       };
        #     };

        #     systemd.services.echoSecret = {
        #       description = "Echo secret for testing";
        #       serviceConfig = {
        #         Type = "oneshot";
        #         ExecStart = "${pkgs.bash}/bin/bash -c 'echo \"${config.sops.secrets.default.message}\"'";
        #       };
        #       wantedBy = [ "multi-user.target" ];
        #     };
        #   }
        # )

        # You can comment out or remove any additional module imports while testing.
        # Remove or postpone the use of ./secrets/import-secrets.nix if it’s causing conflicts.
        # Also temporarily reduce your module stack to isolate sops functionality.

        ./home-manager/l-x13s/home.nix
        ./desktop/fonts.nix
        ./desktop/environment.nix
        ./system/garbage-collection.nix
        ./system/locale.nix
        ./network/hostname.nix
        ./network/firewall.nix
        ./network/nat-lxc.nix
        ./desktop/applets.nix
        ./desktop/packages.nix
        ./desktop/darkmode.nix
        ./desktop/shell-env.nix
        {
          networking.hostName = "s-test-vm";
          services.openssh.enable = true;
          services.xserver.enable = true;
          services.desktopManager.plasma6.enable = true;
          boot.loader.systemd-boot.configurationLimit = 15;
          environment.interactiveShellInit = ''
            ZSH_THEME=fishy
          '';
          security.sudo.enable = true;
          security.sudo.extraRules = [
            {
              groups = [ "wheel" ];
              commands = [
                {
                  command = "ALL";
                  options = [ "NOPASSWD" ];
                }
              ];
            }
          ];
        }
      ]
      true
      true;
}
