### FILE: ./pd-generate.nix ###
{ pkgs, ... }:

let
  applyScript = pkgs.writeShellScript "apply-v6-pd-configs" ''
    set -euo pipefail

    # Wait for networkd to obtain a delegated prefix (often shows up as a route "proto dhcp")
    PD=""
    for i in $(seq 1 60); do
      PD="$(ip -6 route show | awk '
        ($1 ~ /\/[0-9]+$/) && ($0 ~ /proto[[:space:]]+dhcp/) {print $1; exit}
      ')"
      if [ -n "$PD" ]; then
        break
      fi
      sleep 1
    done

    if [ -z "$PD" ]; then
      echo "No delegated IPv6 prefix found in routes (proto dhcp). Dumping ip -6 route:" >&2
      ip -6 route >&2 || true
      exit 1
    fi

    export PD="$PD"

    # Compute LAN64 (first /64 inside PD) and excluded prefix for Kea
    python3 - <<'PY' > /run/v6-derived.env
import ipaddress, os

pd = ipaddress.IPv6Network(os.environ["PD"], strict=False)

# Choose first /64 for LAN
lan64 = next(pd.subnets(new_prefix=64))

print(f"PD={pd}")
print(f"LAN64={lan64}")

# Kea prefix-exclude wants a prefix + length (exclude LAN64)
print(f"EXCL_PREFIX={lan64.network_address}")
print("EXCL_LEN=64")
PY

    . /run/v6-derived.env

    cat > /run/radvd.conf <<EOF
interface lan1010 {
  AdvSendAdvert on;
  AdvManagedFlag off;
  AdvOtherConfigFlag off;

  prefix $LAN64 {
    AdvOnLink on;
    AdvAutonomous on;
  };
};
EOF

    # Kea config: delegate /64s out of PD, but exclude LAN64 so it can't collide.
    # Prefix-exclude support (RFC 6603) exists in Kea. :contentReference[oaicite:9]{index=9}
    python3 - <<EOF > /run/kea-dhcp6.conf
import json, ipaddress, os

pd  = ipaddress.IPv6Network(os.environ["PD"], strict=False)
lan = ipaddress.IPv6Network(os.environ["LAN64"], strict=False)

cfg = {
  "Dhcp6": {
    "interfaces-config": { "interfaces": ["lan1010"] },

    "preferred-lifetime": 3600,
    "valid-lifetime": 7200,

    "lease-database": {
      "type": "memfile",
      "persist": True,
      "name": "/var/lib/kea/dhcp6.leases"
    },

    # We run RA separately; Kea only does PD here.
    "subnet6": [{
      "id": 1,
      "subnet": str(lan),
      "pd-pools": [{
        "prefix": str(pd.network_address),
        "prefix-len": pd.prefixlen,
        "delegated-len": 64,

        "excluded-prefix": str(lan.network_address),
        "excluded-prefix-len": 64
      }]
    }]
  }
}

print(json.dumps(cfg, indent=2))
EOF

    systemctl restart radvd.service
    systemctl restart kea-dhcp6.service
  '';
in
{
  environment.systemPackages = [ pkgs.python3 pkgs.iproute2 ];

  systemd.services.v6-pd-generate = {
    description = "Generate RA + Kea PD configs from ISP delegated prefix";
    wantedBy = [ "multi-user.target" ];

    after = [ "systemd-networkd.service" "pppoe-pap.service" ];
    wants = [ "systemd-networkd.service" "pppoe-pap.service" ];

    serviceConfig = {
      Type = "oneshot";
      ExecStart = applyScript;
    };
    path = [
      pkgs.iproute2
      pkgs.gawk
      pkgs.coreutils
      pkgs.python3
    ];
  };
}

