

# generate a key with:

## impermanence

```bash
[ -f /persist/$HOME/.ssh/id_ed25519 ] || ssh-keygen -t ed25519 -N "" -f $HOME/.ssh/id_ed25519 -q
mkdir -p $HOME/.config/sops/age
nix-shell -p ssh-to-age --run 'bash -c "ssh-to-age -private-key -i $HOME/.ssh/id_ed25519 > $HOME/.config/sops/age/keys.txt"'

( 
    cd /persist
    mkdir -p .$HOME/.config/sops/age && cp $HOME/.config/sops/age/keys.txt /persist/$HOME/.config/sops/age/keys.txt
    mkdir -p .$HOME/.ssh/ && cp $HOME/.ssh/id_ed25519 /persist/$HOME/.ssh/id_ed25519
)
key=$(age-keygen -y ~/.config/sops/age/keys.txt)
echo -e "public key:\n$key"

```


## "normal"
```bash
[ -f /$HOME/.ssh/id_ed25519 ] || ssh-keygen -t ed25519 -N "" -f $HOME/.ssh/id_ed25519 -q
mkdir -p $HOME/.config/sops/age
nix-shell -p ssh-to-age --run 'bash -c "ssh-to-age -private-key -i $HOME/.ssh/id_ed25519 > $HOME/.config/sops/age/keys.txt"'
```

# get pub key:

```bash
age-keygen -y ~/.config/sops/age/keys.txt
```

# afterwards update the keys of the file:

```bash
sops updatekeys ./general-test.yaml # example.
```


