{ config
, lib
, name
, pkgs
, relativeRepo
, ...
}:

let
  hostName = name;

  runtimeSopsFile = relativeRepo.sourcePath "secrets/s-gamma-runtime.yaml";
  meetHostnameSecretPath = config.sops.secrets."meet/hostname".path;
  meetGroupSecretPath = config.sops.secrets."meet/group_main".path;
  meetAdminPasswordSecretPath = config.sops.secrets."meet/admin_password".path;
  meetAdminHashSecretPath = config.sops.secrets."meet/admin_hash".path;
  meetAdminUsernameSecretPath = config.sops.secrets."meet/admin_username".path;

  networkAddressesUnit = "${hostName}-network-addresses.service";
  certMailUnit = "${hostName}-cert-mail.service";

  meetRuntimeConfigService = "${hostName}-meet-runtime-config";
  meetRuntimeConfigUnit = "${meetRuntimeConfigService}.service";

  runtimeRoot = "/run/${hostName}";
  meetRuntimeDir = "${runtimeRoot}/meet";
  nginxRuntimeConf = "${meetRuntimeDir}/nginx.conf";

  mailTlsFullchainPath = config.sGamma.certs.mail.fullchainPath;
  mailTlsKeyPath = config.sGamma.certs.mail.keyPath;

  renderScript = ./meet-render.sh;

  createRoomScript = ./create-meet-room.py;

  waitForReadableFiles = label: paths: ''
    for path in ${lib.concatMapStringsSep " " lib.escapeShellArg paths}; do
      until [ -r "$path" ]; do
        echo "${label}: waiting for readable file: $path" >&2
        sleep 1
      done
    done
  '';
in
{
  environment.systemPackages = [
    (pkgs.writeShellApplication {
      name = "meet-create-room";
      runtimeInputs = [
        pkgs.bash
        pkgs.python3
      ];
      text = ''
        set -euo pipefail
        secret_dir="/run/secrets/meet"
        groups_dir="/persist/srv/galene/groups"

        meet_hostname="$(tr -d '\r\n' < "$secret_dir/hostname")"
        admin_username="$(tr -d '\r\n' < "$secret_dir/admin_username")"

        export MEET_HOSTNAME="$meet_hostname"
        export MEET_ADMIN_USERNAME="$admin_username"
        export MEET_ADMIN_HASH_FILE="$secret_dir/admin_hash"
        export MEET_GROUPS_DIR="$groups_dir"

        exec ${pkgs.python3}/bin/python3 ${createRoomScript} "$@"
      '';
    })
  ];

  sops.secrets."meet/hostname" = {
    sopsFile = runtimeSopsFile;
    owner = "root";
    group = "root";
    mode = "0400";
    restartUnits = [ meetRuntimeConfigUnit ];
  };

  sops.secrets."meet/group_main" = {
    sopsFile = runtimeSopsFile;
    owner = "root";
    group = "root";
    mode = "0400";
    restartUnits = [ meetRuntimeConfigUnit ];
  };

  sops.secrets."meet/admin_password" = {
    sopsFile = runtimeSopsFile;
    owner = "root";
    group = "galene";
    mode = "0440";
  };

  sops.secrets."meet/admin_hash" = {
    sopsFile = runtimeSopsFile;
    owner = "root";
    group = "galene";
    mode = "0440";
  };

  sops.secrets."meet/admin_username" = {
    sopsFile = runtimeSopsFile;
    owner = "root";
    group = "galene";
    mode = "0440";
  };

  systemd.tmpfiles.rules = [
    "d ${meetRuntimeDir} 0750 nginx nginx -"
    "d /persist/srv/galene 0750 galene galene -"
    "d /persist/srv/galene/groups 0750 galene galene -"
    "d /persist/srv/galene/recordings 0750 galene galene -"
    "d /persist/srv/galene/data 0750 galene galene -"
  ];

  # --------------------------------------------------------------------
  # Galene: single-binary WebRTC SFU. Runs on loopback behind the host's
  # existing SOPS-driven nginx, so it never needs a baked-in hostname and
  # terminates no TLS itself.
  # --------------------------------------------------------------------
  services.galene = {
    enable = true;
    insecure = true;
    httpAddress = "127.0.0.1";
    httpPort = 8443;
    turnAddress = "";
    stateDir = "/persist/srv/galene";
    groupsDir = "/persist/srv/galene/groups";
    recordingsDir = "/persist/srv/galene/recordings";
    dataDir = "/persist/srv/galene/data";
  };

  # The stock module's ProtectSystem=strict only whitelists recordingsDir,
  # so Galene can't write its state under /persist. Extend ReadWritePaths to
  # cover the group, data, and recordings directories.
  systemd.services.galene.serviceConfig.ReadWritePaths = [
    "/persist/srv/galene/groups"
    "/persist/srv/galene/data"
    "/persist/srv/galene/recordings"
  ];

  # The stock module emits `-turn ` with an empty value when turnAddress is
  # empty, which makes galene consume the next flag (`-data`) as the TURN
  # address. Override ExecStart to enable the built-in TURN server on a
  # fixed port (:1194) and restrict media to a fixed UDP range, so clients
  # behind NAT can still relay media through the server.
  systemd.services.galene.serviceConfig.ExecStart = lib.mkForce
    (lib.concatStringsSep " " [
      "${pkgs.galene}/bin/galene"
      "-insecure"
      "-http 127.0.0.1:8443"
      "-turn :1194"
      "-udp-range 30000-30100"
      "-data /persist/srv/galene/data"
      "-groups /persist/srv/galene/groups"
      "-recordings /persist/srv/galene/recordings"
      "-static ${pkgs.galene.static}/static"
    ]);

  # --------------------------------------------------------------------
  # Runtime nginx server block: reads meet/hostname from SOPS and renders
  # the reverse-proxy vhost, mirroring the web/mail runtime-render pattern.
  # --------------------------------------------------------------------
  systemd.services.${meetRuntimeConfigService} = {
    description = "Render ${hostName} meet nginx config from SOPS";
    after = [
      "network-online.target"
      networkAddressesUnit
      certMailUnit
    ];
    wants = [ "network-online.target" ];
    requires = [
      networkAddressesUnit
    ];
    before = [ "nginx.service" ];
    environment = {
      MEET_HOSTNAME_FILE = meetHostnameSecretPath;
      MEET_GROUP_FILE = meetGroupSecretPath;
      MEET_NGINX_CONF = nginxRuntimeConf;
      MEET_GROUPS_DIR = "/persist/srv/galene/groups";
      MEET_DATA_DIR = "/persist/srv/galene/data";
      MEET_MAIL_FULLCHAIN = mailTlsFullchainPath;
      MEET_MAIL_KEY = mailTlsKeyPath;
    };
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      TimeoutStartSec = "5min";
    };
    preStart = waitForReadableFiles "meet runtime" [
      meetHostnameSecretPath
      meetGroupSecretPath
      mailTlsFullchainPath
      mailTlsKeyPath
    ];
    script = "${pkgs.bash}/bin/bash ${renderScript}";
  };

  # appendHttpConfig is types.lines, so it merges with the web profile's.
  services.nginx.appendHttpConfig = ''
    include ${nginxRuntimeConf};
  '';

  systemd.services.nginx = {
    after = [ meetRuntimeConfigUnit ];
    wants = [ meetRuntimeConfigUnit ];
  };

  # Galene serves HTTP on loopback only; external clients reach it through
  # the TLS-terminating nginx vhost on 80/443 (already opened by web.nix).
  # Media and TURN need their own public reachable ports:
  #   - TURN (TCP+UDP) on 1194 for NAT-traversal relay.
  #   - Media (UDP) on the 30000-30100 range.
  networking.firewall.allowedTCPPorts = [ 1194 ];
  networking.firewall.allowedUDPPorts = [ 1194 30000 ];
  networking.firewall.allowedUDPPortRanges = [
    { from = 30000; to = 30100; }
  ];

  # --------------------------------------------------------------------
  # Create-room helper: generates a UUID-named group owned by the SOPS
  # admin user (hashed password from SOPS) with an expiry.
  # --------------------------------------------------------------------
  systemd.services."${hostName}-meet-create-room" = {
    description = "Create a Galene meeting room on ${hostName}";
    environment = {
      MEET_HOSTNAME_FILE = meetHostnameSecretPath;
      MEET_ADMIN_USERNAME_FILE = meetAdminUsernameSecretPath;
      MEET_ADMIN_HASH_FILE = meetAdminHashSecretPath;
      MEET_GROUPS_DIR = "/persist/srv/galene/groups";
    };
    serviceConfig = {
      Type = "oneshot";
    };
    script = ''
      export MEET_HOSTNAME="$(tr -d '\r\n' < "$MEET_HOSTNAME_FILE")"
      export MEET_ADMIN_USERNAME="$(tr -d '\r\n' < "$MEET_ADMIN_USERNAME_FILE")"
      ${pkgs.python3}/bin/python3 ${createRoomScript}
    '';
  };

  # --------------------------------------------------------------------
  # Cleanup timer: remove expired rooms and their persisted recordings/state.
  # --------------------------------------------------------------------
  systemd.services."${hostName}-meet-cleanup" = {
    description = "Clean up expired Galene meeting rooms on ${hostName}";
    environment = {
      MEET_GROUPS_DIR = "/persist/srv/galene/groups";
      MEET_RECORDINGS_DIR = "/persist/srv/galene/recordings";
      MEET_DATA_DIR = "/persist/srv/galene/data";
    };
    path = [
      pkgs.jq
      pkgs.coreutils
    ];
    serviceConfig = {
      Type = "oneshot";
    };
    script = ''
      ${pkgs.bash}/bin/bash ${./cleanup-meet-rooms.sh}
    '';
  };

  systemd.timers."${hostName}-meet-cleanup" = {
    description = "Periodically remove expired Galene meeting rooms";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "1min";
      OnUnitActiveSec = "1h";
      Persistent = true;
    };
  };
}
