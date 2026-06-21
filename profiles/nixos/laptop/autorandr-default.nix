{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.local.laptop.autorandrDefault;

  ensureAutorandrDefault = pkgs.writeShellScript "ensure-autorandr-default" ''
    set -u

    config_home="''${XDG_CONFIG_HOME:-$HOME/.config}"
    profile_dir="$config_home/autorandr/default"

    if [ -s "$profile_dir/setup" ] && [ -s "$profile_dir/config" ]; then
      exit 0
    fi

    if [ -z "''${DISPLAY:-}" ]; then
      echo "No DISPLAY in user session; skipping autorandr default profile creation." >&2
      exit 0
    fi

    for _ in $(${pkgs.coreutils}/bin/seq 1 20); do
      if ${pkgs.xrandr}/bin/xrandr --query >/dev/null 2>&1; then
        break
      fi
      ${pkgs.coreutils}/bin/sleep 0.5
    done

    if ! ${pkgs.xrandr}/bin/xrandr --query >/dev/null 2>&1; then
      echo "xrandr is not ready; skipping autorandr default profile creation." >&2
      exit 0
    fi

    ${pkgs.coreutils}/bin/mkdir -p "$config_home/autorandr"
    ${pkgs.coreutils}/bin/rm -rf "$profile_dir"

    if ! ${pkgs.autorandr}/bin/autorandr --save default >/tmp/autorandr-default-profile.log 2>&1; then
      ${pkgs.coreutils}/bin/cat /tmp/autorandr-default-profile.log >&2
      ${pkgs.coreutils}/bin/rm -rf "$profile_dir"
      exit 0
    fi
  '';
in
{
  options.local.laptop.autorandrDefault.enable = lib.mkEnableOption "autorandr default profile creation" // {
    default = true;
  };

  config = lib.mkIf cfg.enable {
    systemd.user.services.autorandr-default-profile = {
      description = "Create a default autorandr profile when missing";
      before = [ "app-autorandr@autostart.service" ];
      wantedBy = [ "xdg-desktop-autostart.target" ];

      serviceConfig = {
        Type = "oneshot";
        ExecStart = ensureAutorandrDefault;
      };
    };
  };
}
