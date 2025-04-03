

This works (ignores .git):
```bash
vim /etc/nixos/flake.nix; nixos-rebuild switch --impure --flake path:/etc/nixos#l-werk
```

This also works:
```bash
$ cat ~/.config/nix/nix.conf
extra-experimental-features = nix-command flakes
access-tokens = github.com=ghp_......

# make it the same...
# Then update with:
nixos-rebuild switch --impure --flake "github:esp0xdeadbeef/nixos#$(hostname)"

```

