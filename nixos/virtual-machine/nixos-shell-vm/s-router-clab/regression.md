# s-router-clab Regression State

Last updated: 2026-05-12 01:05 UTC.

This file is current-state evidence only. Older entries are stale until
reverified.

## Fixed and Live-Verified

- No current CLAB production-readiness result is verified after the latest
  aborted full-lab run.

## Fixed but Only Locally Tested

- The host-side `s-router-clab-render-live` service now calls the render
  application through an absolute store path instead of relying on systemd PATH.
- Local eval passed:
  `nix eval /home/deadbeef/github/nixos#nixosConfigurations.s-router-clab.config.systemd.services.s-router-clab-render-live.description --raw`.
- `s-router-clab/host-deploy.nix` and the legacy nested
  `container/deploy.nix` now generate `resolved-inventory-clab.nix` from
  `getResolvedInventory.nix { renderer = "clab"; }` before calling CPM.
- Local CPM compile with that resolved CLAB inventory passed, and the
  `esp0xdeadbeef-hetz-c-router-access-dmz` DNS forwarders resolve to literal
  IPv4/IPv6 addresses: `1.1.1.1`, `9.9.9.9`, `2606:4700:4700::1111`,
  `2620:fe::fe`.
- Focused guard passed:
  `bash tests/test-s-router-test-containerlab-gate.sh`.
- `network-codex-agent` now refuses to treat the CLAB VM matrix launcher as a
  result. The parent loop scans worker logs/status files and fails on current
  worker runtime failures.
- `network-renderer-containerlab-linux-backend` commit `98ef0b6` writes a
  status file for every matrix worker.
- `network-renderer-containerlab-linux-backend` commit `648d523` materializes
  single-endpoint overlay interfaces as Containerlab links, fixing the observed
  `core-nebula eth3` startup-command/link mismatch for
  `single-wan-with-nebula`.
- `network-codex-agent` now clears the detached CLAB VM matrix worker root
  before every matrix launch so stale worker logs cannot fail a new run.

## Implemented but Not Yet Live-Validated

- `s-router-clab` imports `./host-deploy.nix`.
- `host-deploy.nix` renders the locked CLAB topology on the host and asks the
  nested `s-router-clab-container` only to run Docker/Containerlab against the
  rendered YAML. This avoids the nested container's read-only Nix database.

## Still Broken

- No full-lab loop has completed after the resolved CLAB inventory patch.
- Current visible Docker state is stale and invalid. The live
  `s-router-clab-container` still shows `clab-fabric-*` containers created
  seven days earlier, and `clab-fabric-espbranch-site-b-b-router-upstream-selector`
  has only `lo` in `ip a`.
- The last full-loop CLAB matrix state was red. Worker logs showed missing
  required host bridges after 120 seconds, missing runtime target containers,
  `containers not found`, and Nix eval failures for deleted `vm-network.nix`
  files.

## Pending / Unknown

- Whether the next boot/deploy creates Docker network `clab`.
- Whether every `clab-fabric-*` router gets at least one non-loopback data-plane
  interface.
- Whether FRR `zebra` crashes recur after a real Containerlab deploy.

## Next Concrete Debugging Target

- Do not rerun `scripts/s-router-full-lab-rebuild-loop.sh` until the preserved
  observed runtime failures are fixed or deliberately retired. The loop now
  hard-blocks on those files before rebooting or spawning validators.

## Assumptions in the Wrong Layer

- CLAB must materialize explicit CPM/provider output. It must not infer missing
  topology, routing, firewall, DNS, or overlay meaning from names.
- A running Docker container is not proof of realized network topology.
