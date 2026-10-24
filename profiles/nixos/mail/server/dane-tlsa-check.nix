/**
  DANE/TLSA consistency guardrail for the hosted mail domains.

  Publishes nothing. Reads the hosted domain list from the rendered Postfix
  `vdomains` hash (never a hardcoded name), computes the live mail leaf
  certificate's SPKI SHA-256, and compares it against every hosted domain's
  `_25._tcp.<domain>` TLSA record as served by the configured nameservers.

  A domain that publishes DANE-EE(3)/SPKI(1)/SHA-256(1) pins but none matching the
  live leaf means the published pin no longer matches what the server actually
  presents, which silently breaks inbound SMTP DANE validation for senders that
  enforce it. The unit fails loudly with the exact records to publish, so a
  key-rotating renewal is a copy/paste fix instead of an outage discovered by
  correspondents. Domains that publish no pins (or only other TLSA shapes) are
  reported and skipped.
*/
{ hostName
, lib
, mailTlsFullchainPath
, postfixRuntimeDir
, pkgs
}:

pkgs.writeShellApplication {
  name = "${hostName}-verify-dane-tlsa";
  runtimeInputs = [
    pkgs.coreutils
    pkgs.dnsutils
    pkgs.openssl
    pkgs.gnugrep
    pkgs.gawk
  ];
  text = ''
        set -euo pipefail

        vdomains=${lib.escapeShellArg "${postfixRuntimeDir}/vdomains"}
        fullchain=${lib.escapeShellArg mailTlsFullchainPath}

        die() {
          printf 'verify-dane-tlsa: %s\n' "$*" >&2
          exit 1
        }

        [ -s "$vdomains" ] || die "no hosted domains at $vdomains (mail runtime not rendered yet)"
        [ -s "$fullchain" ] || die "no mail fullchain at $fullchain"

        # Leaf certificate is the first PEM block in the fullchain.
        leaf_spki="$(
          openssl x509 -in "$fullchain" -pubkey -noout \
            | openssl pkey -pubin -outform DER \
            | openssl dgst -sha256 -binary \
            | od -An -tx1 -v | tr -d ' \n' | tr '[:lower:]' '[:upper:]'
        )"
        [ -n "$leaf_spki" ] || die "failed to compute leaf SPKI SHA-256 from $fullchain"

        printf 'verify-dane-tlsa: live leaf SPKI SHA-256 = %s\n' "$leaf_spki"

        # Postfix hash format: <key> <whitespace> <value>; the domain is the key.
        domains="$(
          gawk '{ print $1 }' "$vdomains" | grep -Ev '^$' | sort -u
        )"
        [ -n "$domains" ] || die "no domain keys found in $vdomains"

        failed=0
        checked=0
        while IFS= read -r domain; do
          [ -n "$domain" ] || continue

          # Resolve TLSA via the domain's own authoritative delegation. A missing
          # record is reported but is not a hard failure: DANE is opt-in per domain.
          tlsa_lines="$(dig +short TLSA "_25._tcp.$domain" 2>/dev/null || true)"

          if [ -z "$tlsa_lines" ]; then
            printf 'verify-dane-tlsa: %s: no TLSA record published (DANE off, skipped)\n' "$domain"
            continue
          fi

          # `dig +short` wraps long hex across lines (no blank-line separators), and some
          # servers emit one record per line. Normalise into one logical record per line by
          # joining any line that does not itself start with the "<usage> <selector>
          # <matchtype>" triple onto the previous record. A record is then
          # "<usage> <selector> <matchtype> <hex-without-spaces>".
          tlsa_records="$(printf '%s\n' "$tlsa_lines" | gawk '
            { lines[NR] = $0 }
            END {
              n = 0
              for (i = 1; i <= NR; i++) {
                l = lines[i]
                if (l ~ /^[0-9]+[ \t]+[0-9]+[ \t]+[0-9]+([ \t]|$)/) {
                  rec[++n] = l
                } else if (n > 0) {
                  rec[n] = rec[n] " " l
                }
              }
              for (i = 1; i <= n; i++) {
                gsub(/[ \t]+/, " ", rec[i])
                print rec[i]
              }
            }
          ')"

          # A domain passes when at least one published DANE-EE(3)/SPKI(1)/SHA-256(1)
          # pin matches the live leaf. Multiple pins are the documented rollover case
          # (old + new key published together); only the absence of any match is fatal.
          domain_pins=0
          domain_matched=0
          domain_mismatches=""

          while IFS= read -r record; do
            [ -n "$record" ] || continue
            # First three fields are the numeric TLSA triple; the remainder is the hash.
            triple="$(printf '%s' "$record" | cut -d' ' -f1-3)"
            rest="$(printf '%s' "$record" | cut -d' ' -f4-)"
            [ -n "$rest" ] || continue
            usage="$(printf '%s' "$triple" | cut -d' ' -f1)"
            selector="$(printf '%s' "$triple" | cut -d' ' -f2)"
            matchtype="$(printf '%s' "$triple" | cut -d' ' -f3)"

            # Strip any interior whitespace left by dig's wrapping.
            hash="$(printf '%s' "$rest" | tr -d ' \t')"
            [ -n "$hash" ] || continue

            # Only DANE-EE(3) + SPKI(1) + SHA-256(1) pins are directly comparable to
            # the leaf SPKI we computed. Anything else is reported, not judged.
            if [ "$usage" != "3" ] || [ "$selector" != "1" ] || [ "$matchtype" != "1" ]; then
              printf 'verify-dane-tlsa: %s: TLSA %s %s %s %s not a 3 1 1 leaf pin (skipped)\n' \
                "$domain" "$usage" "$selector" "$matchtype" "$hash"
              continue
            fi

            domain_pins=$((domain_pins + 1))
            checked=$((checked + 1))
            normalized="$(printf '%s' "$hash" | tr '[:lower:]' '[:upper:]')"

            if [ "$normalized" = "$leaf_spki" ]; then
              domain_matched=$((domain_matched + 1))
            else
              domain_mismatches="''${domain_mismatches}''${domain_mismatches:+
    }''${normalized}"
            fi
          done <<< "$tlsa_records"

          if [ "$domain_pins" -eq 0 ]; then
            printf 'verify-dane-tlsa: %s: no comparable 3 1 1 pin published (skipped)\n' "$domain"
          elif [ "$domain_matched" -gt 0 ]; then
            printf 'verify-dane-tlsa: %s: OK (%s/%s pin(s) match the live leaf)\n' \
              "$domain" "$domain_matched" "$domain_pins"
          else
            failed=$((failed + 1))
            printf 'verify-dane-tlsa: %s: MISMATCH (no published pin matches the live leaf)\n' "$domain" >&2
            printf '%s\n' "$domain_mismatches" | while IFS= read -r pin; do
              [ -n "$pin" ] || continue
              printf 'verify-dane-tlsa:   published: %s\n' "$pin" >&2
            done
            printf 'verify-dane-tlsa:   live leaf: %s\n' "$leaf_spki" >&2
            printf 'verify-dane-tlsa:   publish for %s: 3 1 1 %s\n' "$domain" "$leaf_spki" >&2
          fi
        done <<< "$domains"

        if [ "$failed" -ne 0 ]; then
          die "$failed hosted domain(s) have no DANE pin matching the live leaf certificate; update the TLSA records above"
        fi

        printf 'verify-dane-tlsa: %s DANE pin(s) checked across hosted domains, every domain matched\n' "$checked"
  '';
}
