{
  lib,
  pkgs,
  nebulaRendererCli,
  renderedContainers ? { },
  runtimeSecretNames ? [ ],
}:

let
  containerName = "nixos-router-core-nebula";
  serviceModule = {
    systemd.services.s-router-nebula-render-node = {
      description = "Render this Nebula node from CPM with network-renderer-nebula";
      path = with pkgs; [
        coreutils
        glibc
        gawk
        iputils
        iproute2
        nebula
        python3
      ];
      serviceConfig = {
        Type = "simple";
        WorkingDirectory = "/root";
      };
      script = ''
        set -euo pipefail
        test -r /etc/network-artifacts/control-plane.json
        test -r /etc/network-artifacts/inventory.json
        test -r /persist/nebula-runtime/profiles/nixos-router-core-nebula/ca.crt
        test -r /persist/nebula-runtime/profiles/nixos-router-core-nebula/nixos-router-core-nebula.crt
        test -r /persist/nebula-runtime/profiles/nixos-router-core-nebula/nixos-router-core-nebula.key

        probe4="$(printf '%s.%s.%s.%s' 1 1 1 1)"
        ping -4 -c3 -W2 "$probe4"

        rm -rf /run/s-router-nebula-render-node
        install -d -m 0700 /run/s-router-nebula-render-node
        ${nebulaRendererCli}/bin/network-renderer-nebula \
          render-node \
          --cpm /etc/network-artifacts/control-plane.json \
          --inventory /etc/network-artifacts/inventory.json \
          --node nixos-router-core-nebula \
          --out /run/s-router-nebula-render-node

        python3 - /run/s-router-nebula-render-node/runtime-node.json /run/s-router-nebula-render-node/runtime.json <<'PY'
        import ipaddress
        import json
        import sys
        from pathlib import Path

        source = Path(sys.argv[1])
        target = Path(sys.argv[2])
        payload = json.loads(source.read_text(encoding="utf-8"))
        node_name = payload["nodeName"]
        runtime = payload["runtimeNode"]
        settings = dict(runtime.get("nebulaNetwork", {}).get("settings", {}))

        def read_endpoint(path):
            value = Path(path).read_text(encoding="utf-8").strip()
            if not value:
                raise SystemExit(f"empty endpoint secret: {path}")
            if "/" in value:
                network = ipaddress.ip_network(value, strict=False)
                if network.prefixlen < network.max_prefixlen:
                    return str(network.network_address + 1)
                return str(network.network_address)
            return value.split("/", 1)[0]

        def endpoint(value, port):
            return f"[{value}]:{port}" if ":" in value else f"{value}:{port}"

        static_map = dict(runtime.get("staticHostMap", {}))
        for overlay_ip, specs in runtime.get("staticHostMapSecretEndpoints", {}).items():
            static_map[overlay_ip] = [
                endpoint(read_endpoint(spec["sourceFile"]), str(spec.get("port", runtime.get("service", {}).get("port", 4242))))
                for spec in specs
                if spec.get("sourceFile")
            ]

        firewall = settings.get("nebulaFirewallRules", {"inbound": [], "outbound": []})
        unsafe_routes = list(settings.get("tun", {}).get("unsafe_routes", []))

        for spec in runtime.get("dynamicFirewallCidrs", []):
            source_file = spec.get("sourceFile")
            if not source_file:
                continue
            cidr = str(ipaddress.ip_network(Path(source_file).read_text(encoding="utf-8").strip(), strict=False))
            rule = {"host": "any", "local_cidr": cidr, "port": "any", "proto": "any"}
            for direction in ("inbound", "outbound"):
                if rule not in firewall.setdefault(direction, []):
                    firewall[direction].insert(0, rule)

        for spec in runtime.get("dynamicUnsafeRoutes", []):
            source_file = spec.get("sourceFile")
            if not source_file:
                continue
            cidr = str(ipaddress.ip_network(Path(source_file).read_text(encoding="utf-8").strip(), strict=False))
            route = {"route": cidr, "mtu": 1280 if ":" in cidr else 1200, "install": True}
            via = spec.get("via6") or spec.get("via4") or spec.get("via")
            if via:
                route["via"] = via
            if route not in unsafe_routes:
                unsafe_routes.append(route)

        service = runtime.get("service", {})
        lighthouse = runtime.get("lighthouse", {})
        lighthouse_ips = lighthouse.get("overlayIps", [])
        is_lighthouse = lighthouse.get("node") == node_name
        tun_settings = dict(settings.get("tun", {}))
        tun_settings.update({
            "dev": service.get("interface", "nebula1"),
            "disabled": bool(is_lighthouse),
            "unsafe_routes": unsafe_routes,
        })

        config = settings
        config.update({
            "pki": {
                "ca": f"/persist/nebula-runtime/profiles/{node_name}/ca.crt",
                "cert": f"/persist/nebula-runtime/profiles/{node_name}/{node_name}.crt",
                "key": f"/persist/nebula-runtime/profiles/{node_name}/{node_name}.key",
            },
            "static_host_map": static_map,
            "lighthouse": {
                "am_lighthouse": bool(is_lighthouse),
                "hosts": [] if is_lighthouse else lighthouse_ips,
            },
            "listen": {
                "host": service.get("listenHost", "[::]"),
                "port": int(service.get("port", lighthouse.get("port", 4242))),
            },
            "tun": tun_settings,
            "firewall": firewall,
            "relay": settings.get("relay", runtime.get("relay", {})),
        })

        target.write_text(json.dumps(config, indent=2, sort_keys=True), encoding="utf-8")
        PY

        python3 - /run/s-router-nebula-render-node/runtime-node.json <<'PY'
        import json
        import ipaddress
        import subprocess
        import sys

        runtime = json.load(open(sys.argv[1], encoding="utf-8"))["runtimeNode"]
        for route in runtime.get("routePreparation", {}).get("removeRoutes", []):
            network = ipaddress.ip_network(route, strict=False)
            command = ["ip", "-6", "route", "del", route] if network.version == 6 else ["ip", "route", "del", route]
            subprocess.run(command, check=False)
        PY

        python3 - /run/s-router-nebula-render-node/runtime.json <<'PY'
        import ipaddress
        import json
        import subprocess
        import sys

        config = json.load(open(sys.argv[1], encoding="utf-8"))
        endpoints = []
        for values in (config.get("static_host_map") or {}).values():
            for endpoint in values:
                host = str(endpoint).rsplit(":", 1)[0].strip("[]")
                try:
                    ipaddress.ip_address(host)
                except ValueError:
                    continue
                endpoints.append(host)

        for host in sorted(set(endpoints)):
            family_flag = "-6" if ":" in host else "-4"
            route = subprocess.run(
                ["ip", "-j", family_flag, "route", "get", host],
                check=False,
                text=True,
                stdout=subprocess.PIPE,
            )
            if route.returncode != 0 or not route.stdout.strip():
                continue
            entry = json.loads(route.stdout)[0]
            dev = entry.get("dev")
            if not dev or dev == (config.get("tun") or {}).get("dev", "nebula1"):
                continue
            command = ["ip", family_flag, "route", "replace", f"{host}/32" if family_flag == "-4" else f"{host}/128"]
            if entry.get("gateway"):
                command += ["via", entry["gateway"]]
            command += ["dev", dev]
            subprocess.run(command, check=True)
        PY

        exec nebula -config /run/s-router-nebula-render-node/runtime.json
      '';
    };
  };
  container = renderedContainers.${containerName};
  runtimeSecretMounts = builtins.listToAttrs (
    map (secretName: {
      name = "/run/secrets/${secretName}";
      value = {
        hostPath = "/run/secrets/${secretName}";
        isReadOnly = true;
      };
    }) runtimeSecretNames
  );
  containerPath =
    (lib.nixosSystem {
      system = pkgs.stdenv.hostPlatform.system;
      modules = [
        container.config
        serviceModule
      ];
    }).config.system.build.toplevel;
in
lib.optionalAttrs (builtins.hasAttr containerName renderedContainers) {
  ${containerName} = {
    config = serviceModule;
    bindMounts = (container.bindMounts or { }) // runtimeSecretMounts;
    path = lib.mkForce containerPath;
  };
}
