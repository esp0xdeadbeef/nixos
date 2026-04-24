{ pkgs, renderedHostNetwork }:
let
  sites = renderedHostNetwork.sites or { };

  requireAttr = path: value:
    if builtins.isAttrs value then
      value
    else
      throw "s-router-test/nebula-bootstrap.nix: missing attrset at ${path}";

  requireString = path: value:
    if builtins.isString value && value != "" then
      value
    else
      throw "s-router-test/nebula-bootstrap.nix: missing string at ${path}";

  stripPrefixLength =
    cidr:
    let
      match = builtins.match "([^/]+)/[0-9]+" cidr;
    in
    if match == null then
      throw "s-router-test/nebula-bootstrap.nix: expected CIDR, got ${builtins.toJSON cidr}"
    else
      builtins.head match;

  readPrefixLength =
    cidr:
    let
      match = builtins.match "[^/]+/([0-9]+)" cidr;
    in
    if match == null then
      throw "s-router-test/nebula-bootstrap.nix: expected CIDR prefix length, got ${builtins.toJSON cidr}"
    else
      builtins.fromJSON (builtins.head match);

  withPrefixLength = cidr: prefixLength: "${stripPrefixLength cidr}/${builtins.toString prefixLength}";

  siteA = requireAttr "renderedHostNetwork.sites.esp0xdeadbeef.site-a" (
    (requireAttr "renderedHostNetwork.sites.esp0xdeadbeef" (sites.esp0xdeadbeef or null))."site-a" or null
  );
  siteB = requireAttr "renderedHostNetwork.sites.espbranch.site-b" (
    (requireAttr "renderedHostNetwork.sites.espbranch" (sites.espbranch or null))."site-b" or null
  );

  overlayA = requireAttr "renderedHostNetwork.sites.esp0xdeadbeef.site-a.overlays.east-west" (
    (requireAttr "renderedHostNetwork.sites.esp0xdeadbeef.site-a.overlays" (siteA.overlays or null))."east-west"
      or null
  );
  overlayB = requireAttr "renderedHostNetwork.sites.espbranch.site-b.overlays.east-west" (
    (requireAttr "renderedHostNetwork.sites.espbranch.site-b.overlays" (siteB.overlays or null))."east-west"
      or null
  );
  overlayANebula = requireAttr "renderedHostNetwork.sites.esp0xdeadbeef.site-a.overlays.east-west.nebula" (
    overlayA.nebula or null
  );
  overlayAIpam = requireAttr "renderedHostNetwork.sites.esp0xdeadbeef.site-a.overlays.east-west.ipam" (
    overlayA.ipam or null
  );
  overlayALighthouse = requireAttr "renderedHostNetwork.sites.esp0xdeadbeef.site-a.overlays.east-west.nebula.lighthouse" (
    overlayANebula.lighthouse or null
  );
  overlayBIpam = requireAttr "renderedHostNetwork.sites.espbranch.site-b.overlays.east-west.ipam" (
    overlayB.ipam or null
  );

  overlayANodes = requireAttr "renderedHostNetwork.sites.esp0xdeadbeef.site-a.overlays.east-west.nodes" (
    overlayA.nodes or null
  );
  overlayBNodes = requireAttr "renderedHostNetwork.sites.espbranch.site-b.overlays.east-west.nodes" (
    overlayB.nodes or null
  );

  coreOverlayCidr = requireString
    "renderedHostNetwork.sites.esp0xdeadbeef.site-a.overlays.east-west.nodes.nebula-core.addr4"
    ((requireAttr "renderedHostNetwork.sites.esp0xdeadbeef.site-a.overlays.east-west.nodes.nebula-core" (overlayANodes.nebula-core or null)).addr4 or null);
  coreOverlayCidr6 = requireString
    "renderedHostNetwork.sites.esp0xdeadbeef.site-a.overlays.east-west.nodes.nebula-core.addr6"
    ((requireAttr "renderedHostNetwork.sites.esp0xdeadbeef.site-a.overlays.east-west.nodes.nebula-core" (overlayANodes.nebula-core or null)).addr6 or null);
  branchOverlayCidr = requireString
    "renderedHostNetwork.sites.espbranch.site-b.overlays.east-west.nodes.branch-node01.addr4"
    ((requireAttr "renderedHostNetwork.sites.espbranch.site-b.overlays.east-west.nodes.branch-node01" (overlayBNodes.branch-node01 or null)).addr4 or null);
  branchOverlayCidr6 = requireString
    "renderedHostNetwork.sites.espbranch.site-b.overlays.east-west.nodes.branch-node01.addr6"
    ((requireAttr "renderedHostNetwork.sites.espbranch.site-b.overlays.east-west.nodes.branch-node01" (overlayBNodes.branch-node01 or null)).addr6 or null);
  hostileOverlayCidr = requireString
    "renderedHostNetwork.sites.espbranch.site-b.overlays.east-west.nodes.hostile-node01.addr4"
    ((requireAttr "renderedHostNetwork.sites.espbranch.site-b.overlays.east-west.nodes.hostile-node01" (overlayBNodes.hostile-node01 or null)).addr4 or null);
  hostileOverlayCidr6 = requireString
    "renderedHostNetwork.sites.espbranch.site-b.overlays.east-west.nodes.hostile-node01.addr6"
    ((requireAttr "renderedHostNetwork.sites.espbranch.site-b.overlays.east-west.nodes.hostile-node01" (overlayBNodes.hostile-node01 or null)).addr6 or null);
  lighthouseNodeName =
    requireString
      "renderedHostNetwork.sites.esp0xdeadbeef.site-a.overlays.east-west.nebula.lighthouse.node"
      (overlayALighthouse.node or null);
  lighthouseOverlayCidr = requireString
    "renderedHostNetwork.sites.esp0xdeadbeef.site-a.overlays.east-west.nodes.${lighthouseNodeName}.addr4"
    ((requireAttr
      "renderedHostNetwork.sites.esp0xdeadbeef.site-a.overlays.east-west.nodes.${lighthouseNodeName}"
      (overlayANodes.${lighthouseNodeName} or null)).addr4 or null);
  lighthouseOverlayCidr6 = requireString
    "renderedHostNetwork.sites.esp0xdeadbeef.site-a.overlays.east-west.nodes.${lighthouseNodeName}.addr6"
    ((requireAttr
      "renderedHostNetwork.sites.esp0xdeadbeef.site-a.overlays.east-west.nodes.${lighthouseNodeName}"
      (overlayANodes.${lighthouseNodeName} or null)).addr6 or null);
  lighthouseEndpoint = requireString
    "renderedHostNetwork.sites.esp0xdeadbeef.site-a.overlays.east-west.nebula.lighthouse.endpoint"
    (overlayALighthouse.endpoint or null);
  lighthouseEndpoint6 = requireString
    "renderedHostNetwork.sites.esp0xdeadbeef.site-a.overlays.east-west.nebula.lighthouse.endpoint6"
    (overlayALighthouse.endpoint6 or null);
  lighthousePort = builtins.toString (overlayALighthouse.port or 4242);
  overlayAV4PrefixLength = readPrefixLength (
    requireString
      "renderedHostNetwork.sites.esp0xdeadbeef.site-a.overlays.east-west.ipam.ipv4.prefix"
      ((requireAttr
        "renderedHostNetwork.sites.esp0xdeadbeef.site-a.overlays.east-west.ipam.ipv4"
        (overlayAIpam.ipv4 or null)).prefix or null)
  );
  overlayAV6PrefixLength = readPrefixLength (
    requireString
      "renderedHostNetwork.sites.esp0xdeadbeef.site-a.overlays.east-west.ipam.ipv6.prefix"
      ((requireAttr
        "renderedHostNetwork.sites.esp0xdeadbeef.site-a.overlays.east-west.ipam.ipv6"
        (overlayAIpam.ipv6 or null)).prefix or null)
  );
  overlayBV4PrefixLength = readPrefixLength (
    requireString
      "renderedHostNetwork.sites.espbranch.site-b.overlays.east-west.ipam.ipv4.prefix"
      ((requireAttr
        "renderedHostNetwork.sites.espbranch.site-b.overlays.east-west.ipam.ipv4"
        (overlayBIpam.ipv4 or null)).prefix or null)
  );
  overlayBV6PrefixLength = readPrefixLength (
    requireString
      "renderedHostNetwork.sites.espbranch.site-b.overlays.east-west.ipam.ipv6.prefix"
      ((requireAttr
        "renderedHostNetwork.sites.espbranch.site-b.overlays.east-west.ipam.ipv6"
        (overlayBIpam.ipv6 or null)).prefix or null)
  );

  lighthouseOverlayIp = stripPrefixLength lighthouseOverlayCidr;
  lighthouseOverlayIp6 = stripPrefixLength lighthouseOverlayCidr6;
  coreCertCidr = withPrefixLength coreOverlayCidr overlayAV4PrefixLength;
  coreCertCidr6 = withPrefixLength coreOverlayCidr6 overlayAV6PrefixLength;
  branchCertCidr = withPrefixLength branchOverlayCidr overlayBV4PrefixLength;
  branchCertCidr6 = withPrefixLength branchOverlayCidr6 overlayBV6PrefixLength;
  hostileCertCidr = withPrefixLength hostileOverlayCidr overlayBV4PrefixLength;
  hostileCertCidr6 = withPrefixLength hostileOverlayCidr6 overlayBV6PrefixLength;
  lighthouseCertCidr = withPrefixLength lighthouseOverlayCidr overlayAV4PrefixLength;
  lighthouseCertCidr6 = withPrefixLength lighthouseOverlayCidr6 overlayAV6PrefixLength;
  hostileUnsafeRoutes = [
    {
      route = "0.0.0.0/1";
      via = lighthouseOverlayIp;
    }
    {
      route = "128.0.0.0/1";
      via = lighthouseOverlayIp;
    }
    {
      route = "::/1";
      via = lighthouseOverlayIp6;
    }
    {
      route = "8000::/1";
      via = lighthouseOverlayIp6;
    }
  ];
  lighthouseUnsafeNetworks = builtins.concatStringsSep "," (map (route: route.route) hostileUnsafeRoutes);
in
if renderedHostNetwork.bridges ? branch then
  {
    environment.etc."s-router-test/nebula-bootstrap-spec.json".text =
      builtins.toJSON {
        core = {
          container = "nebula-core";
          overlayIp = coreOverlayCidr;
          overlayIp6 = coreOverlayCidr6;
        };

        branchNode = {
          container = "branch-node01";
          overlayIp = branchOverlayCidr;
          overlayIp6 = branchOverlayCidr6;
        };

        hostileNode = {
          container = "hostile-node01";
          overlayIp = hostileOverlayCidr;
          overlayIp6 = hostileOverlayCidr6;
        };

        lighthouse = {
          node = lighthouseNodeName;
          overlayIp = lighthouseOverlayCidr;
          overlayIp6 = lighthouseOverlayCidr6;
          endpoint = lighthouseEndpoint;
          endpoint6 = lighthouseEndpoint6;
          port = lighthousePort;
        };
      };

    systemd.tmpfiles.rules = [
      "d /persist/nebula-runtime 0700 root root -"
      "d /persist/nebula-runtime/pki 0700 root root -"
      "d /persist/nebula-runtime/profiles 0700 root root -"
      "d /persist/nebula-runtime/profiles/hetzner-nebula-prodtest-01 0700 root root -"
      "d /persist/nebula-runtime/profiles/nebula-core 0700 root root -"
      "d /persist/nebula-runtime/profiles/branch-node01 0700 root root -"
      "d /persist/nebula-runtime/profiles/hostile-node01 0700 root root -"
    ];

    systemd.services.nebula-profile-bootstrap = {
      description = "Generate and distribute Nebula runtime profiles for s-router-test";
      wantedBy = [ "multi-user.target" ];
      after = [
        "network-online.target"
        "container@nebula-core.service"
        "container@branch-node01.service"
      ];
      wants = [
        "network-online.target"
        "container@nebula-core.service"
        "container@branch-node01.service"
      ];
      serviceConfig.Type = "oneshot";
      path = with pkgs; [
        bash
        coreutils
        gnugrep
        gawk
        iproute2
        jq
        nebula
        openssh
        systemd
        util-linux
      ];
      script = ''
        set -euo pipefail

        state_dir="/persist/nebula-runtime"
        pki_dir="$state_dir/pki"
        profiles_dir="$state_dir/profiles"
        mkdir -p \
          "$pki_dir" \
          "$profiles_dir/hetzner-nebula-prodtest-01" \
          "$profiles_dir/nebula-core" \
          "$profiles_dir/branch-node01" \
          "$profiles_dir/hostile-node01"

        issue_node_cert() {
          local node_name="$1"
          local node_cidr4="$2"
          local node_cidr6="$3"
          local node_groups="$4"
          local node_unsafe_networks="''${5:-}"
          local cert_path="$pki_dir/$node_name.crt"
          local key_path="$pki_dir/$node_name.key"

          rm -f "$cert_path" "$key_path"
          cert_args=(
            -ca-crt "$pki_dir/ca.crt"
            -ca-key "$pki_dir/ca.key"
            -name "$node_name"
            -networks "$node_cidr4,$node_cidr6"
            -groups "$node_groups"
            -out-crt "$cert_path"
            -out-key "$key_path"
          )
          if [ -n "$node_unsafe_networks" ]; then
            cert_args+=(-unsafe-networks "$node_unsafe_networks")
          fi
          ${pkgs.nebula}/bin/nebula-cert sign "''${cert_args[@]}"
        }

        if [ ! -s "$pki_dir/ca.crt" ] || [ ! -s "$pki_dir/ca.key" ]; then
          ${pkgs.nebula}/bin/nebula-cert ca -name s-router-test-lab -out-crt "$pki_dir/ca.crt" -out-key "$pki_dir/ca.key"
        fi

        issue_node_cert nebula-core ${coreCertCidr} ${coreCertCidr6} lab,core
        issue_node_cert branch-node01 ${branchCertCidr} ${branchCertCidr6} lab,branch
        issue_node_cert hostile-node01 ${hostileCertCidr} ${hostileCertCidr6} lab,hostile
        issue_node_cert ${lighthouseNodeName} ${lighthouseCertCidr} ${lighthouseCertCidr6} lab,lighthouse ${lighthouseUnsafeNetworks}

        root_ssh_dir="/persist/root/.ssh"
        mkdir -p "$root_ssh_dir"
        chmod 0700 "$root_ssh_dir"
        if [ ! -s "$root_ssh_dir/id_ed25519" ] || [ ! -s "$root_ssh_dir/id_ed25519.pub" ]; then
          rm -f "$root_ssh_dir/id_ed25519" "$root_ssh_dir/id_ed25519.pub"
          ${pkgs.openssh}/bin/ssh-keygen -q -t ed25519 -N "" -f "$root_ssh_dir/id_ed25519"
        fi

        install_profile() {
          local profile_name="$1"
          local cert_name="$2"
          local key_name="$3"
          local profile_dir="$profiles_dir/$profile_name"
          local pki_base="/persist/etc/nebula"

          if [ "$profile_name" = "${lighthouseNodeName}" ]; then
            pki_base="/root/nebula-s-router-test/profile"
          fi

          install -d -m 0700 "$profile_dir"
          install -m 0600 "$pki_dir/ca.crt" "$profile_dir/ca.crt"
          install -m 0600 "$pki_dir/$cert_name" "$profile_dir/$cert_name"
          install -m 0600 "$pki_dir/$key_name" "$profile_dir/$key_name"
          cat >"$profile_dir/config.yml" <<EOF
pki:
  ca: $pki_base/ca.crt
  cert: $pki_base/$cert_name
  key: $pki_base/$key_name
static_map:
  network: ip
$(if [ "$profile_name" = "nebula-core" ]; then cat <<CORE

static_host_map:
  "${lighthouseOverlayIp}":
    - "${lighthouseEndpoint}:${lighthousePort}"
    - "[${lighthouseEndpoint6}]:${lighthousePort}"
  "${lighthouseOverlayIp6}":
    - "${lighthouseEndpoint}:${lighthousePort}"
    - "[${lighthouseEndpoint6}]:${lighthousePort}"

lighthouse:
  am_lighthouse: false
  hosts:
    - "${lighthouseOverlayIp}"
    - "${lighthouseOverlayIp6}"

punchy:
  punch: true

listen:
  host: "[::]"
  port: 4242
CORE
elif [ "$profile_name" = "${lighthouseNodeName}" ]; then cat <<LH

static_host_map: {}

lighthouse:
  am_lighthouse: true

listen:
  host: "[::]"
  port: ${lighthousePort}
LH
else cat <<BRANCH

static_host_map:
  "${lighthouseOverlayIp}":
    - "${lighthouseEndpoint}:${lighthousePort}"
    - "[${lighthouseEndpoint6}]:${lighthousePort}"
  "${lighthouseOverlayIp6}":
    - "${lighthouseEndpoint}:${lighthousePort}"
    - "[${lighthouseEndpoint6}]:${lighthousePort}"

lighthouse:
  am_lighthouse: false
  hosts:
    - "${lighthouseOverlayIp}"
    - "${lighthouseOverlayIp6}"

punchy:
  punch: true

listen:
  host: "[::]"
  port: 4242
BRANCH
fi)

tun:
  dev: nebula1
  drop_multicast: false
$(if [ "$profile_name" = "hostile-node01" ]; then cat <<UNSAFE
  unsafe_routes:
    - route: 0.0.0.0/1
      via: ${lighthouseOverlayIp}
      mtu: 1300
      install: false
    - route: 128.0.0.0/1
      via: ${lighthouseOverlayIp}
      mtu: 1300
      install: false
    - route: ::/1
      via: ${lighthouseOverlayIp6}
      mtu: 1300
      install: false
    - route: 8000::/1
      via: ${lighthouseOverlayIp6}
      mtu: 1300
      install: false
UNSAFE
fi)

firewall:
  outbound:
    - port: any
      proto: any
      host: any
$(if [ "$profile_name" = "hostile-node01" ]; then cat <<UNSAFEFWOUT
    - port: any
      proto: any
      host: any
      local_cidr: 0.0.0.0/1
    - port: any
      proto: any
      host: any
      local_cidr: 128.0.0.0/1
    - port: any
      proto: any
      host: any
      local_cidr: ::/1
    - port: any
      proto: any
      host: any
      local_cidr: 8000::/1
UNSAFEFWOUT
fi)
  inbound:
    - port: any
      proto: any
      host: any
$(if [ "$profile_name" = "${lighthouseNodeName}" ]; then cat <<UNSAFEFWIN
    - port: any
      proto: any
      host: any
      local_cidr: 0.0.0.0/1
    - port: any
      proto: any
      host: any
      local_cidr: 128.0.0.0/1
    - port: any
      proto: any
      host: any
      local_cidr: ::/1
    - port: any
      proto: any
      host: any
      local_cidr: 8000::/1
UNSAFEFWIN
fi)
EOF
        }

        install_profile nebula-core "nebula-core.crt" "nebula-core.key"
        install_profile branch-node01 "branch-node01.crt" "branch-node01.key"
        install_profile hostile-node01 "hostile-node01.crt" "hostile-node01.key"
        install_profile ${lighthouseNodeName} "${lighthouseNodeName}.crt" "${lighthouseNodeName}.key"

        restart_nebula_runtime() {
          local machine_name="$1"
          ${pkgs.systemd}/bin/systemd-run --quiet --wait --pipe -M "$machine_name" \
            /bin/sh -lc 'systemctl restart nebula-runtime'
        }

        restart_nebula_runtime nebula-core
        restart_nebula_runtime branch-node01
        restart_nebula_runtime hostile-node01

        if ${pkgs.openssh}/bin/ssh -o BatchMode=yes -o ConnectTimeout=10 -o StrictHostKeyChecking=accept-new \
          -i "$root_ssh_dir/id_ed25519" root@46.224.173.254 true 2>/dev/null; then
          remote_state_dir="/root/nebula-s-router-test"
          remote_profile_dir="$remote_state_dir/profile"
          remote_bin_dir="$remote_state_dir/bin"

          ${pkgs.openssh}/bin/scp -q -o BatchMode=yes -o ConnectTimeout=10 -o StrictHostKeyChecking=accept-new \
            -i "$root_ssh_dir/id_ed25519" \
            "$profiles_dir/${lighthouseNodeName}/ca.crt" \
            "$profiles_dir/${lighthouseNodeName}/${lighthouseNodeName}.crt" \
            "$profiles_dir/${lighthouseNodeName}/${lighthouseNodeName}.key" \
            "$profiles_dir/${lighthouseNodeName}/config.yml" \
            root@46.224.173.254:/root/

          ${pkgs.openssh}/bin/ssh -o BatchMode=yes -o ConnectTimeout=10 -o StrictHostKeyChecking=accept-new \
            -i "$root_ssh_dir/id_ed25519" root@46.224.173.254 '
              set -euo pipefail
              remote_state_dir="'"$remote_state_dir"'"
              remote_profile_dir="'"$remote_profile_dir"'"
              remote_bin_dir="'"$remote_bin_dir"'"
              install -d -m 0700 "$remote_profile_dir" "$remote_bin_dir"
              install -m 0600 /root/ca.crt "$remote_profile_dir/ca.crt"
              install -m 0600 /root/'"${lighthouseNodeName}"'.crt "$remote_profile_dir/'"${lighthouseNodeName}"'.crt"
              install -m 0600 /root/'"${lighthouseNodeName}"'.key "$remote_profile_dir/'"${lighthouseNodeName}"'.key"
              install -m 0600 /root/config.yml "$remote_profile_dir/config.yml"
              rm -f /root/ca.crt /root/'"${lighthouseNodeName}"'.crt /root/'"${lighthouseNodeName}"'.key /root/config.yml

              if ! command -v nebula >/dev/null 2>&1; then
                if ! test -x "$remote_bin_dir/nebula"; then
                  tmpdir="$(mktemp -d)"
                  trap "rm -rf \"$tmpdir\"" EXIT
                  curl -fsSL https://github.com/slackhq/nebula/releases/download/v1.10.3/nebula-linux-amd64.tar.gz \
                    | tar -C "$tmpdir" -xz
                  install -m 0755 "$tmpdir/nebula" "$remote_bin_dir/nebula"
                fi
                nebula_bin="$remote_bin_dir/nebula"
              else
                nebula_bin="$(command -v nebula)"
              fi

              cat > /etc/systemd/system/nebula-s-router-test-lighthouse.service <<EOF
[Unit]
Description=Temporary Nebula lighthouse for s-router-test validation
After=network-online.target
Wants=network-online.target

[Service]
ExecStart=$nebula_bin -config $remote_profile_dir/config.yml
Restart=always
RestartSec=2

[Install]
WantedBy=multi-user.target
EOF
              if command -v iptables >/dev/null 2>&1; then
                iptables -C INPUT -p udp --dport '"${lighthousePort}"' -j ACCEPT 2>/dev/null \
                  || iptables -I INPUT -p udp --dport '"${lighthousePort}"' -j ACCEPT
                iptables -C FORWARD -i nebula1 -o eth0 -j ACCEPT 2>/dev/null \
                  || iptables -I FORWARD -i nebula1 -o eth0 -j ACCEPT
                iptables -C FORWARD -i eth0 -o nebula1 -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT 2>/dev/null \
                  || iptables -I FORWARD -i eth0 -o nebula1 -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
                iptables -t nat -C POSTROUTING -s 100.96.10.0/24 -o eth0 -j MASQUERADE 2>/dev/null \
                  || iptables -t nat -I POSTROUTING -s 100.96.10.0/24 -o eth0 -j MASQUERADE
              fi
              if command -v ip6tables >/dev/null 2>&1; then
                ip6tables -C INPUT -p udp --dport '"${lighthousePort}"' -j ACCEPT 2>/dev/null \
                  || ip6tables -I INPUT -p udp --dport '"${lighthousePort}"' -j ACCEPT
                ip6tables -C FORWARD -i nebula1 -o eth0 -j ACCEPT 2>/dev/null \
                  || ip6tables -I FORWARD -i nebula1 -o eth0 -j ACCEPT
                ip6tables -C FORWARD -i eth0 -o nebula1 -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT 2>/dev/null \
                  || ip6tables -I FORWARD -i eth0 -o nebula1 -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
                ip6tables -t nat -C POSTROUTING -s fd42:dead:beef:ee::/64 -o eth0 -j MASQUERADE 2>/dev/null \
                  || ip6tables -t nat -I POSTROUTING -s fd42:dead:beef:ee::/64 -o eth0 -j MASQUERADE
              fi
              sysctl -w net.ipv4.ip_forward=1
              sysctl -w net.ipv6.conf.all.forwarding=1
              systemctl daemon-reload
              systemctl enable nebula-s-router-test-lighthouse.service
              systemctl restart nebula-s-router-test-lighthouse.service
            '
        else
          echo "nebula-profile-bootstrap: Hetzner SSH key not authorized yet for root@46.224.173.254" >&2
        fi
      '';
    };
  }
else
  { }
