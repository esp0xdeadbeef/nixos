{
  inputs,
  config,
  lib,
  pkgs,
  modulesPath,
  outPath,
  ...
}:

let
  identity = {
    enterpriseName = "esp0xdeadbeef";
    siteName = "site-a";
    boxName = builtins.baseNameOf (builtins.toString ./.);
  };

  fabric = {
    intentPath = "${outPath}/library/100-fabric-routing/inputs/intent.nix";
    inventoryPath = ./inventory.nix;
  };

  system = if builtins ? currentSystem then builtins.currentSystem else "x86_64-linux";

  renderer = inputs.network-renderer-nixos.libBySystem.${system};

  vmBuild = renderer.vm.build {
    inherit (fabric) intentPath inventoryPath;
    boxName = identity.boxName;
    simulatedContainerDefaults = {
      autoStart = true;
      privateNetwork = true;
    };
  };
in
{
  imports = [
    "${modulesPath}/virtualisation/qemu-vm.nix"
    vmBuild.artifactModule
    inputs.sops-nix.nixosModules.sops
    ./mount-utils.nix
    ./sops.nix
  ];

  system.stateVersion = lib.mkForce "24.11";
  system.build.nixos-shell = config.system.build.vm;

  sops.defaultSopsFile = builtins.toFile "vm-empty-secrets.yaml" "{}";
  sops.validateSopsFiles = false;

  _module.args = {
    inherit identity fabric;
    renderedHostNetwork = {
      hostName = vmBuild.boxName;
      deploymentHostName = null;
      bridgeNameMap = { };
      bridges = { };
      netdevs = vmBuild.renderedNetdevs;
      networks = vmBuild.renderedNetworks;
      containers = vmBuild.renderedContainers;
      debug = {
        host = { };
        bridges = { };
        containers = builtins.attrNames vmBuild.renderedContainers;
      };
    };
  };

  environment.etc."network-renderer/network-renderer-nixos.json".text =
    builtins.toJSON {
      inherit identity fabric;
      host = { };
      bridges = { };
      containers = builtins.attrNames vmBuild.renderedContainers;
    };

  boot.loader.grub.enable = false;
  boot.isContainer = false;

  networking.hostName = vmBuild.boxName;
  networking.useNetworkd = true;
  networking.useDHCP = false;
  networking.useHostResolvConf = lib.mkForce false;
  networking.nftables.enable = false;
  networking.firewall.enable = false;

  systemd.network.enable = true;
  systemd.network.netdevs = vmBuild.renderedNetdevs;
  systemd.network.networks = vmBuild.renderedNetworks;

  services.resolved.enable = lib.mkForce false;

  virtualisation = {
    memorySize = 4096;
    cores = 4;
    graphics = false;
    forwardPorts = [
      {
        from = "host";
        host.port = 2222;
        guest.port = 22;
      }
    ];
    vmVariant = {
      virtualisation = {
        memorySize = 4096;
        cores = 4;
        graphics = false;
        forwardPorts = [
          {
            from = "host";
            host.port = 2222;
            guest.port = 22;
          }
        ];
      };
    };
  };

  users.mutableUsers = false;
  users.users.root = {
    initialHashedPassword = "";
    shell = pkgs.bashInteractive;
    ignoreShellProgramCheck = true;
  };

  programs.bash.enable = true;
  programs.zsh.enable = false;

  services.getty.autologinUser = "root";
  services.openssh.enable = true;

  environment.systemPackages = with pkgs; [
    bashInteractive
    git
    jq
    vim
    iproute2
    iputils
    tcpdump
    curl
  ];

  containers = vmBuild.renderedContainers;
}
