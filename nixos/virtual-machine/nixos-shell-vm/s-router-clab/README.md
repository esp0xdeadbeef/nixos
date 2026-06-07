# `s-router-clab`

`s-router-clab` is a thin host profile for the Containerlab target. It must not
implement Containerlab topology, deploy logic, route/firewall/DNS rules,
overlays, PPP/PPPoE, endpoint behavior, generated artifacts, probes, or
validation hooks locally.

The host profile may only:

- select the HAT or SAT lab source;
- identify `deploymentHost = "s-router-clab"`;
- import renderer-produced host/runtime configuration;
- bind host secrets or runtime inputs required by renderer output;
- preserve explicitly approved VLAN 2 management reachability.

Containerlab topology, runtime/deploy behavior, generated artifacts, and CLAB
validation hooks belong in `network-renderer-containerlab-linux-backend` or an
upstream model contract. Missing behavior is a renderer/model gap, not a reason
to add local Nix modules or scripts here.
