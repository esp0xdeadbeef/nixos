{ lib
, pkgs
, relativeRepo ? import ../../../library/relative-repo.nix
    {
      inherit lib;
      root = ../../..;
    }
, ...
}:
{
  imports = [
    # Keeps Python bytecode out of the store and the checkout. Applied here
    # because base.common is the one module every host and VM reaches
    # (core -> base.common, plus the s-gamma and VM bases directly); putting it
    # in a narrower profile would silently drop it from every host that does
    # not import that profile.
    # A path literal, not `relativeRepo.module`: an argument used inside
    # `imports` cannot come from `_module.args`, because that IS `config` and
    # reading it while imports are evaluated recurses. `relativeRepo` is still
    # accepted (and still used below) for callers that need a different root, but
    # the one import that runs at import time names its file relative to this
    # profile -- which resolves inside whichever checkout is being evaluated.
    ../../../modules/nixos/python-pycache-prefix.nix
  ];

  security.sudo.extraConfig = lib.mkAfter ''
    Defaults lecture = never
  '';

  nix.settings = {
    # nixpkgs builds Nix with
    #   libstore:sandbox-shell = ${busybox-sandbox-shell}/bin/busybox
    # so Nix's compiled-in default here is `sandbox-paths = /bin/sh=<busybox>`.
    # That default is not NixOS configuration, so it never appears in the
    # generated /etc/nix/nix.conf -- it is invisible to inspection and gives
    # every builder busybox ash, where nix.conf(5) documents the intent as
    # "/bin/sh as a bind-mount of bash". Pin it explicitly to a real bash from
    # the store so the setting is visible in nix.conf and hash-pinned in the
    # system closure.
    #
    # This lives in base.common because that is the one module every host and
    # VM reaches (core -> base.common, plus the s-gamma and VM bases directly);
    # base.system is skipped by dell-vm-host and base.common-less hosts.
    sandbox-paths = [ "/bin/sh=${pkgs.bashInteractive}/bin/bash" ];

    # Keep outputs/derivations of store paths that still have a GC root.
    #
    # nix.conf(5): keep-outputs keeps "the outputs of non-garbage derivations",
    # keep-derivations "the derivations from which non-garbage store paths were
    # built". Both are relative to a ROOT -- they do not protect an unrooted
    # path, and they do not extend the 30-day retention below. What they buy is
    # that a rooted artefact keeps its build inputs (compiler, source tarball),
    # so re-realising it does not silently pull a toolchain back in.
    keep-outputs = true;
    keep-derivations = true;
  };

  environment.systemPackages = with pkgs; [
    age
    curl
    dig
    git
    jq
    lsof
    mtr
    procps
    ripgrep
    sops
    tcpdump
    tmux
    traceroute
    vim
    wget
  ];
}
