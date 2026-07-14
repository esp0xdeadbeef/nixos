{ config, lib, mailboxSets ? null, outPath, profiles, ... }:

let
  hasMultipleMailboxSets =
    mailboxSets != null && lib.length mailboxSets.mailboxSetNames > 1;
in

{
  imports = [
    profiles.nixos.mail.server
  ];

  profiles.mail.server = {
    enable = true;
    sopsFile = outPath + "/secrets/s-gamma-runtime.yaml";
    sharedNamespacePrefix = "s";
    sharedNamespaceIncludeDomain = hasMultipleMailboxSets;
    sharedExplicitInbox = true;
    sharedInheritInboxAcl = true;
    sharedSubscriptions = {
      service.wantedBy = [ ];
      timer.enable = false;
    };

    networkAddress.unit = "${config.networking.hostName}-network-addresses.service";

    tls = {
      fullchainPath = config.sGamma.certs.mail.fullchainPath;
      keyPath = config.sGamma.certs.mail.keyPath;
    };

    retention.maxDays = config.local.mail.mailboxSets.retention.maxDays;
  };
}
