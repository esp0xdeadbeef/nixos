# network-* CI validation status

Verified state of the `~/github/network-*` check suites, the fixes landed this
run, and the one remaining contract gap that blocks the rest.

## Verified green (GitHub Actions)

| repo | commit | result |
| --- | --- | --- |
| network-compiler | `27080ef` | success |
| network-forwarding-model | `ec16160` | success (81/81) |
| network-labs | `3a710c36` | success (42/0) |
| network-realization-model | `b6ab76a` | success (`nix flake check`) |
| network-realization-schema | `6881bff` | success (`nix flake check`) |
| network-access-endpoint | `01de9c3` | success |
| network-renderer-nebula | `7054765` | success (15/15) |
| network-renderer-wireguard | `dc39a38` | success (PR #1) |
| network-renderer-containerlab-linux-backend | `f90dc63` | success (full suite) |

## Fixed this run (network-control-plane-model)

- `64ec24f`: named-core DNS listener/forwarder is the relation's emitted terminal
  attachment endpoint, never the resolver loopback (FS-540-HDS-010-SDS-010-SMS-020
  "An ownership loopback is not a substitute"; SMS-035 "a node loopback ... shall
  not be substituted"). FS-540-010/020/025/030/035/040/045 green in CI.
- `7a4a1c6`: FS-525 named-core and egress cases assert the emitted endpoint and
  the declared `egressSurface` determinism.
- `f7903c9`: requester-lane resolver endpoint reachability. SMS-020 requires
  "relation-owned requester-lane route authority containing policy table,
  outgoing lane, selected next-hop identity, and provenance for each requested
  family and resolver endpoint prefix", and SMS-040 defines its keying. The
  control plane is the owning writer: the admitted relation, the resolver
  endpoint, the requester access lane and the lane next hop are all modelled
  inputs, so emitting the requester leg materializes existing authority (URS
  "Only modeled authority can create network behavior") and does not re-derive
  upstream meaning (FS-171). It is emitted only on admitted downstream access
  lanes, never on exit/uplink lanes (FS-550), never fanned out to unadmitted
  siblings (SMS-040), and deduplicated against the destination pass (FS-315).
  `test-dns-service-policy-routes`, `test-runtime-origin-loopback-egress` and
  `test-network-labs-inventory-sweep` (21 outputs) pass; CPM suite 224 PASS with
  the same 18 pre-existing reds as `64ec24f^`.

The earlier claim that this requester lane "violates FS-171" was wrong and is
retracted: both the URS layer-ownership rules and FS-171 assign the
realization-of-modelled-authority case to the layer that writes the canonical
target routes, which is the control plane, not the forwarding model.

## Update: this run (FS-540/FS-550 control-plane work)

`network-control-plane-model`:
- `f7903c9` requester-lane resolver endpoint reachability (FS-540 SMS-020/040).
- `b93dc61`, `36237e7`, `ccf641b`, `45b313a` policy-lane selected-exit defaults
  complemented from the peer end of the modeled link, gated on the modeled
  runtime-origin source relation (FS-540 SMS-045, FS-550, FS-315), and the
  lane-less runtime-origin prefix removed from policy exit main tables.
- `adc93ea` blocker note updated.
- Full suite: 225 PASS / 17 FAIL; every remaining failure also fails on the
  pre-change revision.

`network-renderer-containerlab-linux-backend`: CI success (`f90dc63`).

`network-renderer-nixos`:
- `320bb23` maps the canonical route `table` field to systemd `Table` and drops
  the lane-less twin of a lane-assigned route (FS-315), which removes the
  runtime-origin prefix from policy exit main tables.
- `1381a05` client2 policy test migrated to the source-scoped deny-by-default
  contract (FS-180/FS-540).
- CI: 22 PASS / 4 FAIL (was 21/5).

## This run: policy-table parity fixed, tri-site fixture blocker confirmed

- `network-control-plane-model` `c2cb1dc…2c7d382`: the ingress policy lane now
  carries the selected exit default for each modeled accept rule (access lanes
  only, deduplicated, stamped with the family), so the ingress table resolves
  the exit (FS-315). Full suite unchanged at 225 PASS / 17 FAIL with no
  regressions.
- `network-renderer-nixos` `26de894`: the policy-table parity case asserts the
  kernel table carries the default (tables are global) instead of pinning the
  network it is attached to. Renderer suite is now 23 PASS / 3 FAIL (was 22/4).

## Remaining gap (BLOCKED)

`network-renderer-nixos` has three reds:

1. `test-overlay-core-local-hostile-return-routes.sh` and
   `test-transit-endpoint-return-routes.sh` use the private fixture
   `tests/fixtures/tri-site-s-router-overlay-egress`, which predates FS-322
   (access `selects`), FS-460 (overlay `peerNodes` endpoint identity, overlay as
   egress surface) and fails successive compiler diagnostics. A partial
   migration was attempted and reverted rather than left half-applied.
2. `test-runtime-origin-loopback-egress-render.sh` asserts an older topology
   (`up-client-b`, `pol-client-a/-b`, core runtime-origin `10.19.0.8/32`) that
   the fixture no longer models (it now carries `up-cli-ew`, `up-client-a` and
   tenant DNS origin prefixes). The main-table leak it guards is fixed.

All three need one authoritative tri-site overlay example with a host inventory
in `network-labs`; that repository has no tri-site overlay example, and the
forwarding model's tri-site fixture is intent-only. Hand-editing the private
copy again would re-create the drift this work is removing, so the fixture
migration is blocked on that canonical source (or on permission to add the
example to `network-labs`).

Concrete migration attempts this run (all reverted, no repo left half-migrated):

1. Copied the forwarding model's compiler-clean tri-site intent into
   `network-labs` with the renderer's private inventory: failed with
   `inventory.realization.nodes.esp-edge-example-router-nebula-core.ports.east-west.uplink:
   references unknown site uplink 'east-west'` — the private inventory encodes
   the pre-FS-460 model (overlay name as a routed site uplink).
2. Removed that legacy overlay-uplink port and re-used the forwarding model's
   intent over the private inventory: the inventory lint passed, then the
   forwarding model rejected the result with
   `forwardingModel.enterprise.esp.site.edge.domains.tenants: tenant 'client'
   requires a derived dnsDomain or zone reference for DHCP advertisement
   derivation` — the private inventory's DHCP advertisements do not carry the
   tenant domain facts the current forwarding model derives from.

So the canonical example needs a purpose-written inventory against the current
FS-460/FS-322 domain and overlay contracts, not a port of the private one.

3. Authored `network-labs/examples/tri-site-s-router-overlay-egress` from the
   forwarding model's compiler-clean intent plus the private inventory, then
   iterated against the compiler/FM:
   - tenant prefixes lacked `dnsDomain` (added `dnsDomain = "lan."` to all 33
     tenant prefixes: `forwardingModel…domains.tenants: tenant 'client' requires
     a derived dnsDomain or zone reference for DHCP advertisement derivation`);
   - the inventory had no port realization for the current access-to-uplink
     lanes (`…requires explicit port realization for backing link
     'link::esp.home::p2p-…-hostile--uplink-isp-a'`); added both ends of each
     lane plus the host bridge;
   - the intent then failed semantic validation at the forwarding model:
     `forwardingModel.enterprise.esp.site.home.communicationContract.relations.allow-wan-to-dmz-nebula.from:
     service exposure scope binding requires requester scope to name an external
     or uplink`.

   In other words the forwarding model's tri-site intent is itself stale against
   the current compiler contract (service-exposure requester scopes), while its
   inventory is stale against FS-460. Producing a conforming example therefore
   needs a purpose-written intent *and* inventory, not a port of either existing
   artifact. The attempt was reverted; `network-labs` and the renderer are clean.

4. Continued the same attempt: added `scope = "<site>-example-router-core-*"` to
   all 17 bare `from = { kind = "external"; }` relations (the compiler accepts
   `scope`), then re-ran the port/bridge synthesis. The synthesized ports kept
   landing on the wrong end (`upstream-hostile-wan` ended up in the upstream
   selector's `ports` instead of the policy node, producing a duplicate
   `interface.name`), i.e. the two artifacts disagree about which node owns the
   lane ends and about host/bridge placement. Automated port synthesis cannot
   resolve that disagreement without a modeling decision per lane.

   The upstream selector lane set, the access-to-uplink lane set, and the host /
   bridge placement must therefore be authored deliberately for the example.
   Every attempt was reverted; no repository is left half-migrated.

Recorded upstream: `network-renderer-nixos:docs/blockers.md` (`c378477`) and
`network-control-plane-model:docs/blockers/remaining-ci-reds.md` (`de27394`).

## Final CI sweep (all 11 repositories)

Checked via the GitHub API (latest workflow run per repository):

| repo | head | conclusion |
| --- | --- | --- |
| network-compiler | `27080ef` | success |
| network-forwarding-model | `ec16160` | success |
| network-labs | `3a710c3` | success |
| network-control-plane-model | `de27394` | failure: 17 known reds, identical to the pre-change baseline |
| network-realization-model | `b6ab76a` | success |
| network-realization-schema | `6881bff` | success |
| network-access-endpoint | `01de9c3` | success (last recorded run) |
| network-renderer-nebula | `7054765` | success |
| network-renderer-wireguard | `dc39a38` | success |
| network-renderer-containerlab-linux-backend | `f90dc63` | success |
| network-renderer-nixos | `c378477` | failure: 23 PASS / 3 FAIL |

The control plane's 17 reds are the pre-existing module/example migrations listed
above; every one also fails on `64ec24f^` (two more were fixed during this work:
`FS-525-…-SMS-010` and `test-dns-service-policy-routes`, plus the policy-table
parity case in the renderer).

## Why the last three reds are blocked (ownership, not effort)

`test-overlay-core-local-hostile-return-routes`, `test-transit-endpoint-return-routes`
and `test-runtime-origin-loopback-egress-render` need a conforming tri-site
overlay example. The URS assigns intent to the user: "Intent: User-owned desired
behavior such as tenants, services, DNS policy, what each scope reaches and
offers…" and the repository AGENTS forbids inventing behavior. Authoring the
example therefore requires operator-owned modeling decisions that this run
cannot make:

- which exit scopes each access selects (the stale intent names none; the
  compiler rejects bare external scopes once service exposure is modeled),
- the tenant DNS domains for DHCP advertisement derivation,
- the overlay endpoint identities and underlay provider facts (FS-460),
- the access-to-uplink lane set and the host/bridge placement for each lane end.

Every attempt to derive these from the two existing artifacts was reproduced and
reverted (unknown site uplink, missing tenant dnsDomain, service-exposure scope
binding, and a lane-end/host placement disagreement that duplicated
`interface.name`). The example must be authored deliberately, with those
operator decisions, before the three cases can be validated.

## New evidence on the two overlay service-ingress reds (control plane)

`test-sitec-overlay-service-ingress` was decomposed with the same predicate the
case uses. Current model output versus the case's expectation:

| predicate | model | case expects |
| --- | --- | --- |
| `dns.allowFrom` host entries | `100.96.10.1/24`, `100.96.10.254/24`, `fd42:dead:beef:ee::1/64`, … | `100.96.10.1/32`, `fd42:dead:beef:ee::1/128` |
| policy dmz lane route to the overlay endpoint | absent | `100.96.10.1/32 via 10.80.0.17` |
| overlay interface link route | absent | `100.96.10.1/32` with `intent.kind = "overlay-node-reachability"` |
| upstream forward and return rules | present | present |

So two distinct defects remain in the control plane, both owning-layer work:
the DNS `allowFrom` uses overlay-subnet masks where the modeled resolver-source
identity is a host address (an ACL widening under FS-171 least privilege), and
the overlay peer endpoint reachability is not emitted on the policy lane or the
overlay interface for this site (FS-460 overlay reachability).

`test-s-router-hetz-overlay-dns-ingress` fails on the same missing overlay
reachability; `test-example-overlay-upstream-policy-defaults-preserved` could not
complete because the remote builder refused the connection
(`cannot build on 'ssh-ng://nix-ssh@s-tau-builder'`), which is an environment
failure to retry, not a model result.

These are actionable but not completed: each needs a deliberate change to the
overlay reachability emission (peer endpoint identity, per-lane route authority)
that must be checked against FS-460 and the URS overlay-transport sentence before
landing, and the ACL normalization needs a decision on whether the overlay node
address or its subnet is the modeled requester identity for that relation.

## This run: two overlay DNS cases fixed, one lane-decision case remains

`network-control-plane-model`:
- `31f27bc`: overlay endpoints are host identities. The overlay node record
  (route destinations) and the cross-site DNS ACL entries now use `/32` and
  `/128` instead of the interface subnet mask, with the node's own address
  compared by host part. `test-sitec-overlay-service-ingress` passes.
- `d8aaea7`: `overlay-ingress-routes.nix` emits, on the overlay termination
  node, one route per provider tenant prefix through the modeled underlay uplink
  lane (relation id + `overlay-ingress-return` provenance).
  `test-s-router-hetz-overlay-dns-ingress` passes after migrating its assertion
  from a snapshot interface name to the modeled lane kind/uplink.
- `50ab58d`: blocker note updated.
- Full suite: **227 PASS / 15 FAIL** (was 225/17), no new failures.

Remaining overlay case: `test-example-overlay-upstream-policy-defaults-preserved`
expects a per-uplink default on all five site-a access lanes at the upstream
selector; the forwarding model emits three and places `client`/`client2` on a
combined lane (`lane.uplink = null`). Deciding whether the combined lane or the
per-uplink lane is authoritative is a forwarding-model lane decision (FS-315),
not a control-plane repair.

The three `network-renderer-nixos` reds are unchanged (tri-site fixture needs
operator-owned intent; see the blocker below).

## Blocker status

The remaining work is (a) the forwarding-model lane decision above, and (b) the
operator-owned tri-site intent/inventory for the three renderer cases. Both are
model decisions outside what this run may invent (URS: intent is user-owned;
FS-171 single writer).

## Lane-model finding for the last control-plane red

`test-example-overlay-upstream-policy-defaults-preserved` expects the upstream
selector's core-facing interface to carry a per-access default with
`lane.uplink = "isp-a"` for all five site-a accesses. The compiled model shows:

- `admin`, `mgmt`, `streaming`: per-uplink defaults on the selector core link;
- `client`, `client2`: defaults exist, but as `lane.kind = "access-edge"` with
  `uplink = null` on the downstream-selector -> policy link (e.g.
  `via 10.10.0.27` / `10.10.0.29`), never on the selector core link.

All five accesses model the same selection (`isp-a` only per the intent), so the
asymmetry is a lane-construction decision in the forwarding model: some defaults
are represented as combined/edge lanes and propagated downstream, others as
per-uplink lanes at the selector. FS-315 allows a lane as its own selection
authority, so either representation can be correct, but the two cannot differ
for the same modeled selection. Deciding which form is authoritative (and making
it uniform) is a forwarding-model change, not a control-plane repair; the test
must then assert that form.
