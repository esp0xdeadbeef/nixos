# s-router-nixos DHCP test client

This is a **lab-only** test fixture on the `s-router-nixos` test router. It is
not production network meaning and must not be imported by a production host.

The fixture is a NixOS container (`dhcp-test`) attached to the
`access-local` client-facing bridge (`dns545nl` in the current
`network-labs` lab). It runs a DHCPv4 client on `eth0`, so it exercises the
same path as a real access client:

1. DHCP lease from the rendered Kea server on `access-local`;
2. default route through `access-local` -> `downstream-selector` -> `policy`;
3. egress through `core-primary` and the lab WAN.

## On/off switch

`sRouterNixosTestDhcpClient.enable` defaults to `true` on this test host.
Set it to `false` to remove the container:

```nix
sRouterNixosTestDhcpClient.enable = false;
```

## Validation

Build and roll out the test router, then inspect the client:

```bash
nix build .#nixosConfigurations.s-router-nixos.config.system.build.nixos-shell
sudo vm-update s-router-nixos /path/to/nixos

sudo vm-exec s-router-nixos /run/current-system/sw/bin/bash -lc '
  /run/current-system/sw/bin/nixos-container run dhcp-test -- \
    /run/current-system/sw/bin/ip -br addr
  /run/current-system/sw/bin/nixos-container run dhcp-test -- \
    /run/current-system/sw/bin/ip route
  /run/current-system/sw/bin/nixos-container run dhcp-test -- \
    /run/current-system/sw/bin/ping -c 2 -W 2 10.54.46.1
  /run/current-system/sw/bin/nixos-container run dhcp-test -- \
    /run/current-system/sw/bin/ping -c 2 -W 2 198.18.45.1
'
```

Observed lease: `10.54.46.101/24`, default via `10.54.46.1`. Gateway/WAN ping
currently fails in the lab `access-local` model (DNS-only); the lease path is
proven, egress policy is the next fix.

The current access segment is `access-local` (`lan0 10.54.46.1/24`,
`kea-dhcp4-local-client.service`, `radvd-lan0.service`). If the lab renames
the bridge, update this fixture with the lab; do not move the behavior into a
production host.
