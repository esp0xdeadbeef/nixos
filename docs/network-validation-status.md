# network-* validation status (BLOCKED)

Snapshot of the cross-repo test validation of the `~/github/network-*` tree.
Nothing here is deployed; no protected path (`prod-network/prod/`,
`prod-network/current/`, prod host configs, secrets) was read or modified.

## Matrix as measured

| repo | passing / total |
|---|---|
| network-compiler | 81 / 81 |
| network-control-plane-model | 143 / 158 |
| network-forwarding-model | 71 / 74 |
| network-renderer-nixos | 55 / 73 |
| network-labs | 391 / 516 |
| network-codex-agent | 192 / 273 |
| network-realization-model | 0 tests for 49 owned SMS atoms |
| network-nebula | 9 / 10 |
| network-wireguard | 7 / 8 |
| network-renderer-access-endpoint | 14 / 14 |
| network-containerlab | 3 / 3 |

## Fixed during this run

- `network-labs` `c69719f1`: 41 row-local cases counted exit uplinks with
  `builtins.length (… .uplinks or { })` although `uplinks` is an attrset; the
  `length` call threw and masked every predicate after it. `builtins.attrValues`
  restores the intended "exactly one exit uplink" check. 34 of the 39 affected
  rows now pass end-to-end; the remaining 5 are not structural failures.
- `network-labs` `3023dcbc`: FS-200 fixture modelled the forbidden direct
  `client-edge ↔ core` link (URS §210 / FS §50) and asserted the superseded
  `to.name == "testnet"` exit (FS-322). FS-540's fixture keyed its payload
  `auto` instead of the trace id, and carried a private `addressPools` shape no
  consumer reads. Both fixtures now match the canonical intent contract.
- `network-renderer-nixos` `ad30997`: `test-dns-service-policy-routes` called
  `lib.hasInfix` on a 138 KB nftables ruleset, which overflows the stack and
  aborted the whole eval, hiding four genuinely false checks behind
  "nix eval crashed". Matching one rendered rule line at a time removes the
  overflow; the DNS rules are also saddr-scoped, so the three fragments must be
  matched on one line rather than as one contiguous string.
- `network-renderer-nixos` `585066e`: two checks compared route destinations
  against zero-padded IPv6 literals while destinations are emitted canonically.
  Gateways are copied verbatim from inventory and keep their padded text.

## BLOCKED items

1. Three checks in `FS-540-HDS-010-SDS-010-SMS-040` disagree with the rendered
   lane assignment and cannot be settled from the renderer output:

   - `branch_hostile_public_default_uses_overlay` expects `::/0` via
     `fd42:dead:feed:1000:0:0:0:4` on the `10-pol-hostile-ew` table; the config
     has `::/0` only on `10-core-isp`, table 1005, via `…:6`.
   - `sitea_mgmt_wan_dns_v4` expects `10.20.10.0/24` via `10.10.0.50` on
     `10-core-a`; the route exists on `10-pol-mgmt-a` via `10.10.0.46`.
   - `sitea_mgmt_wan_dns_v6` expects `fd42:dead:beef:10::/64` via
     `fd42:dead:beef:1000:0:0:0:32` on `10-core-a`; the route exists on
     `10-pol-mgmt-a` via `…:2e`.

   `policyTableFor` in the case infers "the table for this relation" from the
   first non-main policy rule on an interface, which is not a property of any
   individual relation. Choosing between the two by editing the expectations to
   match the renderer would rubber-stamp the implementation instead of testing
   it, so the owning FS text for the mgmt WAN return lane and the hostile
   default must decide it.

2. The renderer emits each prefix twice on the same network and table: once with
   the zero-padded text taken from intent (`fd42:dead:beef:0010:…/64`) and once
   in canonical computed form (`fd42:dead:beef:10::/64`). Whichever layer owns
   route generation must emit one canonical route; until then, checks that
   correlate a route with a table can match only the duplicate.

3. Rows that need newer `network-control-plane-model` behaviour cannot be
   exercised from here: the renderer and lab repos load CPM through the flake
   lock, and the CPM fixes for those rows are unpushed local commits
   (`5eb0df7`, `4ca875b`, `d5ed172`), so `nix flake lock` correctly keeps the
   published `eb5a5ff`. Publishing them needs explicit push permission.
