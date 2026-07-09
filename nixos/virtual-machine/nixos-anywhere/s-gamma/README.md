# s-gamma runtime configuration

This host keeps concrete mail domains, mailbox names, personal names, public
hostnames, address literals, DNS zones, TLS material, and preview credentials
out of the public Nix module. Those values belong in SOPS-managed runtime files
or in provider control panels.

See `contact-intake.md` for the planned public contact form, SMS reachability
verification, and intake portal flow.

## SOPS inputs

`mail.nix` only references generic secret keys and runtime file paths. Boot-time
helpers render service-specific files from:

```text
secrets/s-gamma-runtime.yaml
secrets/mail-client.yaml
```

`secrets/s-gamma-runtime.yaml` owns server-side runtime material:

```text
github/webpage_pat
network/address_env
mail/server/env
mail/tls/fullchain_pem
mail/tls/key_pem
dns/named_conf
dns/zone_001
web/nginx/http_conf
web/preview/username
web/preview/password
```

`secrets/mail-client.yaml` owns shared client-side mail login material:

```text
mail_client/shared/password
```

The mail env secret is a shell env file using generic account IDs:

```text
MAIL_FQDN=...
MAIL_DOMAIN=...
MAIL_DOMAINS=...
MAIL_ACCOUNTS=ACCOUNT_001 ACCOUNT_002
MAIL_ACCOUNT_001_ADDRESS=...
MAIL_ACCOUNT_001_ALIASES=...
MAIL_ACCOUNT_002_ADDRESS=...
MAIL_ACCOUNT_002_ALIASES=...
```

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
and preview auth config there instead of in public Nix.

## Web runtime

The real webpage source is pinned by `flake.lock` through the `webpage` input.
At activation/runtime, `s-gamma-webpage-sync.service` copies that pinned source
to:

```text
/persist/srv/kvk/app
```

`s-gamma-webpage.service` runs the backend from that directory on localhost.
Nginx reverse proxies to it and owns the preview access gate. To temporarily
test an override, stop the service and run the app manually from the runtime
dir:

```bash
systemctl stop s-gamma-webpage.service
cd /persist/srv/kvk/app
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
systemctl status s-gamma-mail-runtime-config.service
systemctl status postfix.service dovecot.service bind.service nginx.service
systemctl status s-gamma-webpage-sync.service s-gamma-webpage.service
```

Cutover checklist:

- keep concrete DNS and address data in SOPS or provider panels
- verify authoritative DNS, reverse DNS, and mail ports before MX cutover
- publish DS data only through the registrar or registry path
- verify DNSSEC with external resolvers after the parent DS is visible
- keep web preview gated until the public page may be indexed
