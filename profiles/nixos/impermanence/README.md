# Shared impermanence profile

Import `profiles.nixos.impermanence.default` from hosts that use `/persist`.
The profile centralizes the standard btrfs root rotation, SSH host key
persistence, system state, and `deadbeef` home state.

`/root` is still persisted as a whole directory for compatibility with the
current hosts and is forced to mode `0700`. This keeps SOPS age keys and root
SSH state stable without exposing root's home as a default `0755` persist bind.
Do not add overlapping `users.root` mounts unless `/root` is first split into
explicit subpaths.

Common host overrides:

```nix
local.impermanence = {
  enable = true;
  rootMapperName = "crypted";
  extraSystemDirectories = [ "/etc/nebula" ];
};
```

For hosts where the LUKS mapper is named `root`:

```nix
local.impermanence.rootMapperName = "root";
```

TPM, Clevis/Tang, and other unlock-specific settings belong in the host's boot
or disk-unlock modules, not in this impermanence profile.
