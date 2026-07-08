# s-mx01 mail private module

`mail-private.nix` is intentionally git-ignored because it contains the concrete
domain, DNS zone, mailbox names, and local secret mapping for the mail host. It
is not part of the flake source unless imported explicitly.

Use `NIXOS_MAILSERVER_PRIVATE_MODULE` when evaluating or building this host with
the private mail configuration:

```bash
NIXOS_MAILSERVER_PRIVATE_MODULE=/home/deadbeef/github/nixos/nixos/virtual-machine/nixos-anywhere/s-mx01/mail-private.nix \
  nix eval --impure .#nixosConfigurations.s-mx01.config.mailserver.accounts --apply builtins.attrNames --json
```

Without that environment variable, `mail.nix` does not import the private module
and the mail accounts/SOPS secrets are intentionally absent.

Mail password hashes are read through SOPS from `secrets/s-mx01.yaml`. Keep
public SOPS key names role-based or opaque, for example:

```yaml
mail:
  accounts:
    postmaster:
      hashed-password: ...
    mailbox-001:
      hashed-password: ...
    user-001:
      hashed-password: ...
```

Do not use personal names in public SOPS key names. The git-ignored private
module maps opaque secret IDs such as `user-001` to actual mailbox addresses.

`postmaster@<domain>` remains present as a standards/operations mailbox, but
has a temporary Sieve autoreply while it is being phased out. Normal mail goes
to `contact@<domain>`, which is its own functional mailbox. The personal
account gets server-side Dovecot ACL access to that mailbox through the shared
IMAP namespace. Do not attach a catch-all alias to the autoreply account;
unknown addresses should not generate automatic replies.

The contact mailbox has a server-side retention timer:

```bash
systemctl status <contact-retention-timer>.timer
```

It runs daily and expunges messages older than 365 days from
`contact@<domain>`.

## Web preview

`https://<domain>/` serves a public under-construction placeholder from the
Nix store. The real site/backend is not copied into git or the Nix store; nginx
proxies `https://<domain>/preview/` to the local Python backend running from
`/srv/<app>/app`.

The preview location uses Basic Auth through an htpasswd file generated from
SOPS:

```bash
sops --extract '["web"]["preview"]["password"]' --decrypt secrets/s-mx01.yaml
```

The public SOPS key names stay generic:

```yaml
web:
  preview:
    password: ...
    htpasswd: ...
```

Sync the current local draft manually when needed:

```bash
rsync -av --delete \
  --include='/start-page.sh' \
  --include='/backend/' \
  --include='/backend/contact_server.py' \
  --include='/webpagina/' \
  --include='/webpagina/index.html' \
  --include='/webpagina/*.svg' \
  --exclude='*' \
  /path/to/local/app/ root@<host>:/srv/<app>/app/

ssh root@<host> 'systemctl restart <preview-service>.service'
```
