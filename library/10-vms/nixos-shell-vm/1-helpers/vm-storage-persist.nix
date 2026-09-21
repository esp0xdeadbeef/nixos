{ lib
, config
, pkgs
, inputs
, ...
}:
let
  # Upstream nixos-shell `main` migrated from 9p to virtiofs and now requires
  # `virtualisation.sharedDirectories.*.writable`, which only exists on nixpkgs
  # branches that carry the virtiofs share implementation. The primary `nixpkgs`
  # input is on stable nixos-26.05, which still shares via 9p, so the
  # `nixos-shell` input is pinned to the 9p release (2.2.0) in flake.nix.
  #
  # That pin is only valid while the primary nixpkgs is on 26.05. As soon as we
  # move to 26.11 (which carries the virtiofs option and drops the 9p path),
  # these guests must switch back to upstream `main`.
  nixpkgsNeedsVirtiofsNixosShell = lib.versionAtLeast lib.trivial.release "26.11";
in
{
  imports = [
    inputs.nixos-shell.nixosModules.nixos-shell
  ];

  assertions = [
    {
      assertion = !nixpkgsNeedsVirtiofsNixosShell;
      message = ''
        The primary `nixpkgs` is now on release ${lib.trivial.release}, which
        provides virtiofs `virtualisation.sharedDirectories`. The `nixos-shell`
        input is still pinned to the 9p release (2.2.0) in flake.nix. Switch it
        back to `github:Mic92/nixos-shell` (no tag) and remove this guard.
      '';
    }
  ];

  nixos-shell.mounts = {
    mountHome = false;
    extraMounts = {
      "/persist" = "/persist/vm-persists/${config.networking.hostName}";
      # I need an option to cache those images, will try to make them persistent, without using p9 shares.
      #"/var/lib/containers" = "/persist/vm-persists/${config.networking.hostName}/var/lib/containers";
    };
  };

  fileSystems."/" = {
    device = "tmpfs";
    fsType = "tmpfs";
    options = [ "mode=755" ];
  };

  virtualisation.vmVariant.system.stateVersion = lib.mkDefault config.system.stateVersion;
}
