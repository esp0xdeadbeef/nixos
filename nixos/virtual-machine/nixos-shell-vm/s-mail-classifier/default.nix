{ lib
, pkgs
, profiles
, relativeRepo
, ...
}:
{
  imports = [
    (relativeRepo.module "library/10-vms/nixos-shell-vm/host-config")
    profiles.nixos.mail.mailbox-sets
    profiles.nixos.mail.classifier
  ];

  # This service VM consumes only explicitly declared mailbox runtime secrets.
  # It does not need the interactive per-host password secret.
  local.nixosShellHost.secrets.enable = false;
  local.users.primary.name = "deadbeef";

  users.users.deadbeef = {
    isNormalUser = true;
    hashedPassword = "!";
    shell = pkgs.zsh;
  };
  programs.zsh.enable = true;

  local.mail.mailboxSets = {
    enable = true;
    # New hosted mailbox-set secrets are automatically included. Account
    # secrets retain their explicit server-side security allow-list.
    names = null;
    accountNames = profiles.mail.inventory.hostedMailAccounts;
  };

  profiles.mail.classifier = {
    enable = true;
    dryRun = false;
    timer.enable = true;

    ollama = {
      baseUrl = "http://192.168.3.11:11434";
      model = "qwen3.5:9b-q4_K_M";
    };
  };

  # VLAN 2 keeps the normal Internet/IMAP path. A route-free DHCP lease on
  # VLAN 3 provides direct L2 access to the Ollama endpoint without making this
  # VM a router or changing the production router policy.
  systemd.network.networks."30-vlan3" = {
    networkConfig = {
      DHCP = lib.mkForce "ipv4";
      IPv6AcceptRA = lib.mkForce "no";
      LinkLocalAddressing = lib.mkForce "no";
    };
    dhcpV4Config = {
      UseDNS = false;
      UseRoutes = false;
    };
  };

  boot.kernel.sysctl = {
    "net.ipv4.ip_forward" = 0;
    "net.ipv6.conf.all.forwarding" = 0;
  };

  virtualisation = {
    cores = lib.mkForce 2;
    memorySize = lib.mkForce (2 * 1024);
    diskSize = lib.mkForce (8 * 1024);
  };

  system.stateVersion = lib.mkForce "26.05";
}
