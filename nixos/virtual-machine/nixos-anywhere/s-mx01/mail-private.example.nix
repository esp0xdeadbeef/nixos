{ config, lib, ... }:
let
  domain = "example.invalid";
  fqdn = "mail.${domain}";
  primaryAccount = "postmaster@${domain}";
  contactAccount = "contact@${domain}";
  userAccount = "user@${domain}";
  # No admin right, so the user can use the shared mailbox but cannot delegate ACLs.
  contactAclRights = [
    "lookup"
    "read"
    "write"
    "write-seen"
    "write-deleted"
    "insert"
    "post"
    "expunge"
    "create"
    "delete"
  ];
  contactAclRightsArgs = lib.escapeShellArgs contactAclRights;
  doveadm = lib.getExe' config.services.dovecot2.package "doveadm";
  sopsFile = ../../../../secrets/s-mx01.yaml;
in
{
  networking.domain = domain;

  security.acme = {
    acceptTerms = true;
    defaults.email = contactAccount;
  };

  services.nginx = {
    enable = true;
    virtualHosts.${fqdn}.enableACME = true;
  };

  networking.firewall.allowedTCPPorts = [ 80 ];

  sops.secrets = {
    "mail/accounts/postmaster/hashed-password".sopsFile = sopsFile;
    "mail/accounts/mailbox-001/hashed-password".sopsFile = sopsFile;
    "mail/accounts/user-001/hashed-password".sopsFile = sopsFile;
  };

  systemd.services.example-mail-shared-access = {
    description = "Grant user access to the contact mailbox";
    wantedBy = [ "multi-user.target" ];
    requires = [ "dovecot.service" ];
    after = [ "dovecot.service" ];
    serviceConfig.Type = "oneshot";
    script = ''
      set -euo pipefail

      ${doveadm} mailbox create -u ${contactAccount} INBOX >/dev/null 2>&1 || true
      ${doveadm} mailbox status -u ${contactAccount} messages INBOX >/dev/null
      ${doveadm} acl set -u ${contactAccount} INBOX user=${userAccount} ${contactAclRightsArgs}
    '';
  };

  systemd.services.example-mail-contact-retention = {
    description = "Delete contact mailbox mail older than 12 months";
    requires = [ "dovecot.service" ];
    after = [ "dovecot.service" ];
    serviceConfig.Type = "oneshot";
    script = ''
      set -euo pipefail

      ${doveadm} mailbox status -u ${contactAccount} messages INBOX >/dev/null
      ${doveadm} expunge -u ${contactAccount} mailbox '*' savedbefore 365d
    '';
  };

  systemd.timers.example-mail-contact-retention = {
    description = "Daily contact mailbox retention cleanup";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "daily";
      Persistent = true;
      RandomizedDelaySec = "15m";
    };
  };

  services.dovecot2.settings = {
    mail_plugins.acl = true;

    "protocol imap".mail_plugins.imap_acl = true;

    "namespace shared" = {
      type = "shared";
      separator = config.mailserver.hierarchySeparator;
      prefix = "shared.$username.";
      mail_driver = "maildir";
      mail_path = "%{owner_home}/mail";
      mail_index_private_path = "~/mail/shared/%{owner_user}";
      subscriptions = false;
      list = "children";
    };

    acl_driver = "vfile";
    acl_defaults_from_inbox = true;
    acl_sharing_map."dict file".path = "/var/lib/dovecot/db/shared-mailboxes.db";
  };

  systemd.tmpfiles.rules = [
    "d /var/lib/dovecot/db 0770 ${config.mailserver.storage.owner} ${config.mailserver.storage.group} -"
  ];

  mailserver = {
    enable = true;
    stateVersion = 5;

    inherit fqdn;
    domains = [ domain ];
    systemContact = contactAccount;

    enableSubmission = true;
    x509.useACMEHost = config.mailserver.fqdn;

    accounts = {
      ${primaryAccount} = {
        hashedPasswordFile = config.sops.secrets."mail/accounts/postmaster/hashed-password".path;
        sieveScript = ''
          require ["vacation"];

          vacation
            :days 30
            :subject "${primaryAccount} is buiten gebruik"
            :addresses ["${primaryAccount}"]
          text:
          ${primaryAccount} is buiten gebruik.

          Gebruik ${contactAccount} voor berichten.
          .
            ;
        '';
      };

      ${userAccount} = {
        hashedPasswordFile = config.sops.secrets."mail/accounts/user-001/hashed-password".path;
      };

      ${contactAccount} = {
        hashedPasswordFile = config.sops.secrets."mail/accounts/mailbox-001/hashed-password".path;
        aliases = [
          "abuse@${domain}"
          "admin@${domain}"
          "info@${domain}"
          "root@${domain}"
        ];
      };
    };
  };
}
