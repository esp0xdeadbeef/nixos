

This works (ignores .git):
```bash
vim /etc/nixos/flake.nix; nixos-rebuild switch --impure --flake path:/etc/nixos#l-werk
```
