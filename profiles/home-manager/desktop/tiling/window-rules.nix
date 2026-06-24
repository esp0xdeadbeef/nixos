{ ... }:
{
  local.tiling.generated.i3.windowRules = ''
    for_window [class="google-chrome" class="Google-chrome"] move window to workspace 2
    for_window [class="Chromium" title=".*"] move container to workspace 2
    for_window [class="Spotify"] move to workspace 4
    for_window [title="spotify-player"] move to workspace 4
    for_window [class="discord"] move to workspace 5
    for_window [class="X2GoAgent"] move window to workspace 7
    for_window [class="Navigator" class="firefox"] move window to workspace 8
    for_window [class="Firefox"] move window to workspace 8
    for_window [class="firefox"] move window to workspace 8
    for_window [class="dropbox"] move window to workspace 10
    for_window [class="Dropbox"] move window to workspace 10
    for_window [class="Maestral"] move window to workspace 10
    for_window [class="maestral"] move window to workspace 10
  '';

  local.tiling.generated.sway.windowRules = ''
    for_window [class="google-chrome" class="Google-chrome"] move window to workspace 2
    for_window [class="Chromium" title=".*"] move container to workspace 2
    for_window [class="Spotify"] move to workspace 4
    for_window [title="spotify-player"] move to workspace 4
    for_window [class="X2GoAgent"] move window to workspace 7
    for_window [class="Navigator" class="firefox"] move window to workspace 8
    for_window [class="Firefox"] move window to workspace 8
    for_window [class="firefox"] move window to workspace 8
    for_window [class="dropbox"] move window to workspace 10
    for_window [class="Dropbox"] move window to workspace 10
    for_window [class="Maestral"] move window to workspace 10
    for_window [class="maestral"] move window to workspace 10
  '';
}
