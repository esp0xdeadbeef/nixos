{ pkgs, renderedHostNetwork }:
if renderedHostNetwork.bridges ? branch then
  {
    environment.etc."s-router-test/nebula-bootstrap-spec.json".text =
      builtins.toJSON {
        core = {
          container = "nebula-core";
          overlayIp = "100.64.10.1/24";
        };

        branchNode = {
          container = "branch-node01";
          overlayIp = "100.64.10.10/24";
        };
      };

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
          "$profiles_dir/nebula-core" \
          "$profiles_dir/branch-node01"

        if [ ! -s "$pki_dir/ca.crt" ] || [ ! -s "$pki_dir/ca.key" ]; then
          ${pkgs.nebula}/bin/nebula-cert ca -name s-router-test-lab -out-crt "$pki_dir/ca.crt" -out-key "$pki_dir/ca.key"
        fi

        if [ ! -s "$pki_dir/nebula-core.crt" ] || [ ! -s "$pki_dir/nebula-core.key" ]; then
          ${pkgs.nebula}/bin/nebula-cert sign \
            -ca-crt "$pki_dir/ca.crt" \
            -ca-key "$pki_dir/ca.key" \
            -name nebula-core \
            -ip 100.64.10.1/24 \
            -groups lab,core \
            -out-crt "$pki_dir/nebula-core.crt" \
            -out-key "$pki_dir/nebula-core.key"
        fi

        if [ ! -s "$pki_dir/branch-node01.crt" ] || [ ! -s "$pki_dir/branch-node01.key" ]; then
          ${pkgs.nebula}/bin/nebula-cert sign \
            -ca-crt "$pki_dir/ca.crt" \
            -ca-key "$pki_dir/ca.key" \
            -name branch-node01 \
            -ip 100.64.10.10/24 \
            -groups lab,branch \
            -out-crt "$pki_dir/branch-node01.crt" \
            -out-key "$pki_dir/branch-node01.key"
        fi

        wait_for_machine_pid() {
          local machine_name="$1"
          local machine_pid=""
          for _ in $(seq 1 120); do
            machine_pid="$(${pkgs.systemd}/bin/machinectl show "$machine_name" --property Leader --value 2>/dev/null || true)"
            if [ -n "$machine_pid" ] && [ "$machine_pid" != "0" ]; then
              printf '%s\n' "$machine_pid"
              return 0
            fi
            sleep 1
          done
          return 1
        }

        core_machine_pid="$(wait_for_machine_pid nebula-core)"
        core_wan_ip="$(
          ${pkgs.util-linux}/bin/nsenter -t "$core_machine_pid" -n \
            ${pkgs.iproute2}/bin/ip -j -4 addr show dev eth0 \
            | ${pkgs.jq}/bin/jq -r '.[0].addr_info[] | select(.family == "inet") | .local' \
            | head -n 1
        )"
        core_wan_ip="$(printf '%s' "$core_wan_ip" | tail -n 1)"

        install_profile() {
          local profile_name="$1"
          local cert_name="$2"
          local key_name="$3"
          local profile_dir="$profiles_dir/$profile_name"

          install -d -m 0700 "$profile_dir"
          install -m 0600 "$pki_dir/ca.crt" "$profile_dir/ca.crt"
          install -m 0600 "$pki_dir/$cert_name" "$profile_dir/$cert_name"
          install -m 0600 "$pki_dir/$key_name" "$profile_dir/$key_name"
          cat >"$profile_dir/config.yml" <<EOF
pki:
  ca: /persist/etc/nebula/ca.crt
  cert: /persist/etc/nebula/$cert_name
  key: /persist/etc/nebula/$key_name
$(if [ "$profile_name" = "nebula-core" ]; then cat <<CORE

static_host_map: {}

lighthouse:
  am_lighthouse: true

listen:
  host: 0.0.0.0
  port: 4242
CORE
else cat <<BRANCH

static_host_map:
  "100.64.10.1":
    - "$core_wan_ip:4242"

lighthouse:
  am_lighthouse: false
  hosts:
    - "100.64.10.1"

listen:
  host: 0.0.0.0
  port: 0
BRANCH
fi)

tun:
  dev: nebula1
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
EOF
        }

        install_profile nebula-core "nebula-core.crt" "nebula-core.key"
        install_profile branch-node01 "branch-node01.crt" "branch-node01.key"
      '';
    };
  }
else
  { }
