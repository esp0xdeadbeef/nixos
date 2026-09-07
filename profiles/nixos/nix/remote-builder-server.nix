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
