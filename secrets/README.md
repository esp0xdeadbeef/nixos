

# generate a key with:

```bash
mkdir -p ~/.config/sops/age
nix-shell -p ssh-to-age --run "ssh-to-age -private-key -i ~/.ssh/id_ed25519 > ~/.config/sops/age/keys.txt"
```

# get pub key:

```bash
age-keygen -y ~/.config/sops/age/keys.txt
```

# afterwards update the keys of the file:

```bash
sops updatekeys ./general-test.yaml # example.
```


