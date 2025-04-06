{
  inputs = {
    #nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.11";
    nixos-x13s.url = "github:BrainWart/x13s-nixos";
  };

  #outputs =
  #  { ... }@inputs:
  #  {
  outputs = { nixpkgs, nixos-x13s, ... }@inputs: {
      nixosConfigurations.example = inputs.nixpkgs.lib.nixosSystem {
        system = "aarch64-linux";
        modules = [
          inputs.nixos-x13s.nixosModules.default
          ({ config, pkgs, ... }: {
            nixos-x13s.enable = true;
            #nixos-x13s.kernel = "jhovold"; # jhovold is default, but mainline supported
            nixos-x13s.bluetoothMac = "E9:1C:3B:F0:FD:8C";  # Example MAC address
            nixos-x13s.wifiMac = "8c:fd:f0:1c:3b:0a";

            # install multiple kernels! note this increases eval time for each specialization
            specialisation = {
              # note that activation of each specialization is required to copy the dtb to the EFI, and thus boot
              mainline.configuration.nixos-x13s.kernel = "mainline";
            };

            # allow unfree firmware
            nixpkgs.config.allowUnfree = true;

            # define your fileSystems
            boot.initrd.luks.devices = {
              root = {
                device = "/dev/nvme0n1p2";
              };
            };

            fileSystems."/".device = "/dev/mapper/root";

            system.stateVersion = "24.11";
            services.openssh.enable = true;

            environment.systemPackages = with pkgs; [
              util-linux
            ];


          })
        ];
      };
    };
}