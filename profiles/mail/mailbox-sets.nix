{ mailAccountNames ? null
, mailboxSetNames ? null
, secretsRoot
}:
let
  hasPrefix = prefix: value:
    builtins.substring 0 (builtins.stringLength prefix) value == prefix;

  hasSuffix = suffix: value:
    let
      suffixLength = builtins.stringLength suffix;
      valueLength = builtins.stringLength value;
    in
    valueLength >= suffixLength
    && builtins.substring (valueLength - suffixLength) suffixLength value == suffix;

  removeSuffix = suffix: value:
    builtins.substring 0 ((builtins.stringLength value) - (builtins.stringLength suffix)) value;

  secretNameFromFile = fileName:
    if hasSuffix ".yaml" fileName then
      removeSuffix ".yaml" fileName
    else
      removeSuffix ".yml" fileName;

  isSecretFile = prefix: fileName:
    hasPrefix prefix fileName
    && (hasSuffix ".yaml" fileName || hasSuffix ".yml" fileName);

  discoverSecretNames = prefix:
    if builtins.pathExists secretsRoot then
      builtins.sort builtins.lessThan
        (
          map secretNameFromFile (
            builtins.filter (isSecretFile prefix) (builtins.attrNames (builtins.readDir secretsRoot))
          )
        )
    else
      [ ];

  resolvedMailboxSetNames =
    if mailboxSetNames == null then
      discoverSecretNames "mailbox-"
    else
      mailboxSetNames;

  resolvedMailAccountNames =
    if mailAccountNames == null then
      discoverSecretNames "mail-account-"
    else
      mailAccountNames;

  mailboxSetSopsFile = mailboxSet: "${secretsRoot}/${mailboxSet}.yaml";
  mailboxSetEnvSecretName = mailboxSet: "mail/mailbox-sets/${mailboxSet}/env";
  mailboxSetEnvSecretRef = mailboxSet: {
    name = mailboxSetEnvSecretName mailboxSet;
    sopsFile = mailboxSetSopsFile mailboxSet;
    key = "mailbox/env";
  };

  mailAccountSopsFile = account: "${secretsRoot}/${account}.yaml";
  mailAccountEnvSecretName = account: "mail/accounts/${account}/env";
  mailAccountEnvSecretRef = account: {
    name = mailAccountEnvSecretName account;
    sopsFile = mailAccountSopsFile account;
    key = "mail/account/env";
  };
in
rec {
  inherit
    mailAccountEnvSecretName
    mailAccountEnvSecretRef
    mailAccountSopsFile
    mailboxSetEnvSecretName
    mailboxSetEnvSecretRef
    mailboxSetSopsFile
    ;

  names = resolvedMailboxSetNames;
  mailboxSetNames = resolvedMailboxSetNames;
  mailAccountNames = resolvedMailAccountNames;

  mailboxSetEnvSecretRefs = map mailboxSetEnvSecretRef mailboxSetNames;
  mailAccountEnvSecretRefs = map mailAccountEnvSecretRef mailAccountNames;
  envSecretRefs = mailboxSetEnvSecretRefs ++ mailAccountEnvSecretRefs;

  mkSopsSecrets =
    { restartUnits ? [ ]
    , secretRefs ? envSecretRefs
    }:
    builtins.listToAttrs (
      map
        (
          secret:
          {
            inherit (secret) name;
            value = {
              inherit (secret) key sopsFile;
            } // (if restartUnits == [ ] then { } else { inherit restartUnits; });
          }
        )
        secretRefs
    );

  mkEnvPaths =
    { config
    , lib
    , name
    , pkgs
    , secretRefs ? mailboxSetEnvSecretRefs
    }:
    let
      pathsByName = builtins.listToAttrs (
        map
          (secret: {
            inherit (secret) name;
            value = config.sops.secrets.${secret.name}.path;
          })
          secretRefs
      );
      pathList = pkgs.writeText name (
        (lib.concatStringsSep "\n" (
          lib.mapAttrsToList
            (
              secretName: path: "${secretName}=${path}"
            )
            pathsByName
        ))
        + "\n"
      );
    in
    {
      inherit pathList pathsByName;
      paths = builtins.attrValues pathsByName;
    };
}
