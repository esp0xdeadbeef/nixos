{ lib
, outPath
, pkgs
, hostName
, installDisk
, ...
}:
let
  keyFor = host: lib.fileContents "${outPath}/ssh-keys/deadbeef/${host}.pub";
in
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
      "/var/dkim"
      "/var/lib/acme"
      "/var/lib/dovecot"
      "/var/lib/nixos"
      "/var/lib/postfix"
      "/var/lib/rspamd"
      "/var/lib/systemd"
      "/var/log"
      "/var/spool/postfix"
      "/var/vmail"
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

      if ! mountpoint -q /etc/machine-id; then
        rm -f /etc/machine-id
      fi
    '';
  };

  system.activationScripts.repairPersistentStateRootOwnership = {
    deps = [ "createPersistentStorageDirs" ];
    text = ''
      for path in /persist/var /persist/var/lib /persist/var/log /var /var/lib /var/log; do
        if [ -d "$path" ]; then
          chown root:root "$path"
          chmod 0755 "$path"
        fi
      done

      for journalRoot in /persist/var/log/journal /var/log/journal; do
        if [ -d "$journalRoot" ]; then
          chown root:systemd-journal "$journalRoot"
          chmod 2755 "$journalRoot"
        fi

        for journalDir in "$journalRoot"/*; do
          [ -d "$journalDir" ] || continue
          chown root:systemd-journal "$journalDir"
          chmod 2755 "$journalDir"
        done
      done
    '';
  };

  system.activationScripts.persist-files.deps = [
    "prepareImpermanenceMachineId"
    "repairPersistentStateRootOwnership"
  ];

  boot.loader.grub = {
    enable = true;

    device = installDisk;
    efiSupport = true;
    efiInstallAsRemovable = true;
  };

  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];

  sops.age.sshKeyPaths = [
    "/persist/etc/ssh/ssh_host_ed25519_key"
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
    (keyFor "codex-jail")
    (keyFor "l-portal")
    (keyFor "l-esp")
    (keyFor "l-esp-rsa")
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
}
