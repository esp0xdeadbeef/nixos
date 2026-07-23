{ lib
, pkgs
, profiles
, relativeRepo
, ...
}:

{
  imports = [
    (relativeRepo.module "library/01-general/password-cracking/default.nix")
    (relativeRepo.module "library/10-vms/nixos-shell-vm/host-config/ssh.nix")
    (relativeRepo.module "library/10-vms/nixos-shell-vm/host-config/vm-settings.nix")
    (relativeRepo.module "modules/nixos/cuda-cache.nix")
    profiles.nixos.impermanence.default
    profiles.nixos.llm-clients.agents
    profiles.nixos.llm.ollama-base
    profiles.nixos.nixos-shell-host.common

    ./benchmark.nix
    ./network.nix
    ./nvidia.nix
    ./ollama.nix
  ];

  # The s-llm-inference service VM has no secrets. Interactive access is SSH-key-only, so a
  # per-VM SOPS identity and password secret are deliberately unnecessary.
  local.nixosShellHost.secrets.enable = false;
  local.users.primary.name = "deadbeef";

  users.users.deadbeef = {
    isNormalUser = true;
    hashedPassword = "!";
    shell = pkgs.zsh;
  };

  programs.zsh.enable = true;

  # Keep the CUDA closures built specifically for the P100, just as l-envil
  # targets compute capability 8.6 for its GPU workloads.
  nixpkgs.config = {
    cudaCapabilities = [ "6.0" ];
    cudaForwardCompat = false;
  };

  local.impermanence = {
    enable = true;
    rotateBtrfsRoot.enable = false;
    # The existing nixos-shell /persist share is host-backed. Keep Podman's
    # image store there as well; the Ollama model homes are covered below and
    # by the shared /var/lib/private/ollama persistence rule.
    extraSystemDirectories = [ "/var/lib/containers" ];
  };

  virtualisation = {
    cores = lib.mkForce 16;
    memorySize = lib.mkForce (256 * 1024);
    diskSize = lib.mkForce (40 * 1024);

    # q35 gives the P100's 16 GiB 64-bit BAR a native PCIe topology. The
    # nixos-shell runner merges this with its generated acceleration option.
    qemu.options = lib.mkAfter [
      "-machine q35"
      "-cpu host"
    ];
  };

  environment.systemPackages = [
    pkgs.curl
    pkgs.pciutils
  ];

  system.stateVersion = lib.mkForce "26.05";
}
