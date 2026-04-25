{
  lib,
  pkgs,
  nebulaRuntimePlan ? {
    overlays = { };
    nodes = { };
  },
}:
let
  sortedAttrNames = attrs: builtins.sort builtins.lessThan (builtins.attrNames attrs);

  sanitizeName =
    value:
    lib.replaceStrings
      [
        "::"
        ":"
        "."
        "/"
        " "
      ]
      [
        "-"
        "-"
        "-"
        "-"
        "-"
      ]
      value;

  runtimeNodeNames = sortedAttrNames (nebulaRuntimePlan.nodes or { });

  runtimeNodes =
    builtins.mapAttrs (
      nodeName: node:
      let
        overlayAddresses = node.overlayAddresses or [ ];
        lighthouse = node.lighthouse or { };
        lighthouseAddresses = lighthouse.overlayAddresses or [ ];
        lighthouseIps = lighthouse.overlayIps or [ ];
      in
      {
        overlayId = node.overlayId or null;
        certCidr4 = builtins.elemAt overlayAddresses 0;
        certCidr6 = builtins.elemAt overlayAddresses 1;
        groupsCsv = lib.concatStringsSep "," (node.groups or [ ]);
        unsafeRoutes = node.unsafeRoutes or [ ];
        service = node.service or {
          name = "nebula-runtime";
          interface = "nebula1";
        };
        materialization = node.materialization or { };
        lighthouse = {
          overlayId = node.overlayId or null;
          node = lighthouse.node or null;
          endpoint = lighthouse.endpoint or null;
          endpoint6 = lighthouse.endpoint6 or null;
          port = builtins.toString (lighthouse.port or 4242);
          certCidr4 = builtins.elemAt lighthouseAddresses 0;
          certCidr6 = builtins.elemAt lighthouseAddresses 1;
          overlayIp4 = builtins.elemAt lighthouseIps 0;
          overlayIp6 = builtins.elemAt lighthouseIps 1;
        };
      }
    ) (nebulaRuntimePlan.nodes or { });

  overlayNames = sortedAttrNames (nebulaRuntimePlan.overlays or { });

  lighthouseFingerprints =
    lib.unique (
      map
        (
          overlayId:
          let
            overlay = nebulaRuntimePlan.overlays.${overlayId};
            lighthouse = overlay.lighthouse or { };
            overlayAddresses = lighthouse.overlayAddresses or [ ];
          in
          lib.concatStringsSep "|" [
            (builtins.elemAt overlayAddresses 0)
            (builtins.elemAt overlayAddresses 1)
            (lighthouse.endpoint or "")
            (lighthouse.endpoint6 or "")
            (builtins.toString (lighthouse.port or 4242))
          ]
        )
        overlayNames
    );

  lighthouses =
    builtins.listToAttrs (
      lib.imap0
        (
          index: fingerprint:
          let
            matchingOverlayIds =
              lib.filter
                (
                  overlayId:
                  let
                    overlay = nebulaRuntimePlan.overlays.${overlayId};
                    lighthouse = overlay.lighthouse or { };
                    overlayAddresses = lighthouse.overlayAddresses or [ ];
                  in
                  fingerprint
                  == lib.concatStringsSep "|" [
                    (builtins.elemAt overlayAddresses 0)
                    (builtins.elemAt overlayAddresses 1)
                    (lighthouse.endpoint or "")
                    (lighthouse.endpoint6 or "")
                    (builtins.toString (lighthouse.port or 4242))
                  ]
                )
                overlayNames;
            baseOverlay = nebulaRuntimePlan.overlays.${builtins.head matchingOverlayIds};
            baseLighthouse = baseOverlay.lighthouse or { };
            overlayAddresses = baseLighthouse.overlayAddresses or [ ];
            overlayIps = baseLighthouse.overlayIps or [ ];
            memberNodeNames =
              lib.filter
                (nodeName: builtins.elem (runtimeNodes.${nodeName}.overlayId or "") matchingOverlayIds)
                runtimeNodeNames;
            unsafeNetworks =
              lib.unique (
                builtins.concatLists (
                  map
                    (nodeName: map (route: route.route or "") (runtimeNodes.${nodeName}.unsafeRoutes or [ ]))
                    memberNodeNames
                )
              );
            logicalName = sanitizeName baseOverlay.name;
            name = logicalName;
          in
          {
            inherit name;
            value = {
              id = logicalName;
              overlayIds = matchingOverlayIds;
              node = baseLighthouse.node or null;
              endpoint = baseLighthouse.endpoint or null;
              endpoint6 = baseLighthouse.endpoint6 or null;
              port = builtins.toString (baseLighthouse.port or 4242);
              certCidr4 = builtins.elemAt overlayAddresses 0;
              certCidr6 = builtins.elemAt overlayAddresses 1;
              overlayIp4 = builtins.elemAt overlayIps 0;
              overlayIp6 = builtins.elemAt overlayIps 1;
              certNetworks = [
                (builtins.elemAt overlayAddresses 0)
                (builtins.elemAt overlayAddresses 1)
              ];
              unsafeNetworks = unsafeNetworks;
              certBaseName = "${logicalName}-${baseLighthouse.node or "lighthouse"}";
              serviceName = "nebula-s-router-test-lighthouse-${logicalName}";
              interfaceName = "nebula${builtins.toString index}";
              overlayNetworks4Csv = builtins.elemAt overlayAddresses 0;
              overlayNetworks6Csv = builtins.elemAt overlayAddresses 1;
            };
          }
        )
        lighthouseFingerprints
    );

  lighthouseNames = sortedAttrNames lighthouses;

  runtimeNodesJson = builtins.toJSON runtimeNodes;
  lighthousesJson = builtins.toJSON lighthouses;
in
if runtimeNodeNames == [ ] then
  { }
else
  {
    environment.etc."s-router-test/nebula-bootstrap-spec.json".text =
      builtins.toJSON {
        runtimeNodes = runtimeNodes;
        lighthouses = lighthouses;
      };

    systemd.tmpfiles.rules =
      [
        "d /persist/nebula-runtime 0700 root root -"
        "d /persist/nebula-runtime/pki 0700 root root -"
        "d /persist/nebula-runtime/profiles 0700 root root -"
      ]
      ++ map (nodeName: "d /persist/nebula-runtime/profiles/${nodeName} 0700 root root -") runtimeNodeNames;

    systemd.services.nebula-ca-unseal = {
      description = "Unlock the Nebula CA into /run for explicit issuance work";
      serviceConfig.Type = "oneshot";
      path = with pkgs; [
        bash
        coreutils
        nebula
        openssl
        util-linux
      ];
      script = ''
        set -euo pipefail

        state_dir="/persist/nebula-runtime"
        pki_dir="$state_dir/pki"
        run_dir="/run/nebula-runtime"
        unsealed_dir="$run_dir/unsealed"
        passphrase_file="/run/keys/nebula-ca-passphrase"
        legacy_ca_key="$pki_dir/ca.key"
        encrypted_ca_key="$pki_dir/ca.key.enc"
        ca_crt="$pki_dir/ca.crt"
        unsealed_ca_key="$unsealed_dir/ca.key"
        tmpdir=""

        cleanup() {
          rm -f "$passphrase_file"
          if [ -n "$tmpdir" ] && [ -d "$tmpdir" ]; then
            rm -rf "$tmpdir"
          fi
        }
        trap cleanup EXIT

        if [ ! -s "$passphrase_file" ]; then
          echo "nebula-ca-unseal: missing transient passphrase file $passphrase_file" >&2
          exit 1
        fi

        install -d -m 0700 "$pki_dir" "$run_dir" "$unsealed_dir"

        seal_plaintext_key() {
          local plaintext_key="$1"

          ${pkgs.openssl}/bin/openssl enc -aes-256-cbc -pbkdf2 -salt \
            -in "$plaintext_key" \
            -out "$encrypted_ca_key" \
            -pass "file:$passphrase_file"
          chmod 0600 "$encrypted_ca_key"

          if command -v shred >/dev/null 2>&1; then
            shred -u "$plaintext_key" 2>/dev/null || rm -f "$plaintext_key"
          else
            rm -f "$plaintext_key"
          fi
        }

        if [ -s "$legacy_ca_key" ]; then
          if [ ! -s "$encrypted_ca_key" ]; then
            seal_plaintext_key "$legacy_ca_key"
          else
            if command -v shred >/dev/null 2>&1; then
              shred -u "$legacy_ca_key" 2>/dev/null || rm -f "$legacy_ca_key"
            else
              rm -f "$legacy_ca_key"
            fi
          fi
        fi

        if [ ! -s "$encrypted_ca_key" ]; then
          if [ -s "$ca_crt" ]; then
            echo "nebula-ca-unseal: refusing to continue with cert present but missing encrypted CA key" >&2
            exit 1
          fi

          tmpdir="$(mktemp -d)"
          ${pkgs.nebula}/bin/nebula-cert ca \
            -name s-router-test-lab \
            -out-crt "$tmpdir/ca.crt" \
            -out-key "$tmpdir/ca.key"
          install -m 0600 "$tmpdir/ca.crt" "$ca_crt"
          seal_plaintext_key "$tmpdir/ca.key"
        fi

        rm -f "$unsealed_ca_key"
        ${pkgs.openssl}/bin/openssl enc -d -aes-256-cbc -pbkdf2 \
          -in "$encrypted_ca_key" \
          -out "$unsealed_ca_key" \
          -pass "file:$passphrase_file"
        chmod 0600 "$unsealed_ca_key"
      '';
    };

    systemd.services.nebula-profile-bootstrap = {
      description = "Generate and distribute Nebula runtime profiles for s-router-test";
      after = [ "network-online.target" ] ++ map (nodeName: "container@${nodeName}.service") runtimeNodeNames;
      wants = [ "network-online.target" ] ++ map (nodeName: "container@${nodeName}.service") runtimeNodeNames;
      serviceConfig.Type = "oneshot";
      unitConfig.ConditionPathExists = "/run/nebula-runtime/unsealed/ca.key";
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
        signing_ca_key="/run/nebula-runtime/unsealed/ca.key"
        runtime_nodes_json='${runtimeNodesJson}'
        lighthouses_json='${lighthousesJson}'

        cleanup() {
          rm -f "$signing_ca_key"
        }
        trap cleanup EXIT

        mkdir -p "$pki_dir"
        printf '%s' "$runtime_nodes_json" | jq -r 'keys[]' | while read -r node_name; do
          mkdir -p "$profiles_dir/$node_name"
        done

        issue_node_cert() {
          local cert_name="$1"
          local node_networks="$2"
          local node_groups="$3"
          local node_unsafe_networks="''${4:-}"
          local cert_path="$pki_dir/$cert_name.crt"
          local key_path="$pki_dir/$cert_name.key"

          rm -f "$cert_path" "$key_path"
          cert_args=(
            -ca-crt "$pki_dir/ca.crt"
            -ca-key "$signing_ca_key"
            -name "$cert_name"
            -networks "$node_networks"
            -groups "$node_groups"
            -out-crt "$cert_path"
            -out-key "$key_path"
          )
          if [ -n "$node_unsafe_networks" ]; then
            cert_args+=(-unsafe-networks "$node_unsafe_networks")
          fi
          ${pkgs.nebula}/bin/nebula-cert sign "''${cert_args[@]}"
        }

        if [ ! -s "$pki_dir/ca.crt" ] || [ ! -s "$signing_ca_key" ]; then
          echo "nebula-profile-bootstrap: missing unlocked CA material; run nebula-ca-unseal first" >&2
          exit 1
        fi

        printf '%s' "$runtime_nodes_json" | jq -r 'keys[]' | while read -r node_name; do
          cert_cidr4="$(printf '%s' "$runtime_nodes_json" | jq -r --arg n "$node_name" '.[$n].certCidr4')"
          cert_cidr6="$(printf '%s' "$runtime_nodes_json" | jq -r --arg n "$node_name" '.[$n].certCidr6')"
          groups_csv="$(printf '%s' "$runtime_nodes_json" | jq -r --arg n "$node_name" '.[$n].groupsCsv')"
          unsafe_networks="$(printf '%s' "$runtime_nodes_json" | jq -r --arg n "$node_name" '.[$n].unsafeRoutes | map(.route) | join(",")')"
          if [ "$node_name" = "hostile-node01" ] && [ -s /run/secrets/subnet-ipv6 ]; then
            delegated_prefix="$(tr -d '[:space:]' </run/secrets/subnet-ipv6)"
            if [ -n "$delegated_prefix" ]; then
              if [ -n "$unsafe_networks" ]; then
                unsafe_networks="$unsafe_networks,$delegated_prefix"
              else
                unsafe_networks="$delegated_prefix"
              fi
            fi
          fi
          issue_node_cert "$node_name" "$cert_cidr4,$cert_cidr6" "$groups_csv" "$unsafe_networks"
        done

        printf '%s' "$lighthouses_json" | jq -r 'keys[]' | while read -r lighthouse_id; do
          cert_base_name="$(printf '%s' "$lighthouses_json" | jq -r --arg n "$lighthouse_id" '.[$n].certBaseName')"
          cert_networks="$(printf '%s' "$lighthouses_json" | jq -r --arg n "$lighthouse_id" '.[$n].certNetworks | join(",")')"
          unsafe_networks="$(printf '%s' "$lighthouses_json" | jq -r --arg n "$lighthouse_id" '.[$n].unsafeNetworks | join(",")')"
          issue_node_cert "$cert_base_name" "$cert_networks" "lab,lighthouse" "$unsafe_networks"
        done

        root_ssh_dir="/persist/root/.ssh"
        mkdir -p "$root_ssh_dir"
        chmod 0700 "$root_ssh_dir"
        if [ ! -s "$root_ssh_dir/id_ed25519" ] || [ ! -s "$root_ssh_dir/id_ed25519.pub" ]; then
          rm -f "$root_ssh_dir/id_ed25519" "$root_ssh_dir/id_ed25519.pub"
          ${pkgs.openssh}/bin/ssh-keygen -q -t ed25519 -N "" -f "$root_ssh_dir/id_ed25519"
        fi

        install_profile() {
          local profile_name="$1"
          local profile_dir="$profiles_dir/$profile_name"
          local pki_base="/persist/etc/nebula"
          local cert_name="$profile_name.crt"
          local key_name="$profile_name.key"
          local lighthouse_ip4
          local lighthouse_ip6
          local lighthouse_endpoint
          local lighthouse_endpoint6
          local lighthouse_port
          local unsafe_routes_yaml
          local unsafe_fw_rules

          lighthouse_ip4="$(printf '%s' "$runtime_nodes_json" | jq -r --arg n "$profile_name" '.[$n].lighthouse.overlayIp4')"
          lighthouse_ip6="$(printf '%s' "$runtime_nodes_json" | jq -r --arg n "$profile_name" '.[$n].lighthouse.overlayIp6')"
          lighthouse_endpoint="$(printf '%s' "$runtime_nodes_json" | jq -r --arg n "$profile_name" '.[$n].lighthouse.endpoint')"
          lighthouse_endpoint6="$(printf '%s' "$runtime_nodes_json" | jq -r --arg n "$profile_name" '.[$n].lighthouse.endpoint6')"
          lighthouse_port="$(printf '%s' "$runtime_nodes_json" | jq -r --arg n "$profile_name" '.[$n].lighthouse.port')"
          unsafe_routes_yaml="$(
            printf '%s' "$runtime_nodes_json" \
              | jq -r --arg n "$profile_name" '
                  .[$n].unsafeRoutes
                  | map(
                      "    - route: \(.route)\n      via: "
                      + (if (.route | contains(":")) then "__LIGHTHOUSE_IPV6__" else "__LIGHTHOUSE_IPV4__" end)
                      + "\n      mtu: 1300\n      install: false"
                    )
                  | join("\n")
                '
          )"
          unsafe_fw_rules="$(
            printf '%s' "$runtime_nodes_json" \
              | jq -r --arg n "$profile_name" '
                  .[$n].unsafeRoutes
                  | map("    - port: any\n      proto: any\n      host: any\n      local_cidr: \(.route)")
                  | join("\n")
                '
          )"

          if [ "$profile_name" = "hostile-node01" ] && [ -s /run/secrets/subnet-ipv6 ]; then
            delegated_prefix="$(tr -d '[:space:]' </run/secrets/subnet-ipv6)"
            if [ -n "$delegated_prefix" ]; then
              extra_route_yaml="    - route: $delegated_prefix
      via: $lighthouse_ip6
      mtu: 1300
      install: false"
              extra_fw_rule="    - port: any
      proto: any
      host: any
      local_cidr: $delegated_prefix"
              if [ -n "$unsafe_routes_yaml" ]; then
                unsafe_routes_yaml="$unsafe_routes_yaml
$extra_route_yaml"
              else
                unsafe_routes_yaml="$extra_route_yaml"
              fi
              if [ -n "$unsafe_fw_rules" ]; then
                unsafe_fw_rules="$unsafe_fw_rules
$extra_fw_rule"
              else
                unsafe_fw_rules="$extra_fw_rule"
              fi
            fi
          fi

          if [ -n "$unsafe_routes_yaml" ]; then
            unsafe_routes_yaml="$(printf '%s\n' "$unsafe_routes_yaml" | sed "s/__LIGHTHOUSE_IPV4__/''${lighthouse_ip4}/g; s/__LIGHTHOUSE_IPV6__/''${lighthouse_ip6}/g")"
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

static_host_map:
  "$lighthouse_ip4":
    - "$lighthouse_endpoint:$lighthouse_port"
    - "[$lighthouse_endpoint6]:$lighthouse_port"
  "$lighthouse_ip6":
    - "$lighthouse_endpoint:$lighthouse_port"
    - "[$lighthouse_endpoint6]:$lighthouse_port"

lighthouse:
  am_lighthouse: false
  hosts:
    - "$lighthouse_ip4"
    - "$lighthouse_ip6"

punchy:
  punch: true

listen:
  host: "[::]"
  port: 4242

tun:
  dev: nebula1
  drop_multicast: false
$(if [ -n "$unsafe_routes_yaml" ]; then cat <<UNSAFE
  unsafe_routes:
$unsafe_routes_yaml
UNSAFE
fi)

firewall:
  outbound:
    - port: any
      proto: any
      host: any
$(if [ -n "$unsafe_fw_rules" ]; then cat <<UNSAFEFWOUT
$unsafe_fw_rules
UNSAFEFWOUT
fi)
  inbound:
    - port: any
      proto: any
      host: any
EOF
        }

        printf '%s' "$runtime_nodes_json" | jq -r 'keys[]' | while read -r node_name; do
          install_profile "$node_name"
        done

        best_effort_restart_nebula_runtime() {
          local machine_name="$1"
          for _ in $(seq 1 10); do
            if ${pkgs.systemd}/bin/machinectl show "$machine_name" --property Leader --value >/dev/null 2>&1; then
              if ${pkgs.systemd}/bin/machinectl shell "$machine_name" /bin/sh -lc 'systemctl restart nebula-runtime' </dev/null >/dev/null 2>&1; then
                return 0
              fi
            fi
            sleep 1
          done
          return 0
        }

        printf '%s' "$runtime_nodes_json" | jq -r 'keys[]' | while read -r node_name; do
          best_effort_restart_nebula_runtime "$node_name"
        done

        if ${pkgs.openssh}/bin/ssh -o BatchMode=yes -o ConnectTimeout=10 -o StrictHostKeyChecking=accept-new \
          -i "$root_ssh_dir/id_ed25519" root@46.224.173.254 true 2>/dev/null; then
          remote_state_dir="/root/nebula-s-router-test"
          remote_profile_dir="$remote_state_dir/profile"
          remote_bin_dir="$remote_state_dir/bin"

          printf '%s' "$lighthouses_json" | jq -r 'keys[]' | while read -r lighthouse_id; do
            cert_base_name="$(printf '%s' "$lighthouses_json" | jq -r --arg n "$lighthouse_id" '.[$n].certBaseName')"
            service_name="$(printf '%s' "$lighthouses_json" | jq -r --arg n "$lighthouse_id" '.[$n].serviceName')"
            interface_name="$(printf '%s' "$lighthouses_json" | jq -r --arg n "$lighthouse_id" '.[$n].interfaceName')"
            lighthouse_port="$(printf '%s' "$lighthouses_json" | jq -r --arg n "$lighthouse_id" '.[$n].port')"
            overlay_networks4_csv="$(printf '%s' "$lighthouses_json" | jq -r --arg n "$lighthouse_id" '.[$n].overlayNetworks4Csv')"
            overlay_networks6_csv="$(printf '%s' "$lighthouses_json" | jq -r --arg n "$lighthouse_id" '.[$n].overlayNetworks6Csv')"
            unsafe_fw_rules="$(
              printf '%s' "$lighthouses_json" \
                | jq -r --arg n "$lighthouse_id" '
                    .[$n].unsafeNetworks
                    | map("    - port: any\n      proto: any\n      host: any\n      local_cidr: \(.)")
                    | join("\n")
                  '
            )"

            cat > "$profiles_dir/$cert_base_name.config.yml" <<EOF
pki:
  ca: $remote_profile_dir/ca.crt
  cert: $remote_profile_dir/$cert_base_name.crt
  key: $remote_profile_dir/$cert_base_name.key
static_map:
  network: ip

static_host_map: {}

lighthouse:
  am_lighthouse: true

listen:
  host: "[::]"
  port: $lighthouse_port

tun:
  dev: $interface_name
  drop_multicast: false

firewall:
  outbound:
    - port: any
      proto: any
      host: any
  inbound:
    - port: any
      proto: any
      host: any
$(if [ -n "$unsafe_fw_rules" ]; then printf '%s\n' "$unsafe_fw_rules"; fi)
EOF

            ${pkgs.openssh}/bin/scp -q -o BatchMode=yes -o ConnectTimeout=10 -o StrictHostKeyChecking=accept-new \
              -i "$root_ssh_dir/id_ed25519" \
              "$pki_dir/ca.crt" \
              "$pki_dir/$cert_base_name.crt" \
              "$pki_dir/$cert_base_name.key" \
              "$profiles_dir/$cert_base_name.config.yml" \
              root@46.224.173.254:/root/ \
              </dev/null

            ${pkgs.openssh}/bin/ssh -o BatchMode=yes -o ConnectTimeout=10 -o StrictHostKeyChecking=accept-new \
              -i "$root_ssh_dir/id_ed25519" root@46.224.173.254 "
                set -euo pipefail
                remote_state_dir='$remote_state_dir'
                remote_profile_dir='$remote_profile_dir'
                remote_bin_dir='$remote_bin_dir'
                cert_base_name='$cert_base_name'
                service_name='$service_name'
                interface_name='$interface_name'
                lighthouse_port='$lighthouse_port'
                overlay_networks4_csv='$overlay_networks4_csv'
                overlay_networks6_csv='$overlay_networks6_csv'

                install -d -m 0700 \"\$remote_profile_dir\" \"\$remote_bin_dir\"
                install -m 0600 /root/ca.crt \"\$remote_profile_dir/ca.crt\"
                install -m 0600 /root/\$cert_base_name.crt \"\$remote_profile_dir/\$cert_base_name.crt\"
                install -m 0600 /root/\$cert_base_name.key \"\$remote_profile_dir/\$cert_base_name.key\"
                install -m 0600 /root/\$cert_base_name.config.yml \"\$remote_profile_dir/\$cert_base_name.config.yml\"
                rm -f /root/ca.crt /root/\$cert_base_name.crt /root/\$cert_base_name.key /root/\$cert_base_name.config.yml

                if ! command -v nebula >/dev/null 2>&1; then
                  if ! test -x \"\$remote_bin_dir/nebula\"; then
                    tmpdir=\"\$(mktemp -d)\"
                    trap 'rm -rf \"\$tmpdir\"' EXIT
                    curl -fsSL https://github.com/slackhq/nebula/releases/download/v1.10.3/nebula-linux-amd64.tar.gz | tar -C \"\$tmpdir\" -xz
                    install -m 0755 \"\$tmpdir/nebula\" \"\$remote_bin_dir/nebula\"
                  fi
                  nebula_bin=\"\$remote_bin_dir/nebula\"
                else
                  nebula_bin=\"\$(command -v nebula)\"
                fi

                systemctl disable --now nebula-s-router-test-lighthouse.service 2>/dev/null || true

                cat > /etc/systemd/system/\$service_name.service <<EOF_REMOTE
[Unit]
Description=Temporary Nebula lighthouse for s-router-test validation (\$service_name)
After=network-online.target
Wants=network-online.target

[Service]
ExecStart=\$nebula_bin -config \$remote_profile_dir/\$cert_base_name.config.yml
Restart=always
RestartSec=2

[Install]
WantedBy=multi-user.target
EOF_REMOTE

                if command -v iptables >/dev/null 2>&1; then
                  iptables -C INPUT -p udp --dport \$lighthouse_port -j ACCEPT 2>/dev/null || iptables -I INPUT -p udp --dport \$lighthouse_port -j ACCEPT
                  iptables -C FORWARD -i \$interface_name -o eth0 -j ACCEPT 2>/dev/null || iptables -I FORWARD -i \$interface_name -o eth0 -j ACCEPT
                  iptables -C FORWARD -i eth0 -o \$interface_name -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT 2>/dev/null || iptables -I FORWARD -i eth0 -o \$interface_name -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
                  printf '%s' \"\$overlay_networks4_csv\" | tr ',' '\n' | while read -r cidr; do
                    [ -n \"\$cidr\" ] || continue
                    iptables -t nat -C POSTROUTING -s \"\$cidr\" -o eth0 -j MASQUERADE 2>/dev/null || iptables -t nat -I POSTROUTING -s \"\$cidr\" -o eth0 -j MASQUERADE
                  done
                fi
                if command -v ip6tables >/dev/null 2>&1; then
                  ip6tables -C INPUT -p udp --dport \$lighthouse_port -j ACCEPT 2>/dev/null || ip6tables -I INPUT -p udp --dport \$lighthouse_port -j ACCEPT
                  ip6tables -C FORWARD -i \$interface_name -o eth0 -j ACCEPT 2>/dev/null || ip6tables -I FORWARD -i \$interface_name -o eth0 -j ACCEPT
                  ip6tables -C FORWARD -i eth0 -o \$interface_name -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT 2>/dev/null || ip6tables -I FORWARD -i eth0 -o \$interface_name -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
                  printf '%s' \"\$overlay_networks6_csv\" | tr ',' '\n' | while read -r cidr; do
                    [ -n \"\$cidr\" ] || continue
                    ip6tables -t nat -C POSTROUTING -s \"\$cidr\" -o eth0 -j MASQUERADE 2>/dev/null || ip6tables -t nat -I POSTROUTING -s \"\$cidr\" -o eth0 -j MASQUERADE
                  done
                fi
                sysctl -w net.ipv4.ip_forward=1
                sysctl -w net.ipv6.conf.all.forwarding=1
                systemctl daemon-reload
                systemctl enable \$service_name.service
                systemctl restart \$service_name.service
              " </dev/null
          done
        else
          echo "nebula-profile-bootstrap: Hetzner SSH key not authorized yet for root@46.224.173.254" >&2
        fi
      '';
    };

    systemd.paths.nebula-profile-bootstrap = {
      description = "Start Nebula profile bootstrap when the CA is unsealed into /run";
      wantedBy = [ "multi-user.target" ];
      pathConfig = {
        PathExists = "/run/nebula-runtime/unsealed/ca.key";
        Unit = "nebula-profile-bootstrap.service";
      };
    };
  }
