

# generate a key with:

## impermanence (while setup)

```bash
[ -d /mnt ] || echo "mount /mnt first"
[ -f /mnt/persist/$HOME/.ssh/id_ed25519 ] || ( mkdir /mnt/persist/$HOME/.ssh ; ssh-keygen -t ed25519 -N "" -f /mnt/persist/$HOME/.ssh/id_ed25519 -q)
mkdir -p /mnt/persist/$HOME/.config/sops/age
nix-shell -p ssh-to-age --run 'bash -c "ssh-to-age -private-key -i /mnt/persist/$HOME/.ssh/id_ed25519 > /mnt/persist/$HOME/.config/sops/age/keys.txt"'

key=$(nix-shell -p age --run "age-keygen -y /mnt/persist/$HOME/.config/sops/age/keys.txt")
echo -e "public key:\n$key"
```


## impermanence (after setup)

```bash
[ -f /persist/$HOME/.ssh/id_ed25519 ] || ssh-keygen -t ed25519 -N "" -f $HOME/.ssh/id_ed25519 -q
mkdir -p $HOME/.config/sops/age
nix-shell -p ssh-to-age --run 'bash -c "ssh-to-age -private-key -i $HOME/.ssh/id_ed25519 > $HOME/.config/sops/age/keys.txt"'

( 
    cd /persist
    mkdir -p .$HOME/.config/sops/age && cp $HOME/.config/sops/age/keys.txt /persist/$HOME/.config/sops/age/keys.txt
    mkdir -p .$HOME/.ssh/ && cp $HOME/.ssh/id_ed25519 /persist/$HOME/.ssh/id_ed25519
)
key=$(nix-shell -p age --run 'age-keygen -y ~/.config/sops/age/keys.txt')
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

## Bootstrap an age identity for a nixos-shell VM

A nixos-shell VM mounts its `/persist` directory from
`/persist/vm-persists/<vm-name>` on the VM host. The identity can therefore be
created before the first VM boot. This avoids a bootstrap generation in which
SOPS cannot decrypt yet.

The following command creates the `s-mail-classifier` identity on its VM host.
It refuses to overwrite an existing key, applies restrictive directory and file
permissions, keeps the private identity on the host, and prints only the public
recipient:

```bash
ssh s-tau '
  set -euo pipefail

  key_dir=/persist/vm-persists/s-mail-classifier/root/.config/sops/age
  key_file=$key_dir/keys.txt

  if sudo test -e "$key_file"; then
    echo "refusing to overwrite existing classifier identity" >&2
    exit 1
  fi

  sudo install -d -o root -g root -m 0700 "$key_dir"
  sudo sh -c "umask 077; age-keygen -o \"$key_file\" >/dev/null 2>&1"
  sudo test "$(sudo stat -c %a "$key_file")" = 600
  sudo age-keygen -y "$key_file"
'
```

Add the printed public recipient to `.sops.yaml`, include its anchor only in
the required creation rules, and update the affected encrypted files:

```bash
for secret_file in secrets/mailbox-*.yaml secrets/mail-account-*.yaml; do
  sops updatekeys --yes "$secret_file"
done
```

Verify the new host identity through a pipe. This decrypts into `/dev/null`; it
does not print plaintext or create a decrypted temporary file:

```bash
ssh s-tau '
  set -euo pipefail
  SOPS_AGE_KEY_FILE=/persist/vm-persists/s-mail-classifier/root/.config/sops/age/keys.txt
  export SOPS_AGE_KEY_FILE
  sudo --preserve-env=SOPS_AGE_KEY_FILE \
    sops --decrypt --input-type yaml --output-type yaml /dev/stdin >/dev/null
' <secrets/mailbox-003.yaml
```
