{ config, pkgs, ... }: {
    services.openssh.enable = true;
    environment.systemPackages = with pkgs; [
      rocmPackages.rocm-smi
    ];
}