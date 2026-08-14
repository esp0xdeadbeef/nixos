# Cobalt site — implementation plan

## 1. Context

`cobalt` is a new site (element naming convention). It starts behind the home
ISP router (NAT) and later moves to a direct fiber connection.

- **Site name:** `cobalt` (`esp0xdeadbeef.cobalt`)
- **Router:** `s-router-cobalt` (nixos-shell VM, prod-pinned renderer stack)
- **IPv6:** no public IPv6 from the ISP; internal ULA is kept because the
  pinned CPM requires an IPv6 loopback. No public PD, no WAN IPv6.
- **WAN:** DHCP behind the ISP router for now; later direct fiber (see §6)
- **Client under test:** `l-portal`
- **Temporary router host:** `l-envil`

## 2. Locked decisions

1. `intent.nix` stays a **single shared file** and is **not filtered per site**.
2. The compiler compiles all sites in `intent.nix` and validates one inventory
   against all of them, so the compile uses a **combined inventory**
   (`inventory-all.nix`). Site-a's `inventory.nix` stays untouched.
3. Cobalt is **public-IPv4-only**: no public IPv6, no PD, no WAN IPv6. Internal
   ULA is retained to satisfy the CPM loopback invariant.
4. `s-router-cobalt` is a **lean** prod-stack VM (no site-a overrides).
5. Test behind NAT first, direct fiber second.

## 3. Data flow

```
intent.nix (site-a + cobalt)
        │
        ▼
network-compiler (compiles all sites)
        │
        ▼
network-forwarding-model
        │
        ▼
network-control-plane-model + combined inventory (site-a + cobalt)
        │
        ▼
network-renderer-nixos (renders ONE host)
        │
        ├── hostName = s-router-prod        → site-a render
        └── hostName = s-router-cobalt → cobalt render
```

## 4. Cobalt IP plan (must be distinct from site-a)

| Purpose | site-a | cobalt |
|---|---|---|
| p2p pool | `10.10.0.0/24` | `10.1.0.0/24` |
| p2p pool (ULA v6) | `fd42:dead:beef:1000::/118` | `fd42:dead:beef:2000::/118` |
| loopback pool | `10.19.0.0/24` | `10.1.1.0/24` |
| loopback pool (ULA v6) | `fd42:dead:beef:1900::/118` | `fd42:dead:beef:2900::/118` |
| core-dns resolver | `10.10.0.8` | `10.1.0.8` |
| VLAN 2 tenant | `192.168.1.0/24` | `10.2.2.0/24` |
| VLAN 3 tenant | `192.168.3.0/24` | `10.2.3.0/24` |
| VLAN 7 tenant | `192.168.2.0/24` | `10.2.7.0/24` |
| VLAN 8 tenant | `192.168.8.0/24` | `10.2.8.0/24` |

Cobalt drops the VLAN 3 service endpoints (`s-nebula-container`,
`s-llm-inference-container`) and their DNS/firewall records.

## 5. Model / renderer changes

Done so far:

- `prod-network/current/intent.nix` — added `esp0xdeadbeef.cobalt`
  (IPv4 tenants `10.2.<vlanid>.0/24`, ULA v6 pools, no public PD, no nebula/llm
  endpoints).
- `prod-network/current/dns-runtime-addresses-cobalt.nix` — cobalt resolver
  (`10.1.0.8`) and per-VLAN requester addresses.
- `prod-network/current/inventory-cobalt.nix` — cobalt realization
  (`s-router-cobalt`, `esp0xdeadbeef-cobalt-*`), DHCP WAN, no PPPoE.
- `prod-network/current/inventory-all.nix` — combined site-a + cobalt inventory.
- `nixos/virtual-machine/nixos-shell-vm/s-router-cobalt/` — lean prod VM.
- `nixos/virtual-machine/nixos-shell-vm/s-router-prod/renderers.nix` —
  parameterized identity and switched to `inventory-all.nix`.

Still open (compile iteration):

- `inventory-cobalt.nix` WAN uplink must become **VLAN 300 tagged** on `eth1`:
  ```nix
  upstream-core = {
    mode = "native";
    parent = "eth1";
    vlan = 300;
    bridge = "br-wan";
    ipv4 = { enable = true; dhcp = true; method = "dhcp"; };
  };
  ```
- The cobalt realization's p2p `link` names still need to be derived from the
  compiled cobalt model (the site-a hardcoded names differ because cobalt's
  communication contract differs).
- QEMU NICs: `br-cobalt-lan` (dock) + `br-cobalt-wan` (USB).

## 6. Direct ISP uplink (later phase)

- internet: **DHCP**, **VLAN 300**, **MTU 1500**
- cloned MAC address comes from **secrets** (not committed)

First NAT phase uses the same VLAN 300 for the WAN path through the switch;
behind the ISP router it is just DHCP on VLAN 300.

## 7. Physical topology — phase 1 (NAT, verified)

```
                home ISP router (untagged)
                         │
              Netgear GS108PEv3 port 4 (VLAN 300 untagged)
                         │
   l-envil USB (port 1) ─┴─ VLAN 300 (tagged toward the cobalt WAN container)
   l-envil dock (port 3) ─── LAN trunk: VLANs 2/3/7/8 tagged
   l-portal USB (port 2) ─── VLAN 8 untagged (IOT)
```

Verified port map (via `netgear-admin` disable probe):

| switch port | device | role |
|---|---|---|
| 1 | l-envil USB (`enp0s13f0u4u4u3`) | WAN (VLAN 300) |
| 2 | l-portal USB (`enu1u1`) | portal (VLAN 8) |
| 3 | l-envil dock (`enp170s0`) | LAN trunk (2/3/7/8) |
| 4 | ISP router | WAN (VLAN 300 untagged) |
| 5–8 | — | empty |

- `l-envil` = `100.64.0.13` (nebula overlay), wifi + usb eth + dock eth.
- `l-portal` = `100.64.0.14` (nebula overlay), wifi + usb eth.

### How the topology was enumerated

1. **Host NIC inventory (read-only)** — over the nebula overlay, `ip -brief addr`
   and `ip -brief link` on `l-envil`/`l-portal` gave the NICs and their IPs.
2. **Switch discovery** — the switch was not at its factory-default
   `192.168.0.239`; it had a DHCP lease from the ISP router. An
   `nmap -p 80 192.168.1.0/24` scan found it at `192.168.1.47`.
3. **Identify + login** — `ngp-cli` (`py-netgear-plus`) → `GS108PEv3`; logged in
   with the factory default password.
4. **Port status** — `ngp-cli --json status` gave per-port up/down + link speed:
   ports 1-4 up (`1000/100/1000/1000`), ports 5-8 down.
5. **Speed correlation** — `l-portal`'s USB NIC was the only 100M host NIC, so
   port 2 (the only 100M port) = `l-portal`.
6. **Deterministic disable probe** — `netgear-admin` disabled one port at a time
   while we watched which host went unreachable:
   - disable port 1 → `192.168.1.20` (`l-envil` USB) unreachable → **port 1 =
     l-envil USB**; re-enable.
   - disable port 3 → `192.168.1.25` (`l-envil` dock) unreachable → **port 3 =
     l-envil dock**; re-enable.
   - port 4 = **ISP** by elimination (the remaining live uplink).

The nebula overlay (`100.64.0.13/.14`) plus the LAN IPs was the control plane,
so disabling a data-plane port never cut the management channel.

## 8. Switch provisioning (Netgear GS108PEv3)

Switch: **NETGEAR GS108PEv3**, management at `192.168.1.47` (DHCP), firmware
`V2.06.10EN`. Admin password is a secret (set via `PROSAFE_VLAN_PASSWORD`).

Applied VLAN config (see `prod-network/cobalt/switch-vlan.toml`):

- Advanced 802.1Q VLAN: **enabled**
- VLANs: `1`, `2`, `3`, `7`, `8`, `300`
- PVIDs: `1→1`, `2→2`, `3→1`, `4→300`, `5-8→1`

Tooling (all in the flake):

- `pkgs/prosafe-vlan` — `PotatoMania/prosafe-vlan-manager` + `patches/prosafe-vlan-cobalt.patch`
  (adds `--change-pw-allowed`, `change-password`, auto 802.1Q enable, chained apply)
- `pkgs/netgear-admin` — `ElectricLab/netgear_admin` + `patches/netgear_admin-gs108pev3.patch`
  (port status/enable/disable for GS108PEv3)
- `pkgs/cobalt-switch` — derivation that runs the switch apply with the bundled TOML.

  The admin password is stored in `secrets/cobalt-switch-gs108pev3.yaml`
  (single `password` entry, encrypted to root+deadbeef on l-esp/l-envil/l-portal):

  ```sh
  export PROSAFE_VLAN_PASSWORD="$(sops --decrypt --extract '["password"]' secrets/cobalt-switch-gs108pev3.yaml)"
  nix run .#cobalt-switch
  ```

  This chains: (if needed) factory-default password change → enable 802.1Q →
  apply VLAN config.

- Change the admin password explicitly (regular `user.cgi` flow):

  ```sh
  export PROSAFE_VLAN_NEW_PASSWORD="$(sops --decrypt --extract '["password"]' secrets/cobalt-switch-gs108pev3.yaml)"
  export PROSAFE_VLAN_OLD_PASSWORD='…'
  nix run .#prosafe-vlan -- change-password -a 192.168.1.47 -m gs108ev3
  ```

## 9. Implementation status

1. `README.md` naming convention — ✅
2. Add cobalt to `intent.nix` — ✅
3. Cobalt DNS runtime addresses — ✅
4. `inventory-cobalt.nix` — ✅ (WAN still needs `vlan = 300`)
5. `inventory-all.nix` + renderers wiring — ✅
6. `s-router-cobalt` VM — ✅ (QEMU bridges pending host setup)
7. Register VM on l-envil + host bridges — pending
8. Switch VLAN provisioning — ✅ (applied + tcpdump-validated)
9. Compile iteration (cobalt link names, WAN VLAN 300) — in progress
10. Boot, attach l-portal, verify DHCP + internet — pending

## 10. Verification

- `nix flake check --all-systems`
- build cobalt image:
  ```sh
  nix build .#nixosConfigurations.s-router-cobalt.config.system.build.nixos-shell --no-link
  ```
- Switch L2 validated with tcpdump:
  - l-portal untagged → trunk sees **VLAN 8** tagged ✅
  - ISP untagged → l-envil USB sees **VLAN 300** tagged ✅
  - trunk shows **no VLAN 300** ✅
- l-portal on VLAN 8 gets a DHCP lease and Internet (IOT lane, isolated from VLANs 2/3/7).

## 11. Open questions / resolutions

- **VLAN 3 service endpoints** — dropped from cobalt.
- **Cobalt IP plan** — tenants `10.2.<vlanid>.0/24` confirmed; p2p/loopback
  `10.1.0.0/24` / `10.1.1.0/24` adopted (still adjustable).
- **`prosafe-vlan` GS108PEv3 driver** — currently uses the `gs108ev3` driver
  (same firmware family, same pages); add a `gs108pev3` alias if any
  page-structure drift shows up.
- **`render.hosts` multi-site shape** — the combined inventory currently carries
  site-a's legacy role-keyed `render.hosts`; renderer falls back to
  `deployment.hosts.<host>.wanUplink`. Revisit during cobalt compile iteration.
