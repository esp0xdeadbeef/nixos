{
  lib,
  outPath,
  pkgs,
  hostName,
  installDisk,
  ...
}:
{
  networking.hostName = lib.mkForce hostName;

  imports = [
    "${outPath}/profiles/nixos/base/common.nix"
    "${outPath}/profiles/nixos/nixpkgs/allow-unfree.nix"
  ];

  fileSystems."/boot".neededForBoot = true;
  fileSystems."/nix".neededForBoot = true;
  fileSystems."/persist".neededForBoot = true;

  environment.persistence."/persist" = {
    hideMounts = true;
    directories = [
      "/root/.ssh"
      "/var/lib/nixos"
      "/var/lib/systemd"
      "/var/log"
    ];
    files = [
      "/etc/machine-id"
    ];
  };

  system.activationScripts.prepareImpermanenceMachineId = {
    deps = [ "createPersistentStorageDirs" ];
    text = ''
      install -d -m 0755 /persist/etc

      if [ -e /etc/machine-id ] && [ ! -s /persist/etc/machine-id ]; then
        install -D -m 0444 /etc/machine-id /persist/etc/machine-id
      fi

      if [ ! -s /persist/etc/machine-id ]; then
        ${pkgs.systemd}/bin/systemd-id128 new > /persist/etc/machine-id
        chmod 0444 /persist/etc/machine-id
      fi

      rm -f /etc/machine-id
    '';
  };

  system.activationScripts.persist-files.deps = [
    "prepareImpermanenceMachineId"
  ];

  boot.loader.grub = {
    enable = true;

    # Must match the disk disko installs to.
    device = installDisk;

    efiSupport = true;
    efiInstallAsRemovable = true;
  };

  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];

  sops.age.sshKeyPaths = [
    "/persist/root/.ssh/id_ed25519"
  ];

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

  users.users.root.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAqEmMbztRhj2zE1dXf5Z+Ow7mXXXE6sNAG4/hrIOrmD deadbeef@codex-jail"
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILNntUmNyQ+OYSEGHlXSBOQSWsJkXnx8E+zhfhGFRDuy deadbeef@l-x13s"
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMgBgeVe/DSMZQAY8iS1D5Db3IbyteDSW+l79ZFD8Rmg deadbeef@l-esp"
  ];

  networking.firewall.allowedTCPPorts = [ 22 ];
  networking.firewall.checkReversePath = lib.mkForce false;

  environment.systemPackages = with pkgs; [
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
    vim
  ];

  system.stateVersion = "25.11";
}
