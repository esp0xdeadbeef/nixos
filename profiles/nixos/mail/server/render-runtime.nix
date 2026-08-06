{ dovecotRuntimeDir
, hostName
, lib
, mailAccountEnvPathList
, mailEnvPath
, mailboxSetEnvPathList
, mailTlsFullchainPath
, mailTlsKeyPath
, networkAddressEnvPath
, pkgs
, postfixRuntimeDir
, sharedSenderLoginMap
}:

pkgs.writeShellApplication {
  name = "${hostName}-render-mail-runtime";
  runtimeInputs = [
    pkgs.coreutils
    pkgs.dovecot
    pkgs.gawk
    pkgs.postfix
    pkgs.python3
  ];
  text = ''
    exec ${lib.getExe pkgs.python3} ${
      builtins.path {
        path = ./render-runtime.py;
        name = "render-runtime.py";
      }
    } \
      --mail-env ${lib.escapeShellArg mailEnvPath} \
      --network-env ${lib.escapeShellArg networkAddressEnvPath} \
      --mailbox-set-env-list ${lib.escapeShellArg mailboxSetEnvPathList} \
      --mail-account-env-list ${lib.escapeShellArg mailAccountEnvPathList} \
      --postfix-dir ${lib.escapeShellArg postfixRuntimeDir} \
      --dovecot-dir ${lib.escapeShellArg dovecotRuntimeDir} \
      --tls-fullchain ${lib.escapeShellArg mailTlsFullchainPath} \
      --tls-key ${lib.escapeShellArg mailTlsKeyPath} \
      --shared-sender-login-map ${lib.escapeShellArg sharedSenderLoginMap}
  '';
}
