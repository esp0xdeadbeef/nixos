# s-gamma runtime configuration

This host keeps concrete mail domains, mailbox names, personal names, public
hostnames, address literals, DNS zones, TLS material, and preview credentials
out of the public Nix module. Those values belong in SOPS-managed runtime files
or in provider control panels.

See `contact-intake.md` for the planned public contact form, SMS reachability
verification, and intake portal flow.

## SOPS inputs

The host modules only reference generic secret keys and runtime file paths.
Boot-time helpers render service-specific files from:

```text
secrets/s-gamma-runtime.yaml
secrets/mail-account-*.yaml
```

`secrets/s-gamma-runtime.yaml` owns server-side runtime material:

```text
network/address_env
mail/server/env
dns/knot_conf
dns/zone_001
dns/zone_002
web/contact/env
web/nginx/http_conf
web/preview/username
web/preview/password
```

Each mailbox has its own SOPS file. This keeps mailbox credentials isolated,
so adding or delegating a mailbox does not require sharing one central mail
client secret:

```text
secrets/mail-account-postmaster.yaml
secrets/mail-account-user-001.yaml
secrets/mail-account-mailbox-001.yaml
secrets/mail-account-no-reply.yaml
```

Mailbox account files use this shape:

```text
mail/accounts/<account>/username
mail/accounts/<account>/password
mail/accounts/<account>/aliases
mail/accounts/<account>/label
mail/accounts/<account>/from
mail/accounts/<account>/source
mail/accounts/<account>/outgoing
```

Only client-used accounts need `label`, `from`, `source`, and `outgoing`.

The mail env secret is a shell env file using generic account IDs and account
secret pointers:

```text
MAIL_FQDN=...
MAIL_DOMAIN=...
MAIL_DOMAINS=...
MAIL_TLS_DOMAINS=...
MAIL_ACME_EMAIL=...
MAIL_ACCOUNTS=ACCOUNT_001 ACCOUNT_002
MAIL_ACCOUNT_001_ACCOUNT_SECRET=mail/accounts/postmaster
MAIL_ACCOUNT_002_ACCOUNT_SECRET=mail/accounts/user-001
```

The public mapping between generic runtime IDs and account secrets lives in
`profiles/mail/accounts.nix`; the concrete usernames, aliases, passwords, and
client properties stay in the per-account SOPS files.

The network address env secret is a shell env file for provider addresses:

```text
PUBLIC_IPV4=...
WEB_IPV4=...
WEB_IPV6=...
WEB_IPV6_PREFIX_LENGTH=...
NETWORK_INTERFACE=...
```

DNS and nginx runtime config are included from SOPS-managed files. Put zone
names, record targets, address literals, `server_name` values, backend targets,
and preview auth config there instead of in public Nix. Add another
`dns/zone_NNN` secret when the authoritative server must serve an additional
zone, and include it from the SOPS-managed Knot config.

The web contact env secret is a shell env file for the contact form backend:

```text
SMTP_HOST=...
SMTP_PORT=...
SMTP_STARTTLS=...
RECIPIENT_EMAIL=...
CONTACT_FROM=...
CONTACT_SUBJECT=...
TOKEN_SECRET=...
```

Shared mailbox access is ACL-driven. Non-client mail accounts are automatically
shared to client mail accounts. `MAIL_SHARED_*` entries may add explicit ACLs
from SOPS, but they are not needed for normal account-to-client sharing. The
`<host>-mail-shared-subscriptions` unit refreshes the Dovecot sharing map,
subscribes users to visible shared mailboxes, and rebuilds the Postfix
sender-login map for ACL entries with the `post` right.

Mail certificate hostnames are SOPS-driven. Set `MAIL_TLS_DOMAINS` in the mail
server env secret when the mail certificate needs more names than `MAIL_FQDN`.
`MAIL_ACME_EMAIL` is optional; it defaults to `postmaster@$MAIL_DOMAIN`.

## Module layout

- `network.nix`: provider address SOPS env and runtime address setup
- `cert.nix`: ACME certificate renewal and runtime certificate paths
- `dns.nix`: Knot authoritative DNS, zone secrets, DNS firewall ports
- `mail.nix`: Postfix, Dovecot, Rspamd, mail secrets, mail firewall ports
- `web.nix`: runtime webpage sync, contact backend, nginx, web firewall ports

## Web runtime

The real webpage source is private and is not fetched by Nix evaluation or put in
the Nix store. `<host>-webpage-sync.service` clones or updates the `main` branch
of `esp0xdeadbeef/www` at runtime using `/run/secrets/gh-token`, then copies the
working tree to:

```text
/persist/srv/www/app
```

The source checkout itself lives at `/persist/srv/www/source`. This avoids
private GitHub tarball failures during `nixos-rebuild`, and avoids storing the
webpage source or GitHub token in `/nix/store`.

After committing and pushing webpage changes, restart the sync and app units, or
let the `<host>-webpage-sync.timer` refresh the checkout. The sync service keeps
the existing runtime app when GitHub is temporarily unavailable during boot.
For an immediate refresh:

```bash
systemctl start "$(hostname)-webpage-sync.service"
```

`<host>-webpage.service` runs the backend from `/persist/srv/www/app` on
localhost. Nginx reverse proxies to it and owns the preview access gate. To
temporarily test an override, stop the service and run the app manually from the
runtime dir:

```bash
systemctl stop "$(hostname)-webpage.service"
cd /persist/srv/www/app
python ./run-server.py
```

Expected live behavior during migration:

```text
http://<web-host>/   -> HTTPS redirect without page content
https://<web-host>/  -> gated without preview credentials
https://<web-host>/  -> page content with preview credentials
```

## Operational checks

Evaluation should not require decrypted secrets:

```bash
nix eval --impure .#nixosConfigurations.s-gamma.config.networking.hostName
nix eval --impure .#nixosConfigurations.s-gamma.config.system.build.toplevel.drvPath
```

Runtime service checks on the host:

```bash
systemctl status postfix.service dovecot.service knot.service nginx.service
systemctl status "$(hostname)-cert-mail.service"
systemctl status "$(hostname)-mail-runtime-config.service"
systemctl status "$(hostname)-webpage-sync.service" "$(hostname)-webpage.service"
```

Cutover checklist:

- keep concrete DNS and address data in SOPS or provider panels
- verify authoritative DNS, reverse DNS, and mail ports before MX cutover
- publish DS data only through the registrar or registry path
- verify DNSSEC with external resolvers after the parent DS is visible
- keep web preview gated until the public page may be indexed
