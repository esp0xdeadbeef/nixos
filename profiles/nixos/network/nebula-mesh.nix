{ config
, pkgs
, ...
}:
let
  caSecret = "nebula-ca-crt";
  certSecret = "nebula-host-crt";
  keySecret = "nebula-host-key";
  publicIpSecret = "nebula-lighthouse-public-ip";
  cobaltPublicIpSecret = "nebula-cobalt-lighthouse-public-ip";
  lighthouseAddress = "100.64.0.1";
  cobaltLighthouseAddress = "100.64.0.2";
  renderedConfig = "nebula-mesh.json";
  serviceName = "nebula-mesh";
  restartUnits = [ "${serviceName}.service" ];
  # Temporary while clients are being onboarded and mesh paths are tested.
  firewallRules = [
    {
      host = "any";
      port = "any";
      proto = "any";
    }
  ];
in
{
  environment.systemPackages = [ pkgs.nebula ];

  sops.secrets = {
    ${caSecret} = {
      owner = "nebula-mesh";
      group = "nebula-mesh";
      mode = "0440";
      inherit restartUnits;
    };
    ${certSecret} = {
      owner = "nebula-mesh";
      group = "nebula-mesh";
      mode = "0440";
      inherit restartUnits;
    };
    ${keySecret} = {
      owner = "nebula-mesh";
      group = "nebula-mesh";
      mode = "0440";
      inherit restartUnits;
    };
    ${publicIpSecret}.restartUnits = restartUnits;
    ${cobaltPublicIpSecret}.restartUnits = restartUnits;
  };

  sops.templates.${renderedConfig} = {
    content = builtins.toJSON {
      pki = {
        ca = config.sops.secrets.${caSecret}.path;
        cert = config.sops.secrets.${certSecret}.path;
        key = config.sops.secrets.${keySecret}.path;
      };
      static_host_map.${lighthouseAddress} = [
        "192.168.3.10:4242"
        "${config.sops.placeholder.${publicIpSecret}}:4242"
      ];
      static_host_map.${cobaltLighthouseAddress} = [
        "10.2.20.2:4242"
        "${config.sops.placeholder.${cobaltPublicIpSecret}}:4242"
      ];
      lighthouse = {
        am_lighthouse = false;
        hosts = [ lighthouseAddress cobaltLighthouseAddress ];
      };
      relay = {
        am_relay = false;
        relays = [ lighthouseAddress cobaltLighthouseAddress ];
        use_relays = true;
      };
      listen = {
        host = "[::]";
        port = 0;
      };
      tun = {
        disabled = false;
        dev = "nebula.mesh";
      };
      firewall = {
        inbound = firewallRules;
        outbound = firewallRules;
      };
    };
    owner = "nebula-mesh";
    group = "nebula-mesh";
    mode = "0440";
  };

  users = {
    groups.${serviceName} = { };
    users.${serviceName} = {
      description = "Nebula mesh service user";
      group = serviceName;
      isSystemUser = true;
    };
  };

  systemd.services.${serviceName} = {
    description = "Nebula VPN service for mesh";
    wantedBy = [ "multi-user.target" ];
    wants = [ "basic.target" ];
    after = [
      "basic.target"
      "network.target"
    ];
    before = [ "sshd.service" ];
    unitConfig.StartLimitIntervalSec = 0;
    serviceConfig = {
      Type = "notify";
      Restart = "always";
      ExecStartPre = "${pkgs.nebula}/bin/nebula -test -config ${config.sops.templates.${renderedConfig}.path}";
      ExecStart = "${pkgs.nebula}/bin/nebula -config ${config.sops.templates.${renderedConfig}.path}";
      ExecReload = "${pkgs.coreutils}/bin/kill -s HUP $MAINPID";
      UMask = "0027";
      CapabilityBoundingSet = "CAP_NET_ADMIN";
      AmbientCapabilities = "CAP_NET_ADMIN";
      LockPersonality = true;
      NoNewPrivileges = true;
      PrivateDevices = false;
      DeviceAllow = "/dev/net/tun rw";
      DevicePolicy = "closed";
      PrivateTmp = true;
      PrivateUsers = false;
      ProtectClock = true;
      ProtectControlGroups = true;
      ProtectHome = true;
      ProtectHostname = true;
      ProtectKernelLogs = true;
      ProtectKernelModules = true;
      ProtectKernelTunables = true;
      ProtectProc = "invisible";
      ProtectSystem = true;
      RestrictNamespaces = true;
      RestrictSUIDSGID = true;
      User = serviceName;
      Group = serviceName;
    };
  };
}
