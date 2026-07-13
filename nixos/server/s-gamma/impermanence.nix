{ profiles, ... }:

{
  imports = [
    profiles.nixos.impermanence.minimal
  ];

  profiles.impermanence.minimal = {
    enable = true;
    extraSystemDirectories = [
      "/var/dkim"
      "/var/lib/acme"
      "/var/lib/dovecot"
      "/var/lib/knot"
      "/var/lib/postfix"
      "/var/lib/rspamd"
      "/var/spool/postfix"
      "/var/vmail"
    ];
  };
}
