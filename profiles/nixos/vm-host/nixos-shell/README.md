# Transactional nixos-shell VM host profile

`profiles.nixos.vm-host.nixos-shell` is a thin import adapter for the
`nixos-shell-vm-manager` flake module. Generic lifecycle, carrier, console,
health, storage, concurrency, and offline-start behavior belongs to the manager
repository.

Hosts configure the manager's public options directly:

```nix
{ profiles, self, ... }:
{
  imports = [
    profiles.nixos.vm-host.nixos-shell
  ];

  services.nixosShellVmManager = {
    enable = true;
    persistentDirectory = "/persist/vm-persists";

    instances.s-test = {
      image = self.nixosConfigurations.s-test.config.system.build.nixos-shell;
      healthCheck.command = "...";
      storage.persistentDisk.enable = true;
    };

    carrierControls.eno1-router-vms = {
      interface = "eno1";
      instances = [ "s-router-prod" ];
    };
  };
}
```

Each assigned `image` is included in the host closure. `nixos-rebuild` therefore
builds the VM from the consumer flake's own pins before activation, while
runtime start and rollback require neither source evaluation nor Internet
access. An explicit development update remains
`vm-update <vm> /path/to/local/flake`.

Per-VM `activation.refreshPins = true` is an explicit exception: before an
eligible start, the manager runs `nix flake update --refresh` against an
isolated copy of the configured `pinRefresh.flake`, builds the configured
attribute, and admits the result transactionally. Refresh failure leaves image
slots unchanged and falls back to the already available host-pinned image.

The manager exposes an offline tmux console by default at
`/run/nixos-shell/<vm>.tmux`, session `vm`. For example:

```console
vm-attach s-test-l-esp
tmux -S /run/nixos-shell/s-test-l-esp.tmux attach -t vm
```

Use `vm-list` to discover configured instance names. The operator commands are
`vm-status <vm>`, `vm-attach <vm>`, `vm-update <vm> <local-flake>`, and
`vm-rollout <vm>`. The `nixos-shell-vm-manager` binary is the internal service
engine and expects a generated configuration path rather than a VM name.

A running VM is not restarted by `nixos-rebuild switch`. If it predates console
support, its tmux session appears only after the next deliberate service
stop/start.

Host files should contain only assigned image derivations and genuinely
host-specific policy. They must not copy manager option schemas, watchers, or
lifecycle scripts.
