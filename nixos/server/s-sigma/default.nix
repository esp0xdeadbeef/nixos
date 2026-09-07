{ lib
, profiles
, relativeRepo
, ...
}:
let
  # Public keys of the dedicated remote-builder identities for the hosts allowed
  # to offload builds to this builder. Each client generates this once with
  # `sudo ssh-keygen -t ed25519 -N "" -f /root/.ssh/id_remote-builder` and
  # commits the resulting .pub here (see profiles.nixos.nix.remote-builder-client).
  remoteBuilderKeyFor = host: lib.fileContents (relativeRepo.sourcePath "ssh-keys/deadbeef/remote-builder/${host}.pub");
in
{
  imports = [
    profiles.nixos.server.dell-vm-host
    profiles.nixos.users.sudo-nopasswd
    profiles.nixos.server.no-sleep
    profiles.nixos.llm-clients.cache
    profiles.nixos.network.nebula-mesh
    profiles.nixos.nix.remote-builder-server

    ./libvirt.nix
    ./nixos-shell-servers
    ./hardware
    ./connect-nas
    ./github-token.nix
  ];

  local.nix.remoteBuilderServer = {
    enable = true;
    emulateSystems = [ "aarch64-linux" ];
    clients = {
      # TODO: commit l-esp's id_remote-builder.pub when it is back online.
      l-envil.key = remoteBuilderKeyFor "l-envil";
      l-portal.key = remoteBuilderKeyFor "l-portal";
      s-gamma.key = remoteBuilderKeyFor "s-gamma";
      # l-esp.key = remoteBuilderKeyFor "l-esp";
    };
  };

  system.stateVersion = "25.11";
}
