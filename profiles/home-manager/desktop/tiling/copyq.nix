{ lib, pkgs, ... }:
let
  copyqBinding = execPrefix: ''
    bindsym $mod+Shift+v ${execPrefix} ${pkgs.copyq}/bin/copyq show
  '';
  copyqConfigure = pkgs.writeShellScriptBin "copyq-configure" ''
    set -eu

    copyq_config_file="''${XDG_CONFIG_HOME:-$HOME/.config}/copyq/copyq.conf"
    ${pkgs.coreutils}/bin/mkdir -p "$(${pkgs.coreutils}/bin/dirname "$copyq_config_file")"

    copyq_config() {
      ${pkgs.crudini}/bin/crudini --set "$copyq_config_file" Options "$1" "$2"
    }

    copyq_config maxitems "1000"
    copyq_config expire_tab "0"
    copyq_config save_delay_ms_on_item_added "1000"
    copyq_config save_delay_ms_on_item_modified "1000"
    copyq_config save_delay_ms_on_item_moved "1000"
    copyq_config save_delay_ms_on_item_removed "1000"
    ${pkgs.crudini}/bin/crudini --set "$copyq_config_file" Plugins 'itemimage\image_editor' '${pkgs.ksnip}/bin/ksnip --edit %1'
  '';
in
{
  home.packages = [
    copyqConfigure
  ];

  services.copyq.enable = true;
  systemd.user.services.copyq.Service.ExecStartPre = "${copyqConfigure}/bin/copyq-configure";

  local.i3.extraConfig = lib.mkAfter (copyqBinding "exec --no-startup-id");
  local.sway.extraConfig = lib.mkAfter (copyqBinding "exec");
}
