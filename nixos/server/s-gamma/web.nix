{ config, lib, profiles, relativeRepo, ... }:

{
  imports = [
    profiles.nixos.web.server
  ];

  # Public content is gated while the UWV situation is unresolved, but nginx
  # itself stays up: it keeps :80 available for ACME HTTP-01 and still holds
  # the :443 listener, so certificate issuance and renewal do not depend on
  # the website being published.
  #
  # The maintenance vhost answers every non-ACME request with 503. The backend
  # keeps running but is no longer reachable from outside through nginx.
  #
  # Set `content.enable = true` to publish the site again.
  profiles.web.server.content.enable = false;

  # Belt and braces: hand the backend MAINTENANCE_MODE=1 so that a future
  # backend revision can refuse site content even if reached directly. Nothing
  # in the current site backend reads this yet, so today the 503 is enforced by
  # the maintenance vhost above, not by the backend.
  systemd.services.${config.networking.hostName + "-webpage"}.environment.MAINTENANCE_MODE = "1";

  profiles.web.server = {
    enable = true;
    sopsFile = relativeRepo.sourcePath "secrets/s-gamma-runtime.yaml";
    githubTokenSecretName = "gh-token";

    source = {
      repoUrl = "https://github.com/esp0xdeadbeef/www.git";
      branch = "main";
      checkoutDir = "/persist/srv/www/source";
    };

    runtime.appDir = "/persist/srv/www/app";

    networkAddress.unit = "${config.networking.hostName}-network-addresses.service";

    tls = {
      fullchainPath = config.sGamma.certs.mail.fullchainPath;
      keyPath = config.sGamma.certs.mail.keyPath;
    };
  };
}
