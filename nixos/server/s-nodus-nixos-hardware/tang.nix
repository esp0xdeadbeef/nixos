{ config, lib, ... }:

# Cobalt Tang (NBDE) server, run as a NixOS container directly on s-nodus.
#
# Replaces the former `s-tang` nixos-shell VM.  That VM only ever wrapped this
# container -- one systemd-nspawn instance running the single-threaded `tangd@`
# socket service -- while costing a whole QEMU process: 250 MiB resident plus
# 413 MiB swapped (the 1 GiB guest sat ~40% evicted), and 2 of the board's 4
# cores, on a host that also runs s-router-cobalt-new.  Measured container
# footprint is ~25 MiB (peak 31 MiB).
#
# Tang's key material is DELIBERATELY NOT in SOPS.  It is a *runtime-mutable*
# key database, not a static secret: `tangd` creates the first keypair itself on
# the first /adv request, and rotation is a file operation
# (`tangd-rotate-keys`, or `jose jwk gen` + renaming the old keys with a leading
# `.`).  Keeping it in SOPS would mean re-encrypting the repo on every rotation
# and redeploying just to rotate -- backwards for a key that must be rotated
# periodically.  Instead it lives unencrypted-but-0700 on the host's persistent
# volume, exactly like the SSH host key, and rotation is `ssh` + one command.
#
# Why a container is safe here (this is not collapsing an isolation boundary):
#
#   * The VM never held independent state worth protecting: the keypair bind
#     mount, the unlock VLAN and the container definition all already lived on
#     this host's /persist and in this host's store.
#   * The network path is unchanged in meaning.  The VM attached to
#     br-cobalt-lan and terminated VLAN 90 internally; s-nodus already
#     terminates VLAN 90 off the trunk as `cobalt-lan.90` and bridges it into
#     `ap-unlock` for the cobalt APs.  The container joins that same bridge, so
#     it lands on the identical L2 segment (10.2.90.0/24) the VM was on.
#   * Boot ordering is preserved: `containers.*` with autoStart comes up in
#     stage 2 independent of the WAN transceiver, which matters because a
#     booting laptop must reach Tang to unlock its root disk even when no SFP
#     module is seated.
let
  # Key database.  `tangd` reads /var/lib/tang inside the container; bind it to
  # a persistent host directory so the keypair survives impermanence's root
  # rollback (and, unlike before, no longer disappears into a qcow2).
  keyDir = "/persist/secrets/tang";
in
{
  options.local.tang.bootstrap = lib.mkEnableOption "allow Tang to start with an empty key database (first-boot only)";

  config = {
    containers.tang = {
      autoStart = true;
      privateNetwork = true;

      # The unlock tenant's untagged segment.  `ap-unlock` is the bridge that
      # cobalt-lan.90 (VLAN 90 off the br-cobalt-lan trunk) already feeds for
      # the cobalt APs, so the container is on the same L2 as the old VM's NIC.
      hostBridge = "ap-unlock";

      # The Tang key database.  Same in-container path the VM used, so the
      # persisted keys keep working and no client needs re-binding.
      bindMounts."/var/lib/tang" = {
        hostPath = keyDir;
        isReadOnly = false;
      };

      config = { lib, ... }: {
        systemd.network.enable = false;
        networking.useDHCP = false;

        networking.interfaces.eth0.ipv4.addresses = [
          {
            address = "10.2.90.10";
            prefixLength = 24;
          }
        ];
        networking.interfaces.eth0.ipv6.addresses = [
          {
            address = "fd42:dead:beef:290::10";
            prefixLength = 64;
          }
        ];
        networking.defaultGateway = "10.2.90.1";
        networking.defaultGateway6 = "fd42:dead:beef:290::1";

        services.tang = {
          enable = true;
          # "7500" binds [::]:7500 dual-stack, so it serves both IPv4 and IPv6.
          # Source restriction is enforced by the cobalt allow-<tenant>-to-tang
          # firewall rules on the router; the eBPF ipAddressAllow mis-filtered
          # external TCP inside the container, so it is omitted here.
          listenStream = [ "7500" ];
        };

        # The tang module only creates the socket; it does not open the port in
        # the container's own nftables, so external TCP SYN is dropped (ICMP
        # echo is the only thing allowed by default).
        networking.firewall.allowedTCPPorts = [ 7500 ];
        # Allow the standard traceroute UDP probe range so the kernel replies
        # with ICMP port-unreachable (the destination hop of a UDP traceroute).
        networking.firewall.allowedUDPPorts = lib.range 33434 33523;

        # Fixed uid keeps the persisted keypair ownership stable across reboots.
        users.users.tang = {
          isSystemUser = true;
          uid = 4000;
          group = "tang";
        };
        users.groups.tang.gid = 4000;

        systemd.services."tangd@".serviceConfig = {
          DynamicUser = lib.mkForce false;
          User = "tang";
          Group = "tang";
        };

        system.stateVersion = "26.05";
      };
    };

    # The key database must survive impermanence's root rollback.  Declared as
    # a persisted directory so it is created with the tang uid/gid and 0700
    # before the container starts.  Rotation happens in place here.
    environment.persistence."/persist".directories = [
      {
        directory = "/secrets/tang";
        user = "tang";
        group = "tang";
        mode = "0700";
      }
    ];

    # Refuse to serve a keypair-less Tang.  `tangd` would happily generate a
    # FRESH keypair if the directory were empty, and every existing Clevis .jwe
    # would then fail to unlock -- discovered only at the next reboot of a
    # machine that can no longer decrypt its own disk.  Failing loudly at start
    # is the safe failure mode.
    #
    # Skipped on a genuinely new install: set local.tang.bootstrap = true once,
    # let tangd generate the first pair, then clear it and bind clients.
    systemd.services."container@tang".preStart = lib.mkIf (!config.local.tang.bootstrap) ''
      shopt -s nullglob
      keys=("${keyDir}"/*.jwk)
      if (( ''${#keys[@]} == 0 )); then
        echo "tang: no keypair in ${keyDir}; refusing to start with an empty" \
             "key database (a fresh pair would break every existing Clevis" \
             "binding). Restore the keys, or set local.tang.bootstrap = true" \
             "for a first-time install." >&2
        exit 1
      fi
    '';
  };
}
