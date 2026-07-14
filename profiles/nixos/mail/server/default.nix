{ config
, lib
, mailboxSets ? null
, name
, pkgs
, ...
}:
let
  cfg = config.profiles.mail.server;
  hostName = config.networking.hostName or name;
  networkAddressesUnit = cfg.networkAddress.unit;
  mailRuntimeConfigService = "${hostName}-mail-runtime-config";
  mailRuntimeConfigUnit = "${mailRuntimeConfigService}.service";
  rspamdRuntimeConfigService = "${hostName}-rspamd-runtime-config";
  sharedSubscriptionsService = "${hostName}-mail-shared-subscriptions";
  mailRetentionService = "${hostName}-mail-retention";
  retentionMaxDays = cfg.retention.maxDays;

  runtimeRoot = cfg.runtimeRoot;
  postfixRuntimeDir = "${runtimeRoot}/mail/postfix";
  dovecotRuntimeDir = "${runtimeRoot}/mail/dovecot";
  mailTlsFullchainPath = cfg.tls.fullchainPath;
  mailTlsKeyPath = cfg.tls.keyPath;
  sharedSenderLoginMap = "${postfixRuntimeDir}/shared-vaccounts";

  mailEnvPath = config.sops.secrets.${cfg.mailEnvSecretName}.path;
  networkAddressEnvPath = config.sops.secrets.${cfg.networkAddress.secretName}.path;
  mailSecretEnvRefs = mailboxSets.envSecretRefs;
  mailboxSetEnvPaths = mailboxSetEnvPathsConfig.paths;
  mailboxSetEnvPathList = mailboxSetEnvPathsConfig.pathList;
  mailboxSetEnvPathsConfig = mailboxSets.mkEnvPaths {
    inherit config lib pkgs;
    name = "${hostName}-mailbox-set-env-paths";
    secretRefs = mailboxSets.mailboxSetEnvSecretRefs;
  };
  mailAccountEnvPaths = mailAccountEnvPathsConfig.paths;
  mailAccountEnvPathList = mailAccountEnvPathsConfig.pathList;
  mailAccountEnvPathsConfig = mailboxSets.mkEnvPaths {
    inherit config lib pkgs;
    name = "${hostName}-mail-account-env-paths";
    secretRefs = mailboxSets.mailAccountEnvSecretRefs;
  };

  waitForReadableFiles = label: paths: ''
    for path in ${lib.concatMapStringsSep " " lib.escapeShellArg paths}; do
      until [ -r "$path" ]; do
        echo "${label}: waiting for readable file: $path" >&2
        sleep 1
      done
    done
  '';

  renderMailRuntime = import ./render-runtime.nix {
    inherit
      dovecotRuntimeDir
      hostName
      lib
      mailAccountEnvPathList
      mailEnvPath
      mailboxSetEnvPathList
      mailTlsFullchainPath
      mailTlsKeyPath
      networkAddressEnvPath
      pkgs
      postfixRuntimeDir
      sharedSenderLoginMap
      ;
  };

  syncSharedMailSubscriptions = import ./shared-subscriptions.nix {
    inherit
      cfg
      hostName
      lib
      mailAccountEnvPathList
      mailEnvPath
      mailboxSetEnvPathList
      pkgs
      sharedSenderLoginMap
      ;
  };

  applyMailRetention = import ./retention.nix {
    inherit
      hostName
      lib
      mailAccountEnvPathList
      mailboxSetEnvPathList
      pkgs
      retentionMaxDays
      ;
  };

  commonSubmissionOptions = {
    smtpd_tls_security_level = "encrypt";
    smtpd_sasl_auth_enable = "yes";
    smtpd_sasl_type = "dovecot";
    smtpd_sasl_path = "/run/dovecot2/auth";
    smtpd_sasl_security_options = "noanonymous";
    smtpd_client_restrictions = "permit_sasl_authenticated,reject";
    smtpd_sender_restrictions = "reject_sender_login_mismatch";
    smtpd_recipient_restrictions = "reject_non_fqdn_recipient,reject_unknown_recipient_domain,permit_sasl_authenticated,reject";
    milter_macro_daemon_name = "ORIGINATING";
  };

  postfixTls12CipherList = lib.concatStringsSep ":" [
    "ECDHE-ECDSA-AES256-GCM-SHA384"
    "ECDHE-ECDSA-CHACHA20-POLY1305"
    "ECDHE-ECDSA-AES128-GCM-SHA256"
    "@STRENGTH"
    "@SECLEVEL=2"
  ];
in
{
  options.profiles.mail.server = {
    enable = lib.mkEnableOption "SOPS-backed Postfix and Dovecot virtual mail server";

    sopsFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = "SOPS file containing the mail server runtime env secret.";
    };

    mailEnvSecretName = lib.mkOption {
      type = lib.types.str;
      default = "mail/server/env";
      description = "SOPS secret key containing MAIL_* server env variables.";
    };

    runtimeRoot = lib.mkOption {
      type = lib.types.str;
      default = "/run/${config.networking.hostName}";
      description = "Runtime root for generated mail maps and Dovecot passwd files.";
    };

    sharedNamespacePrefix = lib.mkOption {
      type = lib.types.str;
      default = "s";
      description = "Visible IMAP shared namespace prefix.";
    };

    sharedNamespaceIncludeDomain = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Whether shared mailbox names include the owner domain, yielding s/example.com/name instead of s/name.";
    };

    sharedExplicitInbox = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Whether shared INBOXes are visible as s/example.com/name/INBOX instead of s/example.com/name.";
    };

    sharedInheritInboxAcl = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Whether Dovecot should use INBOX ACLs as defaults for shared child mailboxes.";
    };

    sharedSubscriptions.timer.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Whether to periodically refresh Dovecot shared mailbox ACL projections.";
    };

    networkAddress = {
      secretName = lib.mkOption {
        type = lib.types.str;
        default = "network/address_env";
        description = "SOPS secret key containing network address env variables.";
      };

      unit = lib.mkOption {
        type = lib.types.str;
        default = "${config.networking.hostName}-network-addresses.service";
        description = "Systemd unit that renders or applies runtime network address data.";
      };
    };

    tls = {
      fullchainPath = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Runtime fullchain path for SMTP and IMAP TLS.";
      };

      keyPath = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Runtime private key path for SMTP and IMAP TLS.";
      };
    };

    retention.maxDays = lib.mkOption {
      type = lib.types.ints.positive;
      default = 30;
      description = "Maximum number of days any account-provided retention policy may keep messages.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = mailboxSets != null;
        message = "profiles.mail.server requires profiles.nixos.mail.mailbox-sets to be imported and enabled.";
      }
      {
        assertion = cfg.sopsFile != null;
        message = "profiles.mail.server.sopsFile must be set.";
      }
      {
        assertion = cfg.tls.fullchainPath != null && cfg.tls.keyPath != null;
        message = "profiles.mail.server.tls.fullchainPath and keyPath must be set.";
      }
      {
        assertion = cfg.sharedNamespacePrefix != "";
        message = "profiles.mail.server.sharedNamespacePrefix must be non-empty because Dovecot's private namespace already owns the empty prefix.";
      }
    ];

    users.groups.virtualMail = { };
    users.users.virtualMail = {
      isSystemUser = true;
      group = "virtualMail";
      home = "/var/vmail";
    };

    sops.secrets =
      {
        ${cfg.mailEnvSecretName} = {
          sopsFile = cfg.sopsFile;
          restartUnits = [
            mailRuntimeConfigUnit
            "postfix.service"
            "dovecot.service"
          ];
        };
      }
      // builtins.listToAttrs (
        map
          (secret: {
            inherit (secret) name;
            value = {
              inherit (secret) key sopsFile;
              restartUnits = [
                mailRuntimeConfigUnit
                "postfix.service"
                "dovecot.service"
              ];
            };
          })
          mailSecretEnvRefs
      );

    systemd.tmpfiles.rules = [
      "d ${runtimeRoot} 0755 root root -"
      "d ${runtimeRoot}/mail 0755 root root -"
      "d ${postfixRuntimeDir} 0750 root postfix -"
      "d ${dovecotRuntimeDir} 0750 root dovecot2 -"
      "d /var/lib/postfix/data 0700 postfix postfix -"
      "z /var/lib/postfix/data 0700 postfix postfix -"
      "z /var/lib/postfix/data/master.lock 0600 postfix postfix -"
      "z /var/lib/postfix/data/prng_exch 0600 postfix postfix -"
      "d /var/vmail 0750 virtualMail virtualMail -"
      "d /var/lib/dovecot 0755 root root -"
      "d /var/lib/dovecot/db 0770 virtualMail virtualMail -"
      "Z /var/lib/dovecot/db - virtualMail virtualMail -"
    ];

    systemd.services.${mailRuntimeConfigService} = {
      description = "Render ${hostName} mail runtime maps from SOPS";
      after = [
        "postfix-setup.service"
        networkAddressesUnit
      ];
      requires = [
        "postfix-setup.service"
        networkAddressesUnit
      ];
      before = [
        "postfix.service"
        "dovecot.service"
      ];
      requiredBy = [
        "postfix.service"
        "dovecot.service"
      ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        TimeoutStartSec = "5min";
      };
      preStart = waitForReadableFiles "mail runtime" (
        [
          networkAddressEnvPath
          mailEnvPath
          mailTlsFullchainPath
          mailTlsKeyPath
        ]
        ++ mailboxSetEnvPaths
        ++ mailAccountEnvPaths
      );
      script = "${lib.getExe renderMailRuntime}";
    };

    systemd.services.${rspamdRuntimeConfigService} = {
      description = "Prepare ${hostName} rspamd runtime files";
      before = [ "rspamd.service" ];
      requiredBy = [ "rspamd.service" ];
      path = [ pkgs.coreutils ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        set -euo pipefail

        install -d -m 0755 -o root -g root /var/dkim

        found=0
        for key in /var/dkim/*.key; do
          [ -e "$key" ] || continue
          found=1
          chown rspamd:rspamd "$key"
          chmod 0400 "$key"
        done

        if [ "$found" -eq 0 ]; then
          echo "rspamd: no DKIM key found in /var/dkim" >&2
          exit 1
        fi
      '';
    };

    systemd.services.postfix = {
      after = [
        "dovecot.service"
        "rspamd.service"
        mailRuntimeConfigUnit
      ];
      requires = [
        "dovecot.service"
        mailRuntimeConfigUnit
      ];
      wants = [ "rspamd.service" ];
    };

    systemd.services.dovecot = {
      after = [ mailRuntimeConfigUnit ];
      requires = [ mailRuntimeConfigUnit ];
    };

    systemd.services.${sharedSubscriptionsService} = {
      description = "Sync Dovecot shared mailbox ACL projections";
      after = [
        "dovecot.service"
        mailRuntimeConfigUnit
      ];
      requires = [
        "dovecot.service"
        mailRuntimeConfigUnit
      ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = lib.getExe syncSharedMailSubscriptions;
      };
    };

    systemd.timers.${sharedSubscriptionsService} = lib.mkIf cfg.sharedSubscriptions.timer.enable {
      description = "Refresh Dovecot shared mailbox ACL projections";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec = "2min";
        OnUnitActiveSec = "15min";
        AccuracySec = "1min";
        Persistent = true;
      };
    };

    systemd.services.${mailRetentionService} = {
      description = "Apply Dovecot retention policies from SOPS mail account profiles";
      after = [
        "dovecot.service"
        mailRuntimeConfigUnit
      ];
      requires = [
        "dovecot.service"
        mailRuntimeConfigUnit
      ];
      preStart = waitForReadableFiles "mail retention" (
        mailboxSetEnvPaths ++ mailAccountEnvPaths
      );
      serviceConfig = {
        Type = "oneshot";
        ExecStart = lib.getExe applyMailRetention;
      };
    };

    systemd.timers.${mailRetentionService} = {
      description = "Run Dovecot mail retention policies";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = "*-*-* 04:20:00";
        RandomizedDelaySec = "30min";
        Persistent = true;
      };
    };

    services.postfix = {
      enable = true;
      enableSmtp = true;
      enableSubmission = true;
      enableSubmissions = true;

      settings.main = {
        myhostname = "localhost.invalid";
        mydestination = "";
        recipient_delimiter = "+";
        disable_vrfy_command = true;
        message_size_limit = 20971520;

        virtual_transport = "lmtp:unix:/run/dovecot2/dovecot-lmtp";
        lmtp_destination_recipient_limit = "1";

        smtpd_sasl_type = "dovecot";
        smtpd_sasl_path = "/run/dovecot2/auth";
        smtpd_sasl_auth_enable = true;
        smtpd_relay_restrictions = [
          "permit_mynetworks"
          "permit_sasl_authenticated"
          "reject_unauth_destination"
        ];
        smtpd_tls_auth_only = true;

        smtpd_tls_chain_files = [
          mailTlsKeyPath
          mailTlsFullchainPath
        ];
        smtpd_tls_security_level = "may";
        smtpd_tls_protocols = ">=TLSv1.2";
        smtpd_tls_mandatory_protocols = ">=TLSv1.2";
        smtpd_tls_ciphers = "high";
        smtpd_tls_mandatory_ciphers = "high";

        tls_high_cipherlist = postfixTls12CipherList;
        tls_preempt_cipherlist = true;
        tls_eecdh_auto_curves = "X25519:prime256v1:secp384r1";

        smtp_dns_support_level = "dnssec";
        smtp_tls_security_level = "dane";
        smtp_tls_protocols = ">=TLSv1.2";
        smtp_tls_mandatory_protocols = ">=TLSv1.2";
        smtp_tls_ciphers = "high";
        smtp_tls_mandatory_ciphers = "high";
      };

      submissionOptions = commonSubmissionOptions;
      submissionsOptions = commonSubmissionOptions;
    };

    services.rspamd = {
      enable = true;
      postfix = {
        enable = true;
        config = {
          smtpd_milters = [ "unix:/run/rspamd/rspamd-milter.sock" ];
          non_smtpd_milters = [ "unix:/run/rspamd/rspamd-milter.sock" ];
          milter_default_action = "accept";
          milter_protocol = "6";
        };
      };
      locals."dkim_signing.conf".text = ''
        enabled = true;
        sign_authenticated = true;
        sign_local = true;
        allow_username_mismatch = true;

        selector = "mail";
        path = "/var/dkim/$domain.$selector.key";
      '';
    };

    services.dovecot2 = {
      enable = true;
      package = pkgs.dovecot;
      enablePAM = lib.mkForce false;

      settings = {
        dovecot_config_version = config.services.dovecot2.package.version;
        dovecot_storage_version = config.services.dovecot2.package.version;

        protocols = {
          imap = true;
          lmtp = true;
        };

        auth_mechanisms = [
          "plain"
          "login"
        ];

        mail_uid = "virtualMail";
        mail_gid = "virtualMail";
        mail_driver = "maildir";
        mail_path = "~/mail";
        mail_home = "/var/vmail/%{user | domain}/%{user | username}";
        mail_access_groups = "virtualMail";
        mail_plugins.acl = true;
        mailbox_list_layout = "Maildir++";
        mail_shared_explicit_inbox = cfg.sharedExplicitInbox;
        acl_defaults_from_inbox = cfg.sharedInheritInboxAcl;
        acl_driver = "vfile";

        "acl_sharing_map"."dict file".path = "/var/lib/dovecot/db/shared-mailboxes.db";

        "namespace inbox" = {
          inbox = true;
          separator = "/";
          "mailbox \"Archive\"" = {
            auto = "subscribe";
          };
          "mailbox \"Drafts\"" = {
            auto = "subscribe";
            special_use = "\\Drafts";
          };
          "mailbox \"Junk\"" = {
            auto = "subscribe";
            special_use = "\\Junk";
          };
          "mailbox \"Sent\"" = {
            auto = "subscribe";
            special_use = "\\Sent";
          };
          "mailbox \"Trash\"" = {
            auto = "subscribe";
            special_use = "\\Trash";
          };
        };

        "namespace shared" = {
          type = "shared";
          separator = "/";
          prefix = "${cfg.sharedNamespacePrefix}/"
            + lib.optionalString cfg.sharedNamespaceIncludeDomain "$domain/"
            + "$username/";
          list = "children";
          subscriptions = false;
          mail_driver = "maildir";
          mail_path = "/var/vmail/%{owner_user | domain}/%{owner_user | username}/mail";
          mail_index_private_path = "~/mail/${cfg.sharedNamespacePrefix}/%{owner_user}";
        };

        "passdb sops-file" = {
          driver = "passwd-file";
          passwd_file_path = "${dovecotRuntimeDir}/passwd";
        };

        "userdb sops-file" = {
          driver = "passwd-file";
          passwd_file_path = "${dovecotRuntimeDir}/passwd";
          fields = {
            "home:default" = "/var/vmail/%{user | domain}/%{user | username}";
            "uid:default" = "virtualMail";
            "gid:default" = "virtualMail";
          };
        };

        "service auth"."unix_listener auth" = {
          user = "postfix";
          group = "postfix";
          mode = "0660";
        };

        "service lmtp"."unix_listener dovecot-lmtp" = {
          user = "postfix";
          group = "postfix";
          mode = "0600";
        };

        "service imap-login" = {
          "inet_listener imap".port = 143;
          "inet_listener imaps" = {
            port = 993;
            ssl = true;
          };
        };

        "protocol imap".mail_plugins.imap_acl = true;

        ssl = "required";
        ssl_server_cert_file = mailTlsFullchainPath;
        ssl_server_key_file = mailTlsKeyPath;
        ssl_min_protocol = "TLSv1.2";
      };
    };

    networking.firewall.allowedTCPPorts = [
      25
      143
      465
      587
      993
    ];
  };
}
