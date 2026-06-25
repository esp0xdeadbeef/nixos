{ inputs
, lib
, outPath
, pkgs
, profiles
, ...
}:
{
  imports = [
    "${outPath}/library/10-vms/nixos-shell-vm/host-config"
    profiles.nixos.llm-clients.agents
    profiles.nixos.impermanence.default
  ];

  sops.defaultSopsFile = "${outPath}/secrets/s-agents.yaml";
  sops.age.sshKeyPaths = [ "/persist/etc/ssh/ssh_host_ed25519_key" ];
  sops.age.keyFile = "/persist/root/.config/sops/age/keys.txt";

  sops.secrets = {
    gh-token = {
      owner = "deadbeef";
      group = "users";
      mode = "0600";
      path = "/run/secrets/gh-token";
    };

    hetzner-token = {
      owner = "deadbeef";
      group = "users";
      mode = "0600";
      path = "/run/secrets/hetzner-token";
    };
  };

  #services.getty.autologinUser =  "deadbeef";
  #services.displayManager.autoLogin.enable = lib.mkForce false;

  services.openssh.settings = {
    PermitRootLogin = "no";
    PasswordAuthentication = true;
    KbdInteractiveAuthentication = true;
  };

  users.users.root.openssh.authorizedKeys.keys = lib.mkForce [ ];
  users.users.deadbeef.shell = pkgs.fish;

  programs.fish.enable = true;

  security.sudo.extraRules = [
    {
      groups = [ "wheel" ];
      commands = [
        {
          command = "ALL";
          options = [ "NOPASSWD" ];
        }
      ];
    }
  ];

  environment.systemPackages = with pkgs; [
    btop
    conntrack-tools
    deadnix
    ethtool
    fd
    file
    gcc
    gdb
    gh
    gnumake
    gron
    htop
    iproute2
    iptables
    iputils
    moreutils
    netcat-openbsd
    nil
    nixpkgs-fmt
    nodejs
    pciutils
    pkg-config
    python3
    ruff
    shellcheck
    socat
    statix
    tmuxp
    tree
    unzip
    usbutils
    zip
  ] ++ (with inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system}; [
    claude-code
    qwen-code
  ]);

  environment.interactiveShellInit = ''
    if [ -r /run/secrets/gh-token ]; then
      export GH_TOKEN="$(cat /run/secrets/gh-token)"
      export GITHUB_TOKEN="$GH_TOKEN"

      git config --global credential.https://github.com.helper '!gh auth git-credential' >/dev/null 2>&1 || true
      git config --global credential.https://gist.github.com.helper '!gh auth git-credential' >/dev/null 2>&1 || true
    fi
  '';

  systemd.tmpfiles.rules = [
    "d /persist/etc 0755 root root -"
    "d /persist/etc/ssh 0755 root root -"
  ];

  local.impermanence = {
    enable = true;
    extraSystemDirectories = [
      "/var/lib/systemd"
    ];
    extraUserDirectories = [
      ".npm-global"
    ];
    rotateBtrfsRoot.enable = false;
  };

  home-manager.users.deadbeef = {
    programs.fish.enable = true;
    programs.zsh.enable = true;
    home.stateVersion = "26.05";
  };

  virtualisation = {
    cores = lib.mkDefault 8;
    memorySize = lib.mkForce (300 * 1024);
    diskSize = lib.mkDefault (40 * 1024);
  };
}
