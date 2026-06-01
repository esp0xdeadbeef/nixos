{ lib
, outPath
, pkgsForRenderer
, runtime
, runtimeFacts
,
}:
let
  inherit (runtimeFacts)
    require
    rootPasswordHashPath
    ;
  operatorAuthorizedKeys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAqEmMbztRhj2zE1dXf5Z+Ow7mXXXE6sNAG4/hrIOrmD deadbeef@codex-jail"
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIA1Rmk/3OrwWB5qvWrltIDGgK2vxQIXfRtPkAg56gHB1 deadbeef@l-x13s"
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMgBgeVe/DSMZQAY8iS1D5Db3IbyteDSW+l79ZFD8Rmg deadbeef@l-esp"
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJwxQYzAV73hk/YIet+5EfgS6RdbkA0wyL5J8G8SjAY0 root@s-router-test"
  ];
in
{
  networking.hostName = "hetzner-nebula-prodtest-01";
  sops.defaultSopsFile = "${outPath}/secrets/s-router-test.yaml";
  sops.age.sshKeyPaths = [ "/persist/root/.ssh/id_ed25519" ];
  fileSystems."/boot".neededForBoot = true;
  fileSystems."/nix".neededForBoot = true;
  fileSystems."/persist".neededForBoot = true;
  environment.persistence."/persist" = {
    hideMounts = true;
    directories = [
      "/root/.ssh"
      "/var/lib/nixos"
      "/var/lib/systemd"
    ];
    files = [ "/etc/machine-id" ];
  };
  system.activationScripts.prepareHetznerImpermanenceMachineId = {
    deps = [ "createPersistentStorageDirs" ];
    text = ''
      install -d -m 0755 /persist/etc
      if [ -e /etc/machine-id ] && [ ! -s /persist/etc/machine-id ]; then
        install -D -m 0444 /etc/machine-id /persist/etc/machine-id
      fi
      if [ ! -s /persist/etc/machine-id ]; then
        ${pkgsForRenderer.systemd}/bin/systemd-id128 new > /persist/etc/machine-id
        chmod 0444 /persist/etc/machine-id
      fi
      rm -f /etc/machine-id
    '';
  };
  system.activationScripts.persist-files.deps = [
    "prepareHetznerImpermanenceMachineId"
  ];

  boot.loader.grub = {
    enable = true;
    device = "/dev/sda";
    efiSupport = true;
    efiInstallAsRemovable = true;
  };
  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];

  users.users.root = {
    hashedPasswordFile = rootPasswordHashPath;
    openssh.authorizedKeys.keys =
      lib.unique (operatorAuthorizedKeys ++ require "authorizedKeys" runtime.authorizedKeys);
  };
  services.openssh = {
    enable = true;
    hostKeys = [
      {
        type = "ed25519";
        path = "/persist/etc/ssh/ssh_host_ed25519_key";
      }
      {
        type = "rsa";
        bits = 4096;
        path = "/persist/etc/ssh/ssh_host_rsa_key";
      }
    ];
    settings = {
      PermitRootLogin = "prohibit-password";
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
    };
  };
  networking.firewall.allowedTCPPorts = [ 22 ];
  networking.firewall.checkReversePath = lib.mkForce false;
  environment.systemPackages = with pkgsForRenderer; [
    bind
    conntrack-tools
    curl
    dig
    ethtool
    gron
    iproute2
    iptables
    iputils
    jq
    lsof
    mtr
    netcat-openbsd
    neovim
    nftables
    procps
    ripgrep
    socat
    strace
    tcpdump
    tmux
    traceroute
    tshark
    vim
  ];
  system.stateVersion = "25.11";
}
