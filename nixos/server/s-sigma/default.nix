{ lib
, profiles
, relativeRepo
, config
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
    profiles.nixos.server.weekly-auto-upgrade
    profiles.nixos.llm-clients.cache
    profiles.nixos.network.nebula-mesh
    profiles.nixos.nix.remote-builder-server

    ./libvirt.nix
    ./nixos-shell-servers
    ./hardware
    ./connect-nas
    ./github-token.nix
  ];

  # Binary-cache signing key for this builder (see cacheSigningKeyFile below).
  # Persisted in SOPS, NOT generated per boot: regenerating it would invalidate
  # the signature of every path signed under the previous key.
  sops.secrets.nix-cache-signing-key = {
    sopsFile = relativeRepo.sourcePath "secrets/s-sigma-root.yaml";
    owner = "root";
    group = "root";
    mode = "0400";
  };

  local.nix.remoteBuilderServer = {
    enable = true;
    # Sign every path realised here so clients can copy a builder output to
    # themselves with `require-sigs` still on (the default). Without this a
    # `nixos-rebuild --target-host` to a client fails with "cannot add path ...
    # because it lacks a signature by a trusted key": the client only trusts
    # cache.nixos.org-1, and a locally-built path carries no signature at all.
    # The public half goes in each client's
    # local.nix.remoteBuilderClient.trustedBuilderKeys.
    cacheSigningKeyFile = config.sops.secrets.nix-cache-signing-key.path;
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
