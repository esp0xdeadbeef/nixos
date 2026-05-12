# s-router-test Regression State

Last updated: 2026-05-12 03:32 UTC.

This file is current-state evidence only. Older entries are stale until
reverified.

## Fixed and Live-Verified

- Hetzner validator deploy path booted the expected system on server
  `130500355`. The run verified SSH return, IPv4/IPv6 route probes, IPv4 ping,
  and `/run/current-system` matching
  `/nix/store/g7qaj9r2ir7wmd0dh3pa3i306fwkrhrk-nixos-system-hetzner-nebula-prodtest-01-25.11.20260501.26ef669`.
- Local `s-router-test`, `s-router-test-clients`, and Hetzner toplevel builds
  passed in the locked full-loop run that started at `2026-05-12 01:18 UTC`.
- `s-router-clab` rebuild loop passed in that run.

## Fixed but Only Locally Tested

- `network-codex-agent` now starts Hetzner deploys in a named tmux window.
- `network-codex-agent` now sources the Hetzner deploy command file from an
  interactive `bash -li` tmux shell, so Ctrl-C returns to that shell instead of
  hiding the deploy in an opaque child process.
- `network-codex-agent` now fails the CLAB rebuild loop quickly after SSH
  returns if `s-router-clab-render-live.service` is failed, if stale
  `clab-fabric-*` containers exist without Docker network `clab`, or if any
  router container has only `lo`.
- Focused local guard passed:
  `bash tests/test-s-router-test-containerlab-gate.sh`.
- Focused Hetzner tmux/deploy guard passed:
  `bash tests/test-s-router-test-hetzner-deploy-guards.sh`.
- The CLAB deploy path now feeds resolved lab inventory to CPM instead of raw
  `inventory-clab.nix`. Local CPM compile with the generated resolved wrapper
  passed and produced literal DNS forwarders for the Hetzner DMZ resolver.
- `network-control-plane-model` now fixes the previously red delegated IPv6
  overlay public-egress handoff and unsafe core-nebula to WAN forwarding
  contract. Verified locally with:
  `bash tests/test-delegated-overlay-public-egress.sh`,
  `bash tests/test-upstream-selector-nebula-underlay-core-transit.sh`,
  `bash tests/test-policy-deny-precedence.sh`,
  `bash tests/test-transit-default-routes-are-classified.sh`, and
  `bash tests/test-network-labs-inventory-sweep.sh`.
- `network-control-plane-model` now materializes service-target denies on
  policy routers, including the minimal `priority-stability` fixture. The
  locked `network-labs` inventory sweep passed across 44 outputs.
- `network-forwarding-model` expected output counts are refreshed for the
  current locked `s-router-overlay-dns-lane-policy` output. Verified locally
  with `bash tests/test-network-labs-output.sh`.
- `network-codex-agent` full-lab loop now waits for network repo tests before
  reboot when `NETWORK_REPO_TEST_GATE=pre-reboot` (default), so model/render
  contract failures hard-stop before the script restarts `s-router-test`.
  Verified locally with `bash -n scripts/s-router-full-lab-rebuild-loop.sh`.

## Fixed but Only Locally Tested

- `network-renderer-containerlab-linux-backend` commit `98ef0b6` and the local
  `network-codex-agent` orchestration patch make CLAB VM matrix worker failures
  visible to the parent loop through worker status files and log scanning.
- `network-renderer-containerlab-linux-backend` commit `648d523` fixes a
  renderer materialization bug where single-endpoint overlay interfaces were
  configured by runtime commands but dropped from the Containerlab link graph.
  The focused `single-wan-with-nebula` renderer regression passes locally.
- `network-codex-agent` now blocks the full loop before doing any restart work
  while observed runtime failure tests exist.
- `network-codex-agent` now patches the reused Hetzner validator deploy path to
  use the correct expected-system flake attr and to add temporary build swap
  before remote build/rebuild work.
- `network-codex-agent` now clears the detached CLAB VM matrix worker root
  before every matrix launch. The `2026-05-12 01:15 UTC` CLAB worker failure
  was from a stale `clab-worker-0.K4jib8.log`, not current renderer output.
- The NixOS tree is still dirty with unrelated runtime and client changes; this
  file does not treat that dirty state as production evidence.

## Implemented but Not Yet Live-Validated

- `s-router-clab` has a local host-side render/deploy service patch. It renders
  the locked model on the host and asks the nested container only to run
  Docker/Containerlab against already-rendered YAML.
- The host-side CLAB render service now uses an absolute store path and
  explicit runtime inputs. Local `nix eval` of the service description passed.

## Still Broken

- The latest full-loop run failed at `2026-05-12 01:35 UTC` while pushing the
  transient Nebula CA passphrase to `s-router-test`:
  `Failed to connect to system scope bus via machine transport: Host is down`.
- `s-router-test` is not production-ready. DNS, route selection, nftables,
  Nebula reachability, DNS-over-overlay, lane preservation, hostile GUA return,
  and leak-prevention checks have not all passed on one locked returned
  generation.
- Current live router validation is red. Site A access containers can resolve
  through the modeled resolver, but `b-router-access-branch` and
  `b-router-access-hostile` get DNS timeouts through their rendered forwarders.
  Direct branch queries to `10.20.10.1` and `fd42:dead:beef:10::1` time out,
  while same-site queries from `s-router-access-mgmt` and
  `s-router-access-client` succeed.
- Live route evidence shows branch traffic to `10.20.10.1` is routed toward
  the branch core Nebula path, and Nebula endpoint pings between
  `s-router-core-nebula` and `b-router-core-nebula` work. The next target is
  the cross-site DNS forward/return path through policy/upstream/core firewalls
  and route tables.
- The last verified CLAB live state was stale and invalid: `clab-fabric-*`
  router containers had only `lo`, Docker network `clab` was missing, and the
  old host render service failed with `exec: s-router-clab-render-live: not
  found`.

## Pending / Unknown

- Whether the current CLAB VM matrix examples finish after the renderer
  single-endpoint overlay fix. No fresh observed-runtime-failure file was
  created before the full-loop run failed on the `s-router-test` host path.
- Whether the Hetzner validator passes Nebula, DNS-over-overlay,
  BGP/firewall assumptions, and leak-prevention checks after the local CPM/FWM
  fixes are committed, pushed, locked downstream, and live-validated.
- Whether the previously observed branch/core Nebula egress failures still
  exist after the latest locked rebuild.

## Next Concrete Debugging Target

- Commit and push the `network-forwarding-model`,
  `network-control-plane-model`, and `network-codex-agent` fixes, propagate
  locks through the downstream chain, then rerun
  `scripts/s-router-full-lab-rebuild-loop.sh` through the locked chain.

## Assumptions in the Wrong Layer

- Renderers and harness code must not infer routing, DNS, firewall, host
  placement, or topology semantics from names.
- Link deduplication and topology shape belong upstream in the model/control
  plane layer, not in renderers or local scripts.
- Runtime deployment realization is not proven by Docker container presence.
  The CLAB host/container layer must prove the generated topology was deployed
  and every router has non-loopback data-plane interfaces.
