{ config
, lib
, outPath
, ...
}:
let
  cfg = config.local.mail.mailboxSets;
  mailboxSets = import ../../mail/mailbox-sets.nix {
    mailAccountNames = cfg.accountNames;
    mailboxSetNames = cfg.names;
    secretsRoot = cfg.secretsRoot;
  };
in
{
  options.local.mail.mailboxSets = {
    enable = lib.mkEnableOption "generic SOPS-backed mailbox set profiles";

    names = lib.mkOption {
      type = lib.types.nullOr (lib.types.listOf lib.types.str);
      default = null;
      description = "Mailbox set ids to load. Null discovers secrets/mailbox-*.yaml.";
    };

    accountNames = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Mail account ids to expose to this server. Client-only accounts should not be listed here.";
    };

    retention.maxDays = lib.mkOption {
      type = lib.types.ints.positive;
      default = 30;
      description = "Maximum number of days any server-side mail account retention secret may keep messages.";
    };

    secretsRoot = lib.mkOption {
      type = lib.types.path;
      default = outPath + "/secrets";
      description = "Repository secrets directory containing mailbox-*.yaml files.";
    };
  };

  config = lib.mkIf cfg.enable {
    _module.args.mailboxSets = mailboxSets;
  };
}
