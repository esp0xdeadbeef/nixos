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
secrets/mailbox-*.yaml
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
web/redirects/env
```

Mail config is split into two generic secret classes. Filenames are opaque ids;
do not put domains, people, providers, or brand names in them:

```text
secrets/mailbox-001.yaml
secrets/mailbox-002.yaml
secrets/mail-account-001.yaml
secrets/mail-account-002.yaml
```

`mailbox-*.yaml` describes a hosted mail domain/set. `mail-account-*.yaml`
describes one account credential/profile. Hosted accounts are linked by generic
ids inside the encrypted mailbox set:

```text
MAILBOX_DOMAIN=example.com
MAILBOX_MAIL_HOST=mail.example.com
MAILBOX_ACCOUNTS=mail-account-001 mail-account-002
MAILBOX_DEFAULT_ACCOUNT=mail-account-001
```

The account secret stores account-local data:

```text
MAIL_ACCOUNT_LOCALPART=alice
MAIL_ACCOUNT_PASSWORD=change-me
MAIL_ACCOUNT_ALIASES=contact support
MAIL_ACCOUNT_CLIENT=true
MAIL_ACCOUNT_SERVER=true
MAIL_ACCOUNT_LABEL=Example Mail
MAIL_ACCOUNT_DISPLAY_NAME=Alice Example
MAIL_ACCOUNT_RETENTION_DAYS=30
```

Create or edit these secrets from a workstation checkout that already has SOPS
access. Do not run this on the mail server; the server only consumes encrypted
files during activation.

To create another hosted mailbox set:

```bash
mailbox_set=mailbox-003
target="secrets/${mailbox_set}.yaml"
tmp="$(mktemp)"
encrypted="$(mktemp)"
trap 'rm -f "$tmp" "$encrypted"' EXIT

test ! -e "$target"

cat > "$tmp" <<'YAML'
mailbox:
    env: |
        MAILBOX_DOMAIN=example.com
        MAILBOX_MAIL_HOST=mail.example.com
        MAILBOX_ACCOUNTS=mail-account-003 mail-account-004
YAML

sops --encrypt --filename-override "$target" "$tmp" > "$encrypted"
install -m 0600 "$encrypted" "$target"
```

To create a hosted account secret:

```bash
account=mail-account-003
target="secrets/${account}.yaml"
tmp="$(mktemp)"
encrypted="$(mktemp)"
trap 'rm -f "$tmp" "$encrypted"' EXIT

test ! -e "$target"

cat > "$tmp" <<'YAML'
mail:
    account:
        env: |
            MAIL_ACCOUNT_LOCALPART=alice
            MAIL_ACCOUNT_PASSWORD=change-me
            MAIL_ACCOUNT_ALIASES=contact
            MAIL_ACCOUNT_CLIENT=true
            MAIL_ACCOUNT_SERVER=true
            MAIL_ACCOUNT_LABEL=Example Mail
            MAIL_ACCOUNT_DISPLAY_NAME=Alice Example
            MAIL_ACCOUNT_RETENTION_DAYS=30
YAML

sops --encrypt --filename-override "$target" "$tmp" > "$encrypted"
install -m 0600 "$encrypted" "$target"
```

To create a client-only external account, such as Gmail in Geary/aerc, do not
add it to any hosted `MAILBOX_ACCOUNTS` list and set `MAIL_ACCOUNT_SERVER=false`:

```bash
account=mail-account-900
target="secrets/${account}.yaml"
tmp="$(mktemp)"
encrypted="$(mktemp)"
trap 'rm -f "$tmp" "$encrypted"' EXIT

test ! -e "$target"

cat > "$tmp" <<'YAML'
mail:
    account:
        env: |
            MAIL_ACCOUNT_ADDRESS=alice@example.net
            MAIL_ACCOUNT_USERNAME=alice@example.net
            MAIL_ACCOUNT_PASSWORD=app-password
            MAIL_ACCOUNT_CLIENT=true
            MAIL_ACCOUNT_SERVER=false
            MAIL_ACCOUNT_LABEL=Example External
            MAIL_ACCOUNT_DISPLAY_NAME=Alice Example
            MAIL_ACCOUNT_SOURCE=imaps://alice%40example.net@imap.example.net
            MAIL_ACCOUNT_OUTGOING=smtps://alice%40example.net@smtp.example.net
YAML

sops --encrypt --filename-override "$target" "$tmp" > "$encrypted"
install -m 0600 "$encrypted" "$target"
```

To edit existing secrets:

```bash
sops edit secrets/mailbox-003.yaml
sops edit secrets/mail-account-003.yaml
```

To check that secrets decrypt without printing them:

```bash
sops -d --extract '["mailbox"]["env"]' secrets/mailbox-003.yaml >/dev/null
sops -d --extract '["mail"]["account"]["env"]' secrets/mail-account-003.yaml >/dev/null
```

The server discovers hosted `mailbox-*.yaml` secrets, but it only receives
`mail-account-*.yaml` secrets listed in its `local.mail.mailboxSets.accountNames`
whitelist. Client-only external accounts stay off that server list. Home Manager
mail clients discover all account secrets and include external accounts where
`MAIL_ACCOUNT_CLIENT=true` and `MAIL_ACCOUNT_SERVER=false`.

If `SOURCE` and `OUTGOING` are omitted for a hosted client account, the mail
clients derive them from `MAILBOX_MAIL_HOST`. Use explicit values for external
providers or when a provider needs different IMAP and SMTP hosts.

Client account order is default-aware. For hosted accounts, set
`MAILBOX_DEFAULT_ACCOUNT=mail-account-001` or
`MAILBOX_DEFAULT_ADDRESS=alice@example.com` in exactly one mailbox set. For a
client-only external account, set `MAIL_ACCOUNT_DEFAULT=true`. aerc and Geary
render default accounts first and then render the remaining client accounts in
the normal discovered order.

Retention is account-driven. Set `MAIL_ACCOUNT_RETENTION_DAYS=30` on
administrative or shared mailboxes such as contact, no-reply, and postmaster
accounts. The server-side retention timer caps account-provided values at
`local.mail.mailboxSets.retention.maxDays`, which defaults to 30 days.
By default the timer applies to all Dovecot mailboxes for that account. Set
`MAIL_ACCOUNT_RETENTION_MAILBOXES="INBOX Junk"` when a specific account needs a
smaller mailbox list.

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
WEB_SITE_NAME=Example
WEB_SITE_DOMAIN=example.com
WEB_CONTACT_MAILBOX_SET=mailbox-001
WEB_CONTACT_ACCOUNT=mail-account-003
WEB_FORM_SMTP_AUTH_FROM_ACCOUNT=false
SMTP_HOST=...
SMTP_PORT=...
SMTP_STARTTLS=...
CONTACT_FROM=...
CONTACT_SUBJECT=...
TOKEN_SECRET=...
```

`WEB_CONTACT_ACCOUNT` links the webpage to one generic
`secrets/mail-account-*.yaml` id. `WEB_CONTACT_MAILBOX_SET` selects the hosted
mailbox set/domain when the same account id appears in more than one
`MAILBOX_ACCOUNTS` set. The webpage environment renderer derives
`WEB_CONTACT_EMAIL`, `CONTACT_FROM`, `SMTP_HOST`, `SMTP_PORT`, and
`WEB_SITE_URL` from the same mailbox/account secrets that configure mail.

Use `WEB_PUBLIC_CONTACT_ACCOUNT` plus `WEB_PUBLIC_CONTACT_MAILBOX_SET` and
`WEB_FORM_ACCOUNT` plus `WEB_FORM_MAILBOX_SET` when the public contact address
and the form sender should be different account ids. Explicit
`WEB_CONTACT_EMAIL`, `CONTACT_FROM`, `SMTP_HOST`, or `SMTP_PORT` values in
`web/contact/env` still override derived values.

Keep public site text and URLs in `web/contact/env` with generic variable names,
not in Nix modules or static HTML. Useful optional public fields are:

```text
WEB_SITE_TITLE=Example | Offensive security vanuit Nederland
WEB_SITE_DESCRIPTION=Example levert securityonderzoek.
WEB_CONTACT_PHONE=+31 00 000 0000
WEB_CONTACT_PHONE_HREF=tel:+31000000000
WEB_LEGAL_ENTITY=Example, eenmanszaak in oprichting
WEB_LEGAL_UPDATED=1 januari 2026
WEB_FOOTER_TAGLINE=Offensive security vanuit Nederland.
```

The renderer also publishes a `security.txt` file from the same runtime env.
By default it uses `WEB_CONTACT_EMAIL` and `WEB_SITE_URL`; override these only
when the disclosure contact or canonical URL must differ:

```text
WEB_SECURITY_CONTACT_EMAIL=security@example.com
WEB_SECURITY_SITE_URL=https://example.com
WEB_SECURITY_CANONICAL_URL=https://example.com/.well-known/security.txt
WEB_SECURITY_EXPIRES_AFTER=+180 days
```

Web redirects are configured from a separate SOPS env secret:

```text
WEB_REDIRECT_DOMAINS=example.net www.example.net
WEB_REDIRECT_TARGET_URL=https://example.com
WEB_REDIRECT_STATUS=301
```

To add another web-only redirect domain, keep the concrete domain in
`web/redirects/env`, point DNS A/AAAA records at this host, and include the same
names in `MAIL_TLS_DOMAINS` so the shared runtime certificate covers HTTPS. The
public Nix module only enables `profiles.nixos.web.redirect-domains`; redirect
domain names and targets should not be committed outside encrypted SOPS data.

Shared mailbox access is ACL-driven. Non-client mail accounts are automatically
shared only to client mail accounts in the same hosted mailbox set/domain.
`MAIL_SHARED_*` entries may add explicit same-domain ACLs from SOPS, but they
are not needed for normal account-to-client sharing. The
`<host>-mail-shared-subscriptions` unit refreshes the Dovecot sharing map,
subscribes users to explicitly managed same-domain shared mailbox folders, and
rebuilds the Postfix sender-login map for ACL entries with the `post` right. On
`s-gamma` this unit is started automatically by Dovecot on boot and restart, so
mailbox subscriptions are projected when the mail runtime is initialized without
running a periodic refresh timer.
Set `profiles.mail.server.sharedNamespaceIncludeDomain = true` for deployments
that need disambiguation across multiple shared domain listings, yielding
`s/example.com/contact`. Set `profiles.mail.server.sharedExplicitInbox = true`
when clients should see the shared inbox as `s/example.com/contact/INBOX`
instead of `s/example.com/contact`. Set
`profiles.mail.server.sharedInheritInboxAcl = true` when Dovecot should use the
shared INBOX ACL as the default ACL for the owner's other mailboxes, so clients
can see the shared folder tree without declaring a fixed folder list in Nix.

Mail certificate hostnames are SOPS-driven. Set `MAIL_TLS_DOMAINS` in the mail
server env secret when the mail certificate needs more names than `MAIL_FQDN`.
`MAIL_ACME_EMAIL` is optional; it defaults to `postmaster@$MAIL_FQDN`.

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

Preview-only website tooling must be controlled from encrypted runtime env, not
from public Nix. For temporary logo inspection and SVG generation, keep these in
`web/contact/env`:

```bash
WEB_LOGO_INSPECTION_ENABLED=true
WEB_PREVIEW_TOOLS_EXPIRES_ON=2026-08-01
WEB_LOGO_GENERATION_MODEL=deepseek-v4-pro
WEB_LOGO_GENERATION_API_KEY=...
```

The website backend disables the preview route on and after the expiry date. The
DeepSeek key must stay in SOPS only. Nginx creates explicit
`/__preview/logo-inspectie` locations for the host in `WEB_SITE_DOMAIN`; the same
paths return `404` on every generated redirect, `www`, and mail host. The backend
also checks the request host, so a redirect-domain request cannot reach the tool
through a different proxy configuration.

Runtime-generated SVGs are exposed below
`webpagina/generated-logo-directions/`. Full DeepSeek request/response logs are
available to the backend in `var/logo-generation-logs/`; they include the prompt
and optional reference SVG text, but never the API key. Private per-SVG DeepSeek
discussions and write-through review notes are available in
`var/logo-discussions/`.
Discussion files are keyed by the SVG content hash, and their full thread is
included as backend-owned context in later generations from that reference. The
runtime manifest derives the selectable apex-domain list from encrypted web
environment values; concrete domains remain outside this repository. Periodic
The actual data lives outside the rsync target under `/persist/srv/www/state/`;
the sync migrates legacy in-app data and recreates symlinks after each update.
Consequently `rsync --delete`, periodic syncs, and reboots do not remove these
runtime files.

The inspection UI itself is built by the webpage repository's
`logo-preview-assets` flake package. The sync service verifies the pinned npm
dependency hash, builds the Vue bundle, and replaces
`preview/logo-inspectie/dist` with a symlink to the resulting immutable
`/nix/store/*-logo-inspectie-assets-*` path. A failed frontend build leaves the
existing runtime application untouched. Check the deployed provenance with:

```bash
readlink /persist/srv/www/app/preview/logo-inspectie/dist
readlink /persist/srv/www/app/webpagina/generated-logo-directions
readlink /persist/srv/www/app/var/logo-discussions
```

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
