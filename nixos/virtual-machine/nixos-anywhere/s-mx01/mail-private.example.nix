{ config, ... }:
let
  domain = "example.invalid";
  fqdn = "mail.${domain}";
  primaryAccount = "postmaster@${domain}";
in
{
  networking.domain = domain;

  security.acme = {
    acceptTerms = true;
    defaults.email = primaryAccount;
  };

  services.nginx = {
    enable = true;
    virtualHosts.${fqdn}.enableACME = true;
  };

  networking.firewall.allowedTCPPorts = [ 80 ];

  mailserver = {
    enable = true;
    stateVersion = 5;

    inherit fqdn;
    domains = [ domain ];
    systemContact = primaryAccount;

    enableSubmission = true;
    x509.useACMEHost = config.mailserver.fqdn;

    accounts.${primaryAccount} = {
      hashedPasswordFile = "/persist/secrets/mail/postmaster.hashed-password";
      aliases = [
        "@${domain}"
        "abuse@${domain}"
        "admin@${domain}"
        "info@${domain}"
        "root@${domain}"
      ];
    };
  };
}
