{ secretsRoot }:
let
  accounts = {
    postmaster = {
      serverId = "ACCOUNT_001";
      client = false;
    };
    user-001 = {
      serverId = "ACCOUNT_002";
      client = true;
    };
    mailbox-001 = {
      serverId = "ACCOUNT_003";
      client = false;
    };
    no-reply = {
      serverId = "ACCOUNT_NOREPLY";
      client = false;
    };
  };

  accountNames = [
    "postmaster"
    "user-001"
    "mailbox-001"
    "no-reply"
  ];

  clientAccountNames = builtins.filter (account: accounts.${account}.client) accountNames;

  secretName = account: field: "mail/accounts/${account}/${field}";
  accountSecret = account: "mail/accounts/${account}";
  sopsFile = account: "${secretsRoot}/mail-account-${account}.yaml";
  secretRef = account: field: {
    name = secretName account field;
    sopsFile = sopsFile account;
  };
in
{
  inherit
    accountNames
    accountSecret
    accounts
    clientAccountNames
    secretName
    secretRef
    sopsFile
    ;

  serverAccountNames = accountNames;

  serverFields = [
    "username"
    "password"
    "aliases"
  ];

  clientFields = [
    "label"
    "from"
    "source"
    "outgoing"
    "password"
  ];
}
