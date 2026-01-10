{
  description = "NixOS VM: nixos-shell (shared store) + raw-efi disk image";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";

    nixos-generators = {
      url = "github:nix-community/nixos-generators";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, nixos-generators }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs { inherit system; };
      lib = nixpkgs.lib;
    in
    {
      ######################################################################
      # 1️⃣ NixOS configuration (USED BY nixos-shell)
      ######################################################################
      nixosConfigurations.vm = lib.nixosSystem {
        inherit system;
        modules = [
            ./nixos-vm-configuration/vm.nix  
        ];
      };

      ######################################################################
      # 2️⃣ Disk image output (USED BY build-vm.sh / libvirt)
      ######################################################################
      packages.${system} = {
        rawEfi = nixos-generators.nixosGenerate {
          inherit pkgs system;
          format = "raw-efi";

          modules = [
            ./configuration.nix

            # Large disposable disk (MiB)
            {
              virtualisation.diskSize = 200 * 1024;
            }

            # Force XFS instead of generator default ext4
            ({ lib, ... }: {
              fileSystems."/" = {
                fsType = lib.mkForce "xfs";
                options = [ "noatime" "nodiratime" ];
              };
            })
          ];
        };

        default = self.packages.${system}.rawEfi;
      };

      ######################################################################
      # 3️⃣ Dev shell (QEMU + libvirt + firmware paths)
      ######################################################################
      devShells.${system}.default = pkgs.mkShell {
        packages = with pkgs; [
          qemu_full
          libvirt
          virt-manager
          guestfs-tools
          jq
        ];

        shellHook = ''
          export OVMF_CODE=${pkgs.qemu_full}/share/qemu/edk2-x86_64-code.fd
          export OVMF_VARS_TEMPLATE=${pkgs.qemu_full}/share/qemu/edk2-i386-vars.fd

          echo "Pinned OVMF:"
          echo "  OVMF_CODE=$OVMF_CODE"
          echo "  OVMF_VARS_TEMPLATE=$OVMF_VARS_TEMPLATE"
        '';
      };
    };
}

