# `s-router-test` Security Regression Log

Verified on 2026-04-24. Treat older conclusions as stale.

## Fixed And Live-Verified

- Current BGP wrapper host is live on a dry-run-matching hash:
  - expected `/nix/store/4j0as93d9bi7qzgifpn6is3m27xslwbq-nixos-system-s-router-test-25.11.20260421.10e7ad5`
  - returned `/nix/store/4j0as93d9bi7qzgifpn6is3m27xslwbq-nixos-system-s-router-test-25.11.20260421.10e7ad5`
- `s88-network-validation-status` is ready and green on the returned BGP host for:
  - `b-router-access-branch`
  - `b-router-access-hostile`
  - all `s-router-access-*`
- Container presence is correct on the returned BGP host, including:
  - branch path containers
  - hostile path containers
  - Nebula containers
  - all expected `s-router-access-*`, selector, policy, and core containers
- Site A endpoint DNS works through the modeled resolver path.
- Branch endpoint DNS works through the modeled resolver path.
- Hostile endpoint DNS works through the modeled hostile access resolver path.
- Direct public DNS leak checks are blocked from the verified endpoint contexts:
  - `admin-test`
  - `branch-node01`
  - `hostile-node01`
- Branch/site-A lane preservation is correct on the returned BGP host:
  - `s-router-core-isp-b` routes branch LAN prefixes via `overlay-west`
  - `b-router-policy` routes site A LAN prefixes via `up-branch-ew`
- Hostile exit-node split routing is correct on the returned BGP host:
  - Hetzner public endpoints stay on `eth0`
  - general public internet uses Nebula table `100`
- Hostile public egress through Hetzner works on the returned BGP host:
  - `curl -4 ifconfig.me` returns `46.224.173.254`
  - `curl -6 ifconfig.me` returns `2a01:4f8:c013:628b::1`
- The previous static-wrapper reboot also came back live-healthy on host hash:
  - returned `/nix/store/kjp7n89727asdscvy169c2n03hif9r3x-nixos-system-s-router-test-25.11.20260421.10e7ad5`
- On that returned static host:
  - `s88-network-validation-status` was ready and green
  - `s-router-core-isp-b` routed branch LAN prefixes via `overlay-west`
  - `b-router-policy` routed site A LAN prefixes via `up-branch-ew`
  - hostile Hetzner egress still returned `46.224.173.254` and `2a01:4f8:c013:628b::1`
  - hostile direct public DNS queries still timed out
- On the currently verified BGP host, `s-router-test` is production-ready for the hostile-network requirement on the locked chain.

## Fixed But Only Locally Tested

- `network-compiler` service-subject policy regression is committed and its test suite passes locally.
- `network-control-plane-model` realized-interface-route normalization is committed and its focused plus passing-fixture suites pass locally.
- `network-renderer-containerlab-linux-backend` VM bridge-input fix is committed and `timeout 180 ./start-vm.sh` now reaches a booted VM.
- `network-renderer-nixos` declarative IPv6 RA rendering and refreshed example-backed tests are committed and pass locally.

## Implemented But Not Yet Live-Validated

- None.

## Still Broken

- None verified on the current returned BGP host.

## Pending Or Unknown

- The static-wrapper returned host was live-checked successfully, but I did not capture a dry-run/live hash-equality line for that reboot because the rebuild-loop session was interrupted just as SSH returned.

## Next Concrete Debugging Target

- If the topology regresses again, rerun the rebuild loop and re-check:
  - dry-run/live hash equality
  - `s88-network-validation-status`
  - branch/site-A lane preservation via `ip route get`
  - hostile `curl -4 ifconfig.me` / `curl -6 ifconfig.me`
  - direct public DNS leak tests from `admin-test`, `branch-node01`, and `hostile-node01`
