{ pkgs, ... }:

{
  # TEMPORARY NETWORK-RENDERER VLAN 3 LOCAL-DATA RACE OVERRIDE.
  #
  # The renderer emits gen-s-router-prod-vlan3-unbound-local-data.service with
  # Before=unbound.service but no RuntimeDirectory, so its `ln -sf` into
  # /run/unbound races unbound's RuntimeDirectory and fails at every boot.
  # Create the directory first, mirroring what vlan2-reservation-dns.nix does
  # for the VLAN 2 generator.
  #
  # Remove this file when network-renderer-nixos gives the generator its own
  # RuntimeDirectory (or an equivalent ExecStartPre mkdir).
  containers.access-vlan3.config.systemd.services."gen-s-router-prod-vlan3-unbound-local-data" = {
    serviceConfig.ExecStartPre = [
      "${pkgs.coreutils}/bin/mkdir -p /run/unbound"
    ];
  };
}
