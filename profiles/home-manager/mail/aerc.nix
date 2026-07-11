{ config, lib, outPath, pkgs, ... }:
let
  mailAccounts = import ../../mail/accounts.nix {
    secretsRoot = "${outPath}/secrets";
  };
  accountNames = mailAccounts.clientAccountNames;
  accountSecretRefs = lib.flatten (
    map
      (
        account:
        map (field: mailAccounts.secretRef account field) mailAccounts.clientFields
      )
      accountNames
  );
  placeholder = name: config.sops.placeholder.${name};
  secretPath = name: config.sops.secrets.${name}.path;
  mkSecret = secret: {
    inherit (secret) name;
    value.sopsFile = secret.sopsFile;
  };
  mkAccount = account: ''
    [${placeholder (mailAccounts.secretName account "label")}]
    from = ${placeholder (mailAccounts.secretName account "from")}
    source = ${placeholder (mailAccounts.secretName account "source")}
    source-cred-cmd = ${pkgs.coreutils}/bin/cat ${secretPath (mailAccounts.secretName account "password")}
    outgoing = ${placeholder (mailAccounts.secretName account "outgoing")}
    outgoing-cred-cmd = ${pkgs.coreutils}/bin/cat ${secretPath (mailAccounts.secretName account "password")}
    default = INBOX
    copy-to = Sent
    postpone = Drafts
  '';
in
{
  programs.aerc = {
    enable = true;
  };

  sops.secrets = builtins.listToAttrs (map mkSecret accountSecretRefs);

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
