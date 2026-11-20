{ config, pkgs, ... }:
{
  nix.gc = {
    automatic = true;
    persistent = true;
    dates = "daily";
    options = "--delete-older-than 30d";
    randomizedDelaySec = "5min";
  };

  # `nix.gc.options = "--delete-older-than 30d"` deletes PROFILE GENERATIONS
  # older than 30 days (nix-collect-garbage(1): "the equivalent of invoking
  # nix-env --delete-generations <period> on each found profile"), and the
  # collector then reclaims whatever those generations were the only reference
  # to. That is the 30-day window, and it is what actually frees the space.
  #
  # A store path that no profile and no GC ROOT references is not "kept for 30
  # days" -- it is garbage the moment the collector runs. That distinction cost
  # a night on 2026-11-20: s-sigma builds s-nodus' aarch64 closure, but
  # `nixos-rebuild --target-host` creates its profile on the TARGET, so on the
  # builder the whole build was unrooted and the daily GC took it (14509 paths
  # / 39.9 GiB, including both board kernels). Neither kernel is substitutable
  # (cache.nixos.org: 404), so each rebuild is hours of qemu-user emulation.
  #
  # So: keep the collector on its 30-day schedule, and give the builder a root
  # for the closures it realises. `keep-outputs`/`keep-derivations` are set in
  # base/common.nix; they act only relative to a root, which is why a root is
  # what matters here.
  systemd.services.nix-prune-generations = {
    description = "Prune old NixOS system generations";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = ''
        ${pkgs.nix}/bin/nix-env \
          --profile /nix/var/nix/profiles/system \
          --delete-generations +30
      '';
    };
  };

  systemd.timers.nix-prune-generations = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "weekly";
      Persistent = true;
    };
  };

}
