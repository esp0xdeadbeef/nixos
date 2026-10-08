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
  remoteBuilderKeyFor = host: lib.fileContents (relativeRepo.sourceModule "ssh-keys/deadbeef/remote-builder/${host}.pub");
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
      l-envil.key = remoteBuilderKeyFor "l-envil";
      l-esp.key = remoteBuilderKeyFor "l-esp";
      l-portal.key = remoteBuilderKeyFor "l-portal";
      s-gamma.key = remoteBuilderKeyFor "s-gamma";
      # s-nodus (BPI-R4 Pro 4E): 4-core aarch64 board with 4 GiB of RAM.  Its
      # large closures -- the QEMU-inclusive one especially -- cannot be built
      # on the board, so it offloads here.  Small config derivations still
      # build locally (nix.settings.max-jobs = 2) so the board can bootstrap
      # when no builder is reachable.
      s-nodus.key = remoteBuilderKeyFor "s-nodus";
      # Peer servers rebuild each other, so each trusts the other's remote-builder identity.
      s-tau.key = remoteBuilderKeyFor "s-tau";
    };
  };

  system.stateVersion = "25.11";
}
