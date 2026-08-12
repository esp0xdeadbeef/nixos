{ lib
, pkgs
, profiles
, relativeRepo
, ...
}:

{
  imports = [
    (relativeRepo.module "library/01-general/password-cracking/default.nix")
    (relativeRepo.module "library/10-vms/nixos-shell-vm/host-config/base.nix")
    (relativeRepo.module "modules/nixos/cuda-cache.nix")
    profiles.nixos.impermanence.default
    profiles.nixos.llm-clients.agents
    profiles.nixos.llm.ollama-base
    profiles.nixos.llm.ollama-gpu-ready
    profiles.nixos.llm.ollama-smoke-test
    profiles.nixos.virtualization.pci-passthrough-guest

    ./benchmark.nix
    ./container
    ./nvidia.nix
    ./ollama.nix
    ./ollama-state.nix
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
    # P100 (Pascal) needs custom CUDA architectures that miss the binary
    # cache.  Pin ollama to stable nixpkgs so it only rebuilds on stable
    # branch updates instead of every unstable bump.
    ollamaPinToStable = true;
  };

  local.impermanence = {
    enable = true;
    rotateBtrfsRoot.enable = false;
  };

  local.virtualization.pciPassthroughGuest.enable = true;

  virtualisation = {
    cores = lib.mkForce 16;
    memorySize = lib.mkForce (256 * 1024);
    # Keep the replaceable nixos-shell root disk small; durable state lives in
    # the host-backed /persist mount.
    diskSize = lib.mkForce (8 * 1024);

  };

  environment.systemPackages = [
    pkgs.curl
    pkgs.pciutils
  ];

  system.stateVersion = lib.mkForce "26.05";
}
