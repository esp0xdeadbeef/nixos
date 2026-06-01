{
  inputs,
  lib,
  pkgs,
  modelHost,
}:
let
  inherit (modelHost)
    builtHost
    fabric
    renderedHost
    renderedContainers
    ;
  runtimeInputMounts = import ./runtime-input-mounts.nix {
    inherit lib renderedContainers;
  };
  nebulaRendererCli =
    inputs.network-renderer-nebula.packages.${pkgs.stdenv.hostPlatform.system}.default;
  manualNebulaRuntimeSecretNames = modelHost.accessPrefixSecretNames ++ [
    "hetzner-public-ipv4"
    "hetzner-lighthouse-public-ipv4"
    "hetzner-public-ipv6"
    "nebula-profile-nixos-router-core-nebula-ca-crt"
    "nebula-profile-nixos-router-core-nebula-crt"
    "nebula-profile-nixos-router-core-nebula-key"
  ];
  manualNebulaRendererService = import ./manual-nebula-renderer-service.nix {
    inherit
      lib
      pkgs
      nebulaRendererCli
      renderedContainers
      ;
    runtimeSecretNames = manualNebulaRuntimeSecretNames;
  };
  hostileGuaOverrides = import ./hostile-gua-overrides.nix {
    inherit lib renderedContainers;
    hetznerAccessPrefixSecretNames = modelHost.accessPrefixSecretNames;
  };
  renderedHostNetwork = {
    hostName = renderedHost.hostName or "s-router-test";
    deploymentHostName = modelHost.resolvedDeploymentHostName;
    bridgeNameMap = renderedHost.bridgeNameMap or { };
    bridges = renderedHost.bridges or { };
    sites = renderedHost.sites or { };
    netdevs = renderedHost.netdevs or { };
    networks = renderedHost.networks or { };
    containers = renderedContainers;
  };
in
{
  imports = [
    (builtHost.artifactModule or { })
    modelHost.bootstrapModule
  ];

  system.stateVersion = lib.mkForce "25.11";
  environment.systemPackages = with pkgs; [
    bindfs
    gron
    ethtool
    iproute2
    iputils
    jq
    lsof
    mtr
    nftables
    nebula
    openssh
    procps
    python3
    ripgrep
    strace
    tcpdump
    tmux
    traceroute
    tshark
  ];

  _module.args = {
    identity.boxName = "s-router-test";
    inherit fabric renderedHostNetwork;
    hostContext = (builtHost.hostContext or { }) // {
      hostname = "s-router-test";
    };
    globalInventory = builtHost.globalInventory or { };
    intent = builtHost.fabricInputs or { };
    fabricInputs = builtHost.fabricInputs or { };
    compilerOut = builtHost.compilerOut or { };
    forwardingOut = builtHost.forwardingOut or { };
    controlPlaneOut = builtHost.controlPlaneOut or { };
    hetznerAccessNodeNames = modelHost.accessNodeNames;
    hetznerAccessPrefixSecretNames = modelHost.accessPrefixSecretNames;
  };

  s88.sRouterTestSops.hetznerAccessPrefixSecretNames = modelHost.accessPrefixSecretNames;

  environment.etc."s-router-test/hetzner-access-ipv6-nodes".text =
    lib.concatLines modelHost.accessNodeNames;

  networking.useNetworkd = true;
  systemd.network.enable = true;
  systemd.network.wait-online.enable = false;
  networking.useDHCP = false;
  networking.useHostResolvConf = lib.mkForce false;
  services.resolved.enable = true;
  systemd.network.netdevs = renderedHost.netdevs or { };
  systemd.network.networks = lib.recursiveUpdate (renderedHost.networks or { }) {
    "30-vlan2".networkConfig.DHCP = "ipv4";
  };

  containers = lib.foldl' lib.recursiveUpdate renderedContainers [
    runtimeInputMounts
    manualNebulaRendererService
    hostileGuaOverrides
    modelHost.overlayContainers
  ];
  systemd.tmpfiles.rules = [
    "d /persist/nebula-runtime 0700 root root -"
    "d /persist/nebula-runtime/profiles 0700 root root -"
  ];
  users.users.root.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAqEmMbztRhj2zE1dXf5Z+Ow7mXXXE6sNAG4/hrIOrmD deadbeef@codex-jail"
  ];
  users.users.deadbeef.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAqEmMbztRhj2zE1dXf5Z+Ow7mXXXE6sNAG4/hrIOrmD deadbeef@codex-jail"
  ];
}
