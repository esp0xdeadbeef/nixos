{ config, lib, mailboxSets ? null, name, pkgs, ... }:
let
  cfg = config.profiles.web.server;
  hostName = config.networking.hostName or name;
  networkAddressesUnit = cfg.networkAddress.unit;
  networkAddressesService = lib.removeSuffix ".service" networkAddressesUnit;
  nginxRuntimeConfigService = "${hostName}-nginx-runtime-config";
  nginxRuntimeConfigUnit = "${nginxRuntimeConfigService}.service";
  certMailUnit = "${hostName}-cert-mail.service";
  webpageSyncService = "${hostName}-webpage-sync";
  webpageSyncUnit = "${webpageSyncService}.service";
  webpageReloadService = "${hostName}-webpage-reload";
  webpageReloadUnit = "${webpageReloadService}.service";
  webpageService = "${hostName}-webpage";
  webpageUnit = "${webpageService}.service";
  webpageEnvService = "${hostName}-webpage-env";
  webpageEnvUnit = "${webpageEnvService}.service";
  webpageUser = "${hostName}-webpage";
  webpageGroup = webpageUser;

  runtimeRoot = cfg.runtimeRoot;
  mailTlsFullchainPath = cfg.tls.fullchainPath;
  mailTlsKeyPath = cfg.tls.keyPath;
  githubTokenPath = config.sops.secrets.${cfg.githubTokenSecretName}.path;
  webpageRepoUrl = cfg.source.repoUrl;
  webpageRepoBranch = cfg.source.branch;
  webpageSourceDir = cfg.source.checkoutDir;
  webpageRuntimeDir = cfg.runtime.appDir;
  webpageStateDir = cfg.runtime.stateDir;
  webpageRestartMarker = "${runtimeRoot}/webpage-restart-needed";
  webpageEnvDir = "${runtimeRoot}/webpage";
  webpageRenderedEnvPath = "${webpageEnvDir}/env";
  webpageHost = cfg.backend.host;
  webpagePort = cfg.backend.port;

  nginxHttpConfPath = config.sops.secrets.${cfg.secretNames.nginxHttpConf}.path;
  webContactEnvPath = config.sops.secrets.${cfg.secretNames.contactEnv}.path;
  webRedirectEnvPath = config.sops.secrets.${cfg.secretNames.redirectEnv}.path;
  nginxPreviewUsernamePath = config.sops.secrets.${cfg.secretNames.previewUsername}.path;
  nginxPreviewPasswordPath = config.sops.secrets.${cfg.secretNames.previewPassword}.path;
  nginxRuntimeDir = "${runtimeRoot}/nginx";
  nginxHtpasswdPath = "${nginxRuntimeDir}/htpasswd";
  nginxRenderedHttpConfPath = "${nginxRuntimeDir}/http.conf";
  nginxGeneratedMailboxConfPath = "${nginxRuntimeDir}/mailbox-domains.conf";
  emptyMailboxPathList = pkgs.writeText "${hostName}-empty-mailbox-env-paths" "";
  mailboxSetEnvPathsConfig =
    if mailboxSets == null then {
      pathList = emptyMailboxPathList;
      paths = [ ];
    } else
      mailboxSets.mkEnvPaths {
        inherit config lib pkgs;
        name = "${hostName}-web-mailbox-set-env-paths";
        secretRefs = mailboxSets.mailboxSetEnvSecretRefs;
      };
  mailAccountEnvPathsConfig =
    if mailboxSets == null then {
      pathList = emptyMailboxPathList;
      paths = [ ];
    } else
      mailboxSets.mkEnvPaths {
        inherit config lib pkgs;
        name = "${hostName}-web-mail-account-env-paths";
        secretRefs = mailboxSets.mailAccountEnvSecretRefs;
      };
  mailboxSetEnvPaths = mailboxSetEnvPathsConfig.paths;
  mailboxSetEnvPathList = mailboxSetEnvPathsConfig.pathList;
  mailAccountEnvPaths = mailAccountEnvPathsConfig.paths;
  mailAccountEnvPathList = mailAccountEnvPathsConfig.pathList;
  webMailSecretEnvRefs =
    if mailboxSets == null then
      [ ]
    else
      mailboxSets.envSecretRefs;

  waitForReadableFiles = label: paths: ''
    for path in ${lib.concatMapStringsSep " " lib.escapeShellArg paths}; do
      until [ -r "$path" ]; do
        echo "${label}: waiting for readable file: $path" >&2
        sleep 1
      done
    done
  '';



  syncWebpageSource = pkgs.writeShellApplication {
    name = "${hostName}-sync-webpage-source";
    runtimeInputs = [
      pkgs.bash
      pkgs.coreutils
      pkgs.gitMinimal
      pkgs.nix
      pkgs.rsync
    ];
    text = ''
      set -euo pipefail

      repo_url=${lib.escapeShellArg webpageRepoUrl}
      repo_branch=${lib.escapeShellArg webpageRepoBranch}
      token_file=${lib.escapeShellArg githubTokenPath}
      src=${lib.escapeShellArg webpageSourceDir}
      dst=${lib.escapeShellArg webpageRuntimeDir}
      legacy_state=${lib.escapeShellArg webpageStateDir}
      restart_marker=${lib.escapeShellArg webpageRestartMarker}

      has_source_checkout() {
        [ -d "$src/.git" ] \
          && [ -f "$src/deploy/sync-runtime.sh" ] \
          && git -C "$src" rev-parse --verify HEAD >/dev/null 2>&1
      }

      use_existing_checkout_or_fail() {
        if has_source_checkout; then
          echo "webpage remote update failed; using existing PAT-fetched init script" >&2
          return 0
        fi
        echo "webpage clone failed and no existing init script is available" >&2
        exit 1
      }

      if [ ! -s "$token_file" ]; then
        echo "missing GitHub token for webpage clone: $token_file" >&2
        exit 1
      fi

      install -d -m 0755 -o root -g root "$(dirname "$src")"

      askpass="$(mktemp)"
      trap 'rm -f "$askpass"' EXIT
      cat > "$askpass" <<'EOF'
      #!/bin/sh
      case "$1" in
        *Username*) printf '%s\n' x-access-token ;;
        *Password*) tr -d '\r\n' < "$GITHUB_TOKEN_FILE" ;;
        *) printf '\n' ;;
      esac
      EOF
      chmod 0700 "$askpass"

      export GIT_ASKPASS="$askpass"
      export GIT_TERMINAL_PROMPT=0
      export GITHUB_TOKEN_FILE="$token_file"

      if [ -d "$src/.git" ]; then
        if git -C "$src" remote set-url origin "$repo_url" \
          && git -C "$src" fetch --depth=1 origin "$repo_branch" \
          && git -C "$src" checkout -B "$repo_branch" FETCH_HEAD \
          && git -C "$src" reset --hard FETCH_HEAD \
          && git -C "$src" clean -fdx; then
          :
        else
          use_existing_checkout_or_fail
        fi
      else
        tmp="$(mktemp -d "$(dirname "$src")/source.tmp.XXXXXX")"
        trap 'rm -f "$askpass"; rm -rf "$tmp"' EXIT
        if git clone --depth=1 --branch "$repo_branch" "$repo_url" "$tmp/repo"; then
          rm -rf "$src"
          mv "$tmp/repo" "$src"
          rmdir "$tmp"
        else
          use_existing_checkout_or_fail
        fi
      fi

      has_source_checkout || use_existing_checkout_or_fail
      init_script="$src/deploy/sync-runtime.sh"
      if [ ! -x "$init_script" ]; then
        echo "PAT-fetched webpage init script is not executable: $init_script" >&2
        exit 1
      fi

      WEBPAGE_SOURCE_DIR="$src" \
      WEBPAGE_RUNTIME_DIR="$dst" \
      WEBPAGE_LEGACY_STATE_DIR="$legacy_state" \
      WEBPAGE_RESTART_MARKER="$restart_marker" \
      WEBPAGE_USER=${lib.escapeShellArg webpageUser} \
      WEBPAGE_GROUP=${lib.escapeShellArg webpageGroup} \
        ${pkgs.bash}/bin/bash "$init_script"
    '';
  };
in
{
  options.profiles.web.server = {
    enable = lib.mkEnableOption "SOPS-backed nginx webpage server";

    sopsFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = "SOPS file containing web runtime secrets.";
    };

    runtimeRoot = lib.mkOption {
      type = lib.types.str;
      default = "/run/${config.networking.hostName}";
      description = "Runtime root for generated nginx and webpage files.";
    };

    githubTokenSecretName = lib.mkOption {
      type = lib.types.str;
      default = "gh-token";
      description = "SOPS secret name containing the GitHub token used for runtime source sync.";
    };

    source = {
      repoUrl = lib.mkOption {
        type = lib.types.str;
        description = "Git repository URL for the runtime webpage source.";
      };

      branch = lib.mkOption {
        type = lib.types.str;
        default = "main";
        description = "Git branch to sync at runtime.";
      };

      checkoutDir = lib.mkOption {
        type = lib.types.str;
        default = "/persist/srv/www/source";
        description = "Persistent checkout directory for the webpage source.";
      };
    };

    runtime = {
      appDir = lib.mkOption {
        type = lib.types.str;
        default = "/persist/srv/www/app";
        description = "Runtime directory copied from the webpage checkout.";
      };

      stateDir = lib.mkOption {
        type = lib.types.str;
        default = "/persist/srv/www/state";
        description = "Legacy state directory migrated into the persistent runtime app.";
      };
    };

    backend = {
      host = lib.mkOption {
        type = lib.types.str;
        default = "127.0.0.1";
        description = "Address the webpage backend listens on.";
      };

      port = lib.mkOption {
        type = lib.types.ints.between 1 65535;
        default = 8080;
        description = "Port the webpage backend listens on.";
      };

      corsAllowOrigin = lib.mkOption {
        type = lib.types.str;
        default = "*";
        description = "CORS_ALLOW_ORIGIN passed to the webpage backend.";
      };
    };

    networkAddress.unit = lib.mkOption {
      type = lib.types.str;
      default = "${config.networking.hostName}-network-addresses.service";
      description = "Systemd unit that renders or applies runtime network address data.";
    };

    tls = {
      fullchainPath = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "TLS fullchain path used by nginx generated virtual hosts.";
      };

      keyPath = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "TLS private key path used by nginx generated virtual hosts.";
      };
    };

    secretNames = {
      nginxHttpConf = lib.mkOption {
        type = lib.types.str;
        default = "web/nginx/http_conf";
        description = "SOPS secret key containing additional nginx HTTP config.";
      };

      contactEnv = lib.mkOption {
        type = lib.types.str;
        default = "web/contact/env";
        description = "SOPS secret key containing webpage contact env.";
      };

      redirectEnv = lib.mkOption {
        type = lib.types.str;
        default = "web/redirects/env";
        description = "SOPS secret key containing webpage redirect env.";
      };

      previewUsername = lib.mkOption {
        type = lib.types.str;
        default = "web/preview/username";
        description = "SOPS secret key containing preview basic-auth username.";
      };

      previewPassword = lib.mkOption {
        type = lib.types.str;
        default = "web/preview/password";
        description = "SOPS secret key containing preview basic-auth password.";
      };
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = mailboxSets != null;
        message = "profiles.web.server requires profiles.nixos.mail.mailbox-sets to be imported and enabled.";
      }
      {
        assertion = cfg.sopsFile != null;
        message = "profiles.web.server.sopsFile must be set.";
      }
      {
        assertion = cfg.source.repoUrl != "";
        message = "profiles.web.server.source.repoUrl must be set.";
      }
      {
        assertion = cfg.tls.fullchainPath != null && cfg.tls.keyPath != null;
        message = "profiles.web.server.tls.fullchainPath and keyPath must be set.";
      }
    ];

    users.groups.${webpageGroup} = { };
    users.users.${webpageUser} = {
      isSystemUser = true;
      group = webpageGroup;
      description = "Isolated ${hostName} webpage backend";
    };

    sops.secrets =
      {
        ${cfg.secretNames.nginxHttpConf} = {
          sopsFile = cfg.sopsFile;
          owner = "root";
          group = "root";
          mode = "0400";
          restartUnits = [
            nginxRuntimeConfigUnit
            "nginx.service"
          ];
        };

        ${cfg.secretNames.contactEnv} = {
          sopsFile = cfg.sopsFile;
          owner = "root";
          group = "root";
          mode = "0400";
          restartUnits = [
            nginxRuntimeConfigUnit
            "nginx.service"
            webpageEnvUnit
            webpageUnit
          ];
        };

        ${cfg.secretNames.redirectEnv} = {
          sopsFile = cfg.sopsFile;
          owner = "root";
          group = "root";
          mode = "0400";
          restartUnits = [
            nginxRuntimeConfigUnit
            "nginx.service"
            webpageEnvUnit
            webpageUnit
          ];
        };

        ${cfg.secretNames.previewUsername} = {
          sopsFile = cfg.sopsFile;
          owner = "root";
          group = "root";
          mode = "0400";
          restartUnits = [
            nginxRuntimeConfigUnit
            "nginx.service"
          ];
        };

        ${cfg.secretNames.previewPassword} = {
          sopsFile = cfg.sopsFile;
          owner = "root";
          group = "root";
          mode = "0400";
          restartUnits = [
            nginxRuntimeConfigUnit
            "nginx.service"
          ];
        };
      }
      // builtins.listToAttrs (
        map
          (secret: {
            inherit (secret) name;
            value = {
              inherit (secret) key sopsFile;
              owner = "root";
              group = "root";
              mode = "0400";
              restartUnits = [
                certMailUnit
                nginxRuntimeConfigUnit
                "nginx.service"
                webpageEnvUnit
                webpageUnit
              ];
            };
          })
          webMailSecretEnvRefs
      );

    systemd.tmpfiles.rules = [
      "d ${runtimeRoot} 0755 root root -"
      "d ${nginxRuntimeDir} 0750 nginx nginx -"
      "d ${webpageEnvDir} 0750 root ${webpageGroup} -"
      "d /persist/srv 0755 root root -"
      "d /persist/srv/www 0755 root root -"
      "d ${webpageSourceDir} 0755 root root -"
      "d ${webpageRuntimeDir} 0755 root root -"
      "z /var/lib/acme 0755 root root -"
      "d /var/log/nginx 0750 nginx nginx -"
      "z /var/log/nginx 0750 nginx nginx -"
      "z /var/log/nginx/access.log 0640 nginx nginx -"
      "z /var/log/nginx/error.log 0640 nginx nginx -"
    ];

    systemd.services.${networkAddressesService}.before = [ "nginx.service" ];

    systemd.services.${nginxRuntimeConfigService} = {
      description = "Prepare ${hostName} nginx runtime files from SOPS";
      after = [ webpageSyncUnit ];
      before = [ "nginx.service" ];
      requiredBy = [ "nginx.service" ];
      path = [
        pkgs.bash
        pkgs.coreutils
        pkgs.gawk
        pkgs.gnugrep
        pkgs.openssl
      ];
      environment = {
        WEB_NGINX_RAW_CONF = nginxHttpConfPath;
        WEB_CONTACT_ENV = webContactEnvPath;
        WEB_REDIRECT_ENV = webRedirectEnvPath;
        WEB_NGINX_RENDERED_CONF = nginxRenderedHttpConfPath;
        WEB_NGINX_GENERATED_MAILBOX_CONF = nginxGeneratedMailboxConfPath;
        WEB_PREVIEW_USERNAME_FILE = nginxPreviewUsernamePath;
        WEB_PREVIEW_PASSWORD_FILE = nginxPreviewPasswordPath;
        WEB_MAILBOX_SET_ENV_PATH_LIST = mailboxSetEnvPathList;
        WEB_TLS_FULLCHAIN = mailTlsFullchainPath;
        WEB_TLS_KEY = mailTlsKeyPath;
        WEB_NGINX_RUNTIME_DIR = nginxRuntimeDir;
        WEB_NGINX_HTPASSWD = nginxHtpasswdPath;
        WEBPAGE_UPSTREAM = "http://${webpageHost}:${toString webpagePort}";
        WEB_NGINX_USER = "nginx";
        WEB_NGINX_GROUP = "nginx";
      };
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        TimeoutStartSec = "5min";
        ExecStart = "${pkgs.bash}/bin/bash ${webpageSourceDir}/deploy/prepare-nginx-runtime.sh";
      };
      preStart = waitForReadableFiles "nginx runtime" [
        "${webpageSourceDir}/deploy/prepare-nginx-runtime.sh"
        nginxHttpConfPath
        nginxPreviewUsernamePath
        nginxPreviewPasswordPath
        webContactEnvPath
        webRedirectEnvPath
        mailTlsFullchainPath
        mailTlsKeyPath
      ] + waitForReadableFiles "nginx runtime mailbox sets" mailboxSetEnvPaths;
    };

    systemd.services.${webpageSyncService} = {
      description = "Sync ${hostName} webpage source from GitHub";
      after = [ "network-online.target" ];
      before = [ webpageUnit ];
      wants = [ "network-online.target" ];
      requiredBy = [ webpageUnit ];
      wantedBy = [ "multi-user.target" ];
      unitConfig.OnSuccess = [ webpageReloadUnit ];
      serviceConfig = {
        Type = "oneshot";
      };
      preStart = waitForReadableFiles "webpage sync" [
        githubTokenPath
      ];
      script = "${lib.getExe syncWebpageSource}";
    };

    systemd.services.${webpageReloadService} = {
      description = "Reload ${hostName} webpage after source sync";
      after = [ webpageSyncUnit ];
      path = [
        pkgs.bash
        pkgs.coreutils
        pkgs.systemd
      ];
      environment = {
        WEBPAGE_RESTART_MARKER = webpageRestartMarker;
        WEBPAGE_SYSTEMD_UNIT = webpageUnit;
        WEBPAGE_REFRESH_UNITS = "${webpageEnvUnit} ${nginxRuntimeConfigUnit}";
        WEBPAGE_RELOAD_UNITS = "nginx.service";
      };
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${pkgs.bash}/bin/bash ${webpageSourceDir}/deploy/reload-after-sync.sh";
      };
    };

    systemd.services.${webpageEnvService} = {
      description = "Prepare ${hostName} webpage environment from SOPS";
      after = [ webpageSyncUnit ];
      before = [ webpageUnit ];
      requiredBy = [ webpageUnit ];
      path = [
        pkgs.bash
        pkgs.coreutils
        pkgs.gnused
      ];
      environment = {
        WEB_CONTACT_ENV = webContactEnvPath;
        WEB_REDIRECT_ENV = webRedirectEnvPath;
        WEB_MAILBOX_SET_ENV_PATH_LIST = mailboxSetEnvPathList;
        WEB_MAIL_ACCOUNT_ENV_PATH_LIST = mailAccountEnvPathList;
        WEBPAGE_ENV_DIR = webpageEnvDir;
        WEBPAGE_RENDERED_ENV = webpageRenderedEnvPath;
        WEBPAGE_USER = webpageUser;
        WEBPAGE_GROUP = webpageGroup;
        WEBPAGE_RUNTIME_OWNER = "root";
      };
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        TimeoutStartSec = "2min";
        ExecStart = "${pkgs.bash}/bin/bash ${webpageSourceDir}/deploy/render-environment.sh";
      };
      preStart = waitForReadableFiles "webpage env" (
        [
          "${webpageSourceDir}/deploy/render-environment.sh"
          webContactEnvPath
          webRedirectEnvPath
        ]
        ++ mailboxSetEnvPaths
        ++ mailAccountEnvPaths
      );
    };

    systemd.timers.${webpageSyncService} = {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec = "5min";
        OnUnitActiveSec = "5min";
        AccuracySec = "1min";
        Persistent = true;
      };
    };

    systemd.services.${webpageService} = {
      description = "Run ${hostName} webpage backend";
      after = [
        "network.target"
        webpageSyncUnit
        webpageEnvUnit
      ];
      requires = [
        webpageSyncUnit
        webpageEnvUnit
      ];
      wantedBy = [ "multi-user.target" ];
      environment = {
        HOST = webpageHost;
        PORT = toString webpagePort;
        WEB_ROOT = "webpagina";
        CORS_ALLOW_ORIGIN = cfg.backend.corsAllowOrigin;
      };
      serviceConfig = {
        User = webpageUser;
        Group = webpageGroup;
        WorkingDirectory = webpageRuntimeDir;
        EnvironmentFile = webpageRenderedEnvPath;
        ExecStart = "${webpageRuntimeDir}/.backend-runtime/bin/webpage-backend ./run-server.py";
        Restart = "always";
        RestartSec = "5s";
      };
      preStart = waitForReadableFiles "web contact" [
        webpageRenderedEnvPath
        "${webpageRuntimeDir}/.backend-runtime/bin/webpage-backend"
      ];
    };

    services.nginx = {
      enable = true;
      recommendedGzipSettings = true;
      recommendedOptimisation = true;
      recommendedProxySettings = true;
      recommendedTlsSettings = true;
      appendHttpConfig = ''
        log_format managed_web_host_combined '$remote_addr host=$host server=$server_name '
          'request="$request" status=$status bytes=$body_bytes_sent '
          'location="$sent_http_location" auth="$sent_http_www_authenticate" '
          'referer="$http_referer" user_agent="$http_user_agent"';
        access_log /var/log/nginx/access.log managed_web_host_combined;

        map $uri $managed_web_preview_path_realm {
          default "preview";
          /.well-known/security.txt off;
          /security.txt off;
        }

        auth_basic $managed_web_preview_realm;
        auth_basic_user_file ${nginxHtpasswdPath};

        include ${nginxRenderedHttpConfPath};
      '';
    };

    systemd.services.nginx = {
      after = [
        networkAddressesUnit
        nginxRuntimeConfigUnit
        webpageUnit
      ];
      requires = [
        networkAddressesUnit
        nginxRuntimeConfigUnit
        webpageUnit
      ];
      preStart = lib.mkBefore (waitForReadableFiles "nginx" [
        nginxRenderedHttpConfPath
        nginxGeneratedMailboxConfPath
        nginxHtpasswdPath
      ]);
      serviceConfig.TimeoutStartSec = "5min";
    };

    networking.firewall.allowedTCPPorts = [
      80
      443
    ];
  };
}
