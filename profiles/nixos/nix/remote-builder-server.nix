{ config
, lib
, ...
}:
let
  cfg = config.local.nix.remoteBuilderServer;
in
{
  options.local.nix.remoteBuilderServer = {
    enable = lib.mkEnableOption "serve this host as an ssh-ng remote builder to other hosts";

    emulateSystems = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Foreign systems to emulate via binfmt (e.g. `aarch64-linux`) so this x86_64 builder can build for them.";
    };

    cacheSigningKeyFile = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = ''
        Path to a binary-cache signing key (`name:base64-ed25519-secret`) used to
        sign every path this builder realises, so clients can `nix copy` those
        paths to themselves without disabling signature checking.

        This is the missing half of the remote-builder relationship: a builder
        that only realises paths leaves them unsigned, and a client whose
        `require-sigs` defaults to true (all of them) rejects the copy with
        "cannot add path ... because it lacks a signature by a trusted key".
        The key must PERSIST across boots -- regenerating it per boot would
        invalidate the signature of every path signed under the previous key.
        Its public half must be listed in the client's
        `local.nix.remoteBuilderClient.trustedBuilderKeys`.
      '';
    };

    clients = lib.mkOption {
      type = lib.types.attrsOf (
        lib.types.submodule {
          options = {
            # Public key the client uses to authenticate its dedicated
            # remote-builder identity to this host. This is NOT the client's
            # root login key; it is /root/.ssh/id_remote-builder.pub generated
            # once on each client (see profiles.nixos.nix.remote-builder-client).
            key = lib.mkOption {
              type = lib.types.str;
              description = "OpenSSH public key of the client's dedicated remote-builder identity.";
            };
          };
        }
      );
      default = { };
      description = "Client hosts (by name) allowed to offload builds to this builder.";
    };
  };

  config = lib.mkIf cfg.enable {
    # Sign realised paths with a persistent key so clients can copy them in
    # without relaxing `require-sigs`. The file is materialised (from SOPS) by
    # the host module; this only points nix at it.
    nix.settings.secret-key-files = lib.mkIf (cfg.cacheSigningKeyFile != null) [ cfg.cacheSigningKeyFile ];

    # Emulate foreign systems so this x86_64 host can build for them (e.g.
    # aarch64 laptops like l-portal). This also adds the emulated systems to
    # nix.settings.extra-platforms so the daemon accepts them.
    boot.binfmt.emulatedSystems = cfg.emulateSystems;

    # The official NixOS module for serving the store over SSH using the
    # modern `nix-daemon --stdio` (`ssh-ng`) protocol, matching the NixOS wiki's
    # recommended setup. The `nix-ssh` user it creates is a locked system user
    # whose sshd `Match` stanza permits only the store protocol, no shell/TTY/
    # agent/port forwarding.
    nix.sshServe = {
      enable = true;
      protocol = "ssh-ng";
      write = false;
      trusted = true; # adds `nix-ssh` to nix.settings.trusted-users
      keys = lib.mapAttrsToList (_host: c: c.key) cfg.clients;
    };
  };
}
