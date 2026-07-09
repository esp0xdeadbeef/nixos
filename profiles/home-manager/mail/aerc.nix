{ config, lib, outPath, pkgs, ... }:
let
  mailClientSopsFile = "${outPath}/secrets/mail-client.yaml";
  accountNames = [
    "account_001"
  ];
  sharedSecretKeys = [
    "mail_client/shared/password"
  ];
  accountSecretKeys = account:
    map (field: "mail_client/${account}/${field}") [
      "label"
      "from"
      "source"
      "outgoing"
    ];
  secretKeys = sharedSecretKeys ++ lib.flatten (map accountSecretKeys accountNames);
  placeholder = name: config.sops.placeholder.${name};
  secretPath = name: config.sops.secrets.${name}.path;
  mkSecret = name: {
    inherit name;
    value.sopsFile = mailClientSopsFile;
  };
  mkAccount = account: ''
    [${placeholder "mail_client/${account}/label"}]
    from = ${placeholder "mail_client/${account}/from"}
    source = ${placeholder "mail_client/${account}/source"}
    source-cred-cmd = ${pkgs.coreutils}/bin/cat ${secretPath "mail_client/shared/password"}
    outgoing = ${placeholder "mail_client/${account}/outgoing"}
    outgoing-cred-cmd = ${pkgs.coreutils}/bin/cat ${secretPath "mail_client/shared/password"}
    default = INBOX
    copy-to = Sent
    postpone = Drafts
  '';
in
{
  programs.aerc = {
    enable = true;
  };

  sops.secrets = builtins.listToAttrs (map mkSecret secretKeys);

  sops.templates.aercAccounts = {
    mode = "0400";
    content = lib.concatStringsSep "\n" ([
      "# Generated from SOPS by Home Manager."
      "# The source/outgoing URIs intentionally exclude passwords."
    ] ++ map mkAccount accountNames);
  };

  xdg.configFile."aerc/accounts.conf".source =
    config.lib.file.mkOutOfStoreSymlink config.sops.templates.aercAccounts.path;
}
