{ lib
, outPath
, pkgs
, hostName
, installDisk
, ...
}:
let
  githubTokenPath = "/run/secrets/gh-token";
  keyFor = host: lib.fileContents "${outPath}/ssh-keys/deadbeef/${host}.pub";
in
{
  networking.hostName = lib.mkForce hostName;

  imports = [
    "${outPath}/profiles/nixos/base/common.nix"
    "${outPath}/profiles/nixos/base/maintenance.nix"
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
      "/var/lib/knot"
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

  system.autoUpgrade = {
    operation = lib.mkForce "boot";
    allowReboot = lib.mkForce true;
  };

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

  sops.secrets.gh-token = {
    sopsFile = "${outPath}/secrets/s-gamma.yaml";
    owner = "root";
    group = "root";
    mode = "0400";
    path = githubTokenPath;
  };

  system.activationScripts.writeRootNixGithubAccessToken = {
    deps = [ "setupSecrets" ];
    text = ''
      token_file=${lib.escapeShellArg githubTokenPath}
      nix_config_dir=/root/.config/nix
      nix_config="$nix_config_dir/nix.conf"

      if [ -r "$token_file" ]; then
        token="$(tr -d '\r\n' < "$token_file")"

        if [ -n "$token" ]; then
          install -d -m 0700 "$nix_config_dir"
          tmp="$nix_config.tmp"

          if [ -e "$nix_config" ]; then
            grep -v -E '^(extra-experimental-features|experimental-features|access-tokens)[[:space:]]*=' "$nix_config" > "$tmp" || true
          else
            : > "$tmp"
          fi

          {
            printf '%s\n' "extra-experimental-features = nix-command flakes"
            printf 'access-tokens = github.com=%s\n' "$token"
          } >> "$tmp"

          chmod 0600 "$tmp"
          mv "$tmp" "$nix_config"
        fi
      fi
    '';
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

  users.users.root.openssh.authorizedKeys.keys = [
    (keyFor "codex-jail")
    (keyFor "l-portal")
    (keyFor "l-esp")
    (keyFor "l-esp-rsa")
  ];

  programs.ssh.knownHosts.github-ed25519 = {
    hostNames = [ "github.com" ];
    publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl";
  };

  networking.firewall.allowedTCPPorts = [ 22 ];
  networking.firewall.checkReversePath = lib.mkForce false;

  environment.systemPackages = with pkgs; [
    conntrack-tools
    curl
    dig
    ethtool
    gron
    iproute2
    iptables
    iputils
    jq
    knot-dns
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
