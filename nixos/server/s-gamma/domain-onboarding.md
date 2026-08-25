# Domain onboarding runbook

Use this when adding another hosted web/mail domain to `s-gamma` and the local
mail clients. Keep concrete domain names, redirect targets, address literals,
mailbox labels, and account names out of plaintext Nix files. Put those values
in Theory7 or encrypted SOPS data.

## Fast path

For the common case where the registrar account already contains the new
domains, do this in order:

1. In Theory7 `My Domains`, switch the list length to `All` and identify every
   newly added active domain.
2. For each domain, replace parking DNS with the record set below, including
   uppercase TLSA input.
3. Open the domain DNSSEC page and click `DNSSEC inschakelen`.
4. Create one encrypted `secrets/mailbox-NNN.yaml` per hosted domain and add
   only the generic ids to `profiles/mail/inventory.nix`.
5. Update encrypted redirect and certificate domain lists in
   `secrets/s-gamma-runtime.yaml` when the new domain must serve web redirects
   or be covered by the shared certificate.
6. Mark any new SOPS files with `git add -N` before evaluating flakes.
7. Activate local Home Manager for aerc/Geary, then deploy `s-gamma`.
8. Verify DNS, mail maps, and certificate SANs.

## Theory7 checklist

In `My Domains`, set the list length to `All` before comparing domains. The
default first page can hide newly added domains.

For each new domain, open the DNS Manager zone and replace parking records with
the production record set:

```text
<domain>.                 A      300  <web-ipv4>
<domain>.                 AAAA   300  <web-ipv6>
<domain>.                 MX     600  10 <domain>.
<domain>.                 TXT    600  "v=spf1 mx -all"
_dmarc.<domain>.          TXT    600  "v=DMARC1; p=reject; sp=reject; adkim=s; aspf=s"
_domainkey.<domain>.      TXT    600  "o=~"
mail._domainkey.<domain>. TXT    300  "<dkim-public-key>"
www.<domain>.             CNAME  300  <domain>.
mail.<domain>.            CNAME  300  <domain>.
imap.<domain>.            CNAME  300  mail.<domain>.
<domain>.                 CAA    600  0 issue "letsencrypt.org"
_25._tcp.<domain>.        TLSA   600  3 1 1 <uppercase-spki-sha256>
```

The TLSA owner is `_25._tcp.<domain>` when MX points at the domain apex. Theory7
validates TLSA certificate association data as uppercase hex. Generate it from
the current leaf certificate and uppercase it before pasting:

```bash
openssl x509 -in <leaf-cert.pem> -pubkey -noout |
  openssl pkey -pubin -outform DER |
  openssl dgst -sha256 -binary |
  xxd -p -c 256 |
  tr '[:lower:]' '[:upper:]'
```

The UI may display the TLSA data lowercase or line-wrapped after saving. Trust
the authoritative `dig @ns.theory7.net` result over the visual formatting.

After deploying a certificate that adds names, recompute the live certificate
SPKI hash and compare it with every `_25._tcp.<domain>` record that uses the
shared mail certificate. ACME may issue a certificate with a new key when the SAN
set changes; in that case, update the TLSA record for every existing hosted
domain, not only the newly added one.

```bash
ssh root@<server> "cat /persist/var/lib/acme/s-gamma-mail/fullchain.pem" |
  openssl x509 -pubkey -noout |
  openssl pkey -pubin -outform DER |
  openssl dgst -sha256 -binary |
  xxd -p -c 256 |
  tr '[:lower:]' '[:upper:]'
```

Check each authoritative Theory7 nameserver before considering DANE done; a
single lagging secondary can still serve the stale TLSA record.

Open the domain's DNSSEC page and use `DNSSEC inschakelen`. For domains using
Theory7 nameservers, the page fetches the PowerDNS key and saves it at the
registry. Verify both the registry/RDAP state and live DNS; the registry
database may update before the TLD zone publishes the NS/DS records.

```bash
dig @ns.theory7.net <domain> A +short
dig @ns.theory7.net <domain> AAAA +short
dig @ns.theory7.net <domain> MX +short
dig @ns.theory7.net _25._tcp.<domain> TLSA +short
dig <domain> NS +short
dig <domain> DS +short
delv <domain> A
```

For `.nl` domains, SIDN RDAP can show nameservers and DS data before all public
resolvers validate the delegation:

```bash
curl -fsSL "https://rdap.sidn.nl/domain/<domain>" |
  jq '{ldhName,status,nameservers,secureDNS,events}'
dig +norecurse @ns1.dns.nl <domain> NS
dig +norecurse @ns1.dns.nl <domain> DS
```

If RDAP is updated but `dig <domain> DS` is still empty, wait for TLD-zone or
resolver-cache propagation. Do not keep re-saving DNSSEC unless Theory7 reports
an error.

## SOPS and Nix

Create a new encrypted hosted mailbox secret with a generic id:

```bash
mailbox_set=mailbox-NNN
target="secrets/${mailbox_set}.yaml"
sops edit "$target"
```

The decrypted `mailbox/env` should contain the concrete domain and mail host,
plus generic account ids:

```text
MAILBOX_DOMAIN=<domain>
MAILBOX_MAIL_HOST=mail.<domain>
MAILBOX_ACCOUNTS=mail-account-NNN mail-account-NNN
```

Add `MAILBOX_DEFAULT_ACCOUNT=mail-account-NNN` only when this domain should
become the canonical website domain and the default account in aerc/Geary.
Exactly one hosted mailbox set across the complete inventory must contain
`MAILBOX_DEFAULT_ACCOUNT` or `MAILBOX_DEFAULT_ADDRESS`; adding the marker to an
ordinary redirect domain makes activation fail.

Add only the generic mailbox id to `profiles/mail/inventory.nix`. Do not add the
domain name there. If the domain should be a web redirect, edit only the
encrypted `web/redirects/env` value in `secrets/s-gamma-runtime.yaml`:

```text
WEB_REDIRECT_DOMAINS=<domain> www.<domain>
WEB_REDIRECT_STATUS=301
```

If the domain must be covered by the shared mail/web certificate, include the
concrete names in the encrypted `MAIL_TLS_DOMAINS` value, not in Nix modules.

### Change the canonical web domain

Changing the primary public domain is an encrypted mailbox change. The canonical
domain is `MAILBOX_DOMAIN` from the single hosted mailbox set carrying
`MAILBOX_DEFAULT_ACCOUNT` or `MAILBOX_DEFAULT_ADDRESS`. Move that marker from
the old set to the new set; do not duplicate the domain in `web/contact/env`.
The same marker makes this domain/account the first default in aerc and Geary.

When the public/form mail addresses should also move, update only their generic
mailbox-set selectors in encrypted `web/contact/env`:

```text
WEB_PUBLIC_CONTACT_MAILBOX_SET=mailbox-NNN
WEB_FORM_MAILBOX_SET=mailbox-NNN
WEB_CONTACT_MAILBOX_SET=mailbox-NNN
```

In encrypted `web/redirects/env`, adjust only the domain list:

```text
WEB_REDIRECT_DOMAINS=<old-canonical-domain> www.<old-canonical-domain> ...
```

The webpage renderer derives `WEB_SITE_DOMAIN`, `WEB_SITE_URL`,
`CONTACT_SITE_URL`, `WEB_REDIRECT_TARGET_URL`, and the allowed redirect target
from the default mailbox set. Both the webpage and nginx environment renderers
require exactly one default and reject a conflicting legacy `WEB_SITE_DOMAIN`.

Do not leave the new canonical apex or `www.<new-canonical-domain>` in
`WEB_REDIRECT_DOMAINS`. The nginx generator treats the apex and `www` pair
together; if either one is in the redirect list, it will not emit the normal
canonical web vhost for the apex. Leaving the apex out lets the site serve from
the canonical domain and lets nginx redirect `www` to the apex.

For mail-style web hostnames, leave `mail.<new-canonical-domain>` out when it is
the hosted mailbox `MAILBOX_MAIL_HOST`; nginx will emit a direct redirect to the
apex. Add `imap.<new-canonical-domain>` to `WEB_REDIRECT_DOMAINS` only when that
hostname should also have a web redirect response instead of falling through to
the default vhost.

After deploying, verify:

```bash
ssh root@<server> "grep -n 'WEB_SITE_DOMAIN\|WEB_SITE_URL\|WEB_REDIRECT_TARGET_URL' /run/s-gamma/webpage/env"
curl -I https://<new-canonical-domain>/
curl -I https://<old-canonical-domain>/
```

The canonical domain and redirect domains are all public: unauthenticated checks
return `200` for the canonical site and the redirect interstitial for redirect
domains, which then navigate to the canonical target.

The derived `WEB_SITE_DOMAIN` also owns temporary host-specific backend tooling such as
`/__preview/logo-inspectie/`. Changing the canonical domain moves that explicit
nginx endpoint to the new host. Verify that it is served on the canonical host
and returns `404` on every redirect domain; a `30x` to the tool on the canonical
host means the isolation is incomplete.

New untracked SOPS files are not visible to flake evaluation. Mark them with
intent-to-add before evaluating or deploying:

```bash
git add -N secrets/mailbox-NNN.yaml
nix eval .#nixosConfigurations.s-gamma.config.system.build.toplevel.drvPath
```

Before finishing, prove concrete domains did not leak into the NixOS checkout:

```bash
rg -n '<concrete-domain-regex>' .
```

This search should return no matches. It is normal for the encrypted SOPS files
to change; the decrypted values must not appear in plaintext repo files.
Do not create loose `*.password` files in a checkout; account passwords belong
inside encrypted SOPS secrets only.

## Apply

Evaluate before switching:

```bash
nix eval .#nixosConfigurations.l-esp.config.system.build.toplevel.drvPath
nix eval .#nixosConfigurations.s-gamma.config.system.build.toplevel.drvPath
```

Apply the workstation config so aerc and Geary receive the new accounts:

```bash
sudo nixos-rebuild switch --flake .#l-esp
systemctl --user start aerc-account-sync.service geary-account-sync.service
```

If root `sudo` is not available, activate only the Home Manager generation from
the NixOS config:

```bash
nix build .#nixosConfigurations.l-esp.config.home-manager.users.deadbeef.home.activationPackage
./result/activate
rm result
```

Verify the account sync:

```bash
systemctl --user status aerc-account-sync.service geary-account-sync.service --no-pager
rg -n '<domain>' ~/.config/aerc ~/.config/geary ~/.local/share/geary
```

Apply the server config and regenerate runtime files:

```bash
nixos-rebuild switch --flake .#s-gamma --target-host root@<server>
ssh root@<server> systemctl start \
  s-gamma-mail-runtime-config.service \
  s-gamma-nginx-runtime-config.service \
  s-gamma-cert-mail.service
```

Verify server mail state and certificate coverage:

```bash
ssh root@<server> "postmap -s /run/s-gamma/mail/postfix/vdomains | rg '<domain>'"
ssh root@<server> "grep -n '<domain>' /run/s-gamma/mail/dovecot/passwd /run/s-gamma/mail/postfix/vaccounts"
ssh root@<server> "cat /persist/var/lib/acme/s-gamma-mail/fullchain.pem" |
  openssl x509 -noout -subject -ext subjectAltName
```

## Public access

The canonical website and redirect domains are public. The nginx preview basic
auth gate was removed from `profiles/nixos/web/server/default.nix`; no
`auth_basic` directive or htpasswd remains.

Verify before finishing:

```bash
curl -I https://<canonical-domain>/
curl -I https://<canonical-domain>/.well-known/security.txt
curl -I https://<redirect-domain>/any/nonexistent/file
```

When public DNS is still propagating, force the check against `s-gamma`:

```bash
curl -k -sS -o /dev/null -D - --resolve <domain>:443:<server-ip> https://<domain>/
curl -k -sS -o /dev/null -D - --resolve <domain>:443:<server-ip> https://<domain>/.well-known/security.txt
```

Expected:

```text
https://<canonical-domain>/                       -> 200
https://<canonical-domain>/.well-known/security.txt -> 200
https://<redirect-domain>/any/nonexistent/file    -> 200 HTML
```

## Runtime privilege checks

The Python backend and nginx must not share an identity. After deployment,
verify the service user and the rendered credential boundary:

```bash
ssh root@<server> 'systemctl show s-gamma-webpage.service -p User -p Group'
ssh root@<server> 'stat -c "%U:%G %a %n" /run/s-gamma/webpage /run/s-gamma/webpage/env /run/s-gamma/nginx/http.conf'
ssh root@<server> 'sudo -u s-gamma-webpage test -r /run/s-gamma/webpage/env'
ssh root@<server> 'sudo -u nginx test ! -r /run/s-gamma/webpage/env'
ssh root@<server> 'sudo -u nginx test -r /run/s-gamma/nginx/http.conf'
```

SOPS source secrets are `root:root 0400`. Root-owned one-shot services render a
minimal backend env and nginx-only files; neither long-running service gets the
complete source secret set. Do not add `nginx` to the backend group or run the
Python service as `nginx` to work around a failed permission check.
