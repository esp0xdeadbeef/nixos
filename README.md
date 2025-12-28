TLDR this repo was never ment to be public, but someone wanted it so i published it.

# this nixos config is based on the configuration of Misterio77's config

https://github.com/Misterio77/nix-starter-configs


# Todo

- [ ] Revisit all hosts with the ugly importer, remove build_ files.
```bash
(echo '{pkgs, ...}: {imports = ['; find . -name '*.nix' -not -name 'default.nix' ; echo '];}') | nixfmt | tee ./default.nix
```

- [ ] Make hosts usb bootable (check git history on this file)


