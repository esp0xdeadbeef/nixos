{ lib
, pkgs
, ...
}:

let
  codexUser = "deadbeef";
  npmGlobalPrefix = "/home/${codexUser}/.npm-global";
in
{
  environment.systemPackages = with pkgs; [
    nodejs
    git
  ];

  environment.variables = {
    NPM_CONFIG_PREFIX = npmGlobalPrefix;
  };

  environment.shellInit = ''
    export PATH="${npmGlobalPrefix}/bin:$PATH"
  '';

  systemd.tmpfiles.rules = [
    "d /home/${codexUser}/.npm-global 0755 ${codexUser} users -"
    "d /home/${codexUser}/.npm-global/bin 0755 ${codexUser} users -"
    "d /home/${codexUser}/.codex 0700 ${codexUser} users -"
  ];

  systemd.services.install-latest-codex = {
    description = "Install latest OpenAI Codex CLI";

    wantedBy = [ "multi-user.target" ];
    after = [
      "network-online.target"
      "persist.mount"
    ];
    wants = [ "network-online.target" ];

    path = with pkgs; [
      bash
      coreutils
      nodejs
      git
    ];

    serviceConfig = {
      Type = "oneshot";
      User = codexUser;
      Group = "users";
      Environment = [
        "HOME=/home/${codexUser}"
        "NPM_CONFIG_PREFIX=${npmGlobalPrefix}"
        "PATH=${npmGlobalPrefix}/bin:${lib.makeBinPath [ pkgs.nodejs pkgs.git pkgs.bash pkgs.coreutils ]}"
      ];
    };

    script = ''
      set -eu

      mkdir -p "${npmGlobalPrefix}/bin" "$HOME/.codex"

      npm config set prefix "${npmGlobalPrefix}"
      npm install --global @openai/codex@latest

      "${npmGlobalPrefix}/bin/codex" --version
    '';
  };

  home-manager.users.${codexUser} = {
    programs.zsh.initContent = lib.mkAfter ''
      export PATH="${npmGlobalPrefix}/bin:$PATH"
    '';
  };
}
