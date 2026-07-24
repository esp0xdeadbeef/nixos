{ config, profiles, relativeRepo, ... }:
{
  imports = [
    profiles.nixos.mail.server
  ];

  profiles.mail.server = {
    enable = true;
    sopsFile = relativeRepo.sourcePath "secrets/s-gamma-runtime.yaml";
    sharedNamespacePrefix = "s";
    # Sharing is same-domain only, so including the domain adds hierarchy
    # without disambiguating anything for an individual IMAP user. Keep the
    # selectable shared INBOX at s/<owner>, which is also the shape handled by
    # clients before multiple hosted mailbox sets were introduced.
    sharedNamespaceIncludeDomain = false;
    sharedExplicitInbox = false;
    sharedInheritInboxAcl = true;
    sharedSubscriptions = {
      service.wantedBy = [ "multi-user.target" ];
      timer = {
        enable = true;
        onBootSec = "2min";
        onUnitActiveSec = "5min";
      };
    };

    networkAddress.unit = "${config.networking.hostName}-network-addresses.service";

    tls = {
      fullchainPath = config.sGamma.certs.mail.fullchainPath;
      keyPath = config.sGamma.certs.mail.keyPath;
    };

    # Inbox cleanup is move-only. No account secret may enable server-side
    # expunge/retention on this host.
    retention = {
      enable = false;
      maxDays = config.local.mail.mailboxSets.retention.maxDays;
    };
  };
}
