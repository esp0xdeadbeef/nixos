{ config
, lib
, pkgs
, ...
}:
let
  caSecret = "nebula-ca-crt";
  certSecret = "nebula-host-crt";
  keySecret = "nebula-host-key";
  publicIpSecret = "nebula-lighthouse-public-ip";
  lighthouseAddress = "100.64.0.1";
  renderedConfig = "nebula-mesh.json";
  restartUnits = [ "nebula@mesh.service" ];
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
      lighthouse = {
        am_lighthouse = false;
        hosts = [ lighthouseAddress ];
      };
      listen = {
        host = "0.0.0.0";
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

  services.nebula.networks.mesh = {
    enable = true;
    isLighthouse = false;
    lighthouses = [ lighthouseAddress ];
    staticHostMap.${lighthouseAddress} = [ "192.168.3.10:4242" ];
    ca = config.sops.secrets.${caSecret}.path;
    cert = config.sops.secrets.${certSecret}.path;
    key = config.sops.secrets.${keySecret}.path;
    firewall = {
      inbound = firewallRules;
      outbound = firewallRules;
    };
  };

  systemd.services."nebula@mesh" = {
    requires = [ "sops-nix.service" ];
    after = [ "sops-nix.service" ];
    serviceConfig.ExecStart = lib.mkForce "${pkgs.nebula}/bin/nebula -config ${config.sops.templates.${renderedConfig}.path}";
  };
}
