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
8. Verify DNS, mail maps, certificate SANs, and basic auth.

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
MAILBOX_DEFAULT_ACCOUNT=mail-account-NNN
```

Add only the generic mailbox id to `profiles/mail/inventory.nix`. Do not add the
domain name there. If the domain should be a web redirect, edit only the
encrypted `web/redirects/env` value in `secrets/s-gamma-runtime.yaml`:

```text
WEB_REDIRECT_DOMAINS=<domain> www.<domain>
WEB_REDIRECT_TARGET_URL=https://<canonical-domain>
WEB_REDIRECT_STATUS=301
```

If the domain must be covered by the shared mail/web certificate, include the
concrete names in the encrypted `MAIL_TLS_DOMAINS` value, not in Nix modules.

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

## Basic auth

The website must stay behind preview auth until the release date. Do not remove
or override the global nginx `auth_basic` settings in
`profiles/nixos/web/server/default.nix`. The only unauthenticated web paths
should be `security.txt` endpoints.

The runtime nginx include must not contain host-level `off` entries. The preview
realm map should only delegate to the path-level map:

```nginx
map "$scheme:$host" $managed_web_preview_realm {
  default $managed_web_preview_path_realm;
}
```

This is the intended path-only exception:

```nginx
map $uri $managed_web_preview_path_realm {
  default "preview";
  /.well-known/security.txt off;
  /security.txt off;
}
```

Check the generated runtime include after deploying:

```bash
ssh root@<server> "sed -n '1,80p' /run/s-gamma/nginx/http.conf"
```

Verify before finishing:

```bash
curl -I https://<domain>/
curl -I https://<domain>/.well-known/security.txt
```

When public DNS is still propagating, force the check against `s-gamma`:

```bash
curl -k -sS -o /dev/null -D - --resolve <domain>:443:<server-ip> https://<domain>/
curl -k -sS -o /dev/null -D - --resolve <domain>:443:<server-ip> https://<domain>/.well-known/security.txt
```

Expected during preview:

```text
https://<domain>/                  -> 401 with Basic realm="preview"
https://<domain>/.well-known/security.txt -> 200
```
