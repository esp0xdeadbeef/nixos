{ config, ... }:
{
  local.tiling.generated.i3.bar = ''
    bar {
      status_command ${config.local.i3.statusCommand}
      font ${config.local.tilingManagerSettings.statusBarFont}
      modifier $mod
      workspace_min_width 40
      colors {
        separator #282a36
        background #282a3670
        statusline #f8f8f2
        focused_workspace #50fa7b70 #50fa7b #282a36
        active_workspace #8be9fd70 #8be9fd #282a36
        inactive_workspace #282a3670 #282a3670 #f8f8f2
        urgent_workspace #2f343a70 #ff555570 #282a36
      }
    }
  '';

  local.tiling.generated.sway.bar = ''
    bar {
      status_command ${config.local.sway.statusCommand}
      font ${config.local.tilingManagerSettings.statusBarFont}
      position bottom
      modifier $mod
      workspace_min_width 40
      colors {
        separator #282a36
        background #282a3670
        statusline #f8f8f2
        focused_workspace #50fa7b70 #50fa7b #282a36
        active_workspace #8be9fd70 #8be9fd #282a36
        inactive_workspace #282a3670 #282a3670 #f8f8f2
        urgent_workspace #2f343a70 #ff555570 #282a36
      }
    }
  '';
}
