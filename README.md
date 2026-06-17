TLDR this repo was never ment to be public, but someone wanted it so i published it.

# this nixos config is based on the configuration of Misterio77's config

https://github.com/Misterio77/nix-starter-configs


# Import convention

Hosts should import explicit profiles and host-local modules by intent. Avoid
regenerating `imports` from every `.nix` file in a directory.

Temporary or experimental modules can stay in scoped optional directories. Prefix
their file or directory name with `build_` or `disabled_` to keep them present in
the tree but excluded from dynamic optional imports.
