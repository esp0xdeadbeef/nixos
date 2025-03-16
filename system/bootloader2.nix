{ pkgs, lib, ... }: {

            environment.systemPackages = [
              # For debugging and troubleshooting Secure Boot.
              pkgs.sbctl
              pkgs.tpm2-tss
            ];

            # Lanzaboote currently replaces the systemd-boot module.
            # This setting is usually set to true in configuration.nix
            # generated at installation time. So we force it to false
            # for now.
            boot.loader.systemd-boot.enable = lib.mkForce false;

#boot.initrd.systemd.enableTpm2 = true;
#security.tpm2.enable = true;

            boot.lanzaboote = {
              enable = true;
              #pkiBundle = "/var/lib/sbctl";
              #pkiBundle = "/var/lib/sbctl";
              pkiBundle = "/etc/secureboot";


            };
          }
