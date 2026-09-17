{ config, lib, profiles, relativeRepo, ... }:

{
  imports = [
    profiles.nixos.web.server
  ];

  # Temporarily force nginx (and therefore the public website) off on s-gamma.
  # Set back to `lib.mkForce true` to restore the site.
  services.nginx.enable = lib.mkForce false;

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
