{ lib, pkgs, ... }:
{
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
