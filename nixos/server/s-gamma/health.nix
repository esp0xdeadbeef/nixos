{ config
, lib
, name
, pkgs
, ...
}:
let
  hostName = name;
  runtimeFullchain = config.sGamma.certs.mail.fullchainPath;
  mailPostfixDir = "/run/${hostName}/mail/postfix";
  resolver = "1.1.1.1";
  certWarnSeconds = 1209600; # 14 days

  healthCheck = pkgs.writeShellApplication {
    name = "${hostName}-mail-health-check";
    runtimeInputs = with pkgs; [
      coreutils
      dnsutils
      gawk
      gnugrep
      openssl
      postfix
      systemd
    ];
    text = ''
      set -uo pipefail

      fullchain=${lib.escapeShellArg runtimeFullchain}
      vdomains=${lib.escapeShellArg "${mailPostfixDir}/vdomains"}
      resolver=${lib.escapeShellArg resolver}
      cert_warn_seconds=${toString certWarnSeconds}

      problems=""
      add_problem() {
        problems="$problems"$'\n'"- $1"
      }

      if [ ! -r "$fullchain" ]; then
        add_problem "mail certificate is not readable: $fullchain"
      else
        if ! openssl x509 -checkend "$cert_warn_seconds" -noout -in "$fullchain" >/dev/null 2>&1; then
          add_problem "mail certificate expires within $((cert_warn_seconds / 86400)) days"
        fi

        spki="$(openssl x509 -in "$fullchain" -pubkey -noout \
          | openssl pkey -pubin -outform DER \
          | openssl dgst -sha256 | awk '{print $NF}' | tr '[:lower:]' '[:upper:]')"
        expected="311$spki"

        if [ -r "$vdomains" ]; then
          while read -r domain _; do
            [ -n "$domain" ] || continue
            published="$(dig +short "@$resolver" "_25._tcp.$domain" TLSA 2>/dev/null \
              | head -1 | tr -d '[:blank:]' | tr '[:lower:]' '[:upper:]')"
            if [ "$published" != "$expected" ]; then
              add_problem "TLSA mismatch for $domain (published: ''${published:-none}, expected: $expected)"
            fi
          done < "$vdomains"
        fi
      fi

      for unit in postfix dovecot knot rspamd nginx; do
        if ! systemctl is-active --quiet "$unit.service"; then
          add_problem "unit $unit.service is not active"
        fi
      done

      queue="$(mailq 2>/dev/null | tail -1 || true)"
      echo "mail queue: $queue"

      if [ -n "$problems" ]; then
        mydomain="$(postconf -h mydomain 2>/dev/null || true)"
        [ -n "$mydomain" ] || mydomain=localhost
        recipient="root@$mydomain"
        {
          printf 'Subject: [%s] mail health check failed\n' "${hostName}"
          printf 'To: %s\n\n' "$recipient"
          printf 'Problems detected:\n%s\n' "$problems"
        } | sendmail -f "$recipient" "$recipient"
        printf '%s\n' "$problems" >&2
        exit 1
      fi

      echo "mail health check OK"
    '';
  };
in
{
  systemd.services."${hostName}-mail-health-check" = {
    description = "Verify mail certificate, DANE TLSA and mail services";
    after = [ "${hostName}-mail-runtime-config.service" ];
    wants = [ "${hostName}-mail-runtime-config.service" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = lib.getExe healthCheck;
    };
  };

  systemd.timers."${hostName}-mail-health-check" = {
    description = "Periodic mail health check";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "*-*-* 06:00:00";
      RandomizedDelaySec = "30min";
      Persistent = true;
    };
  };
}
