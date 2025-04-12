{
  description = "Minimal sops-nix test flake";

  inputs = {
    # Use the stable NixOS channel (nixos-24.11 in this example)
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.11";
    # Use the sops-nix module from Mic92
    sops-nix.url = "github:Mic92/sops-nix";
  };

  outputs = { self, nixpkgs, sops-nix, ... }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs { inherit system; };
      mySystem = pkgs.lib.nixosSystem {
        system = system;
        # Merge only sops-nix and our custom module.
        modules = [
          # Import sops-nix’s module definitions.
          sops-nix.nixosModules
          # Wrap your custom configuration in a lambda so that the NixOS module system
          # provides variables like "config" during module merging.
          ( { config, pkgs, ... }:
            {
              # Sops configuration: unwrap the secret "mysecret".
              sops = {
                unwrap = true;
                secrets = {
                  mysecret = {
                    # The file path is relative to this flake.nix.
                    file = ./hosts/secrets/secrets.yaml;
                  };
                };
              };

              # A simple systemd service that echoes the secret.
              systemd.services.echoSecret = {
                description = "Echo secret for testing";
                serviceConfig = {
                  Type = "oneshot";
                  ExecStart = "${pkgs.bash}/bin/bash -c 'echo \"${config.sops.secrets.mysecret.message}\"'";
                };
                wantedBy = [ "multi-user.target" ];
              };
            }
          )
        ];
      };
    in {
      # Expose the system derivation under packages for the current system.
      packages = {
        "${system}" = {
          sopsTest = mySystem;
        };
      };

      # Optionally expose a configuration fragment for inspection.
      configs = {
        "${system}" = {
          echoSecret =
            mySystem.config.system.build.config.systemd.services.echoSecret.serviceConfig.ExecStart;
        };
      };
    };
}
