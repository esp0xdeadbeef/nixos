{ config, pkgs, ... }:

{
  # Set GTK dark theme
  gtk = {
    enable = true;
    theme = {
      name = "Adwaita-dark";
      package = pkgs.gnome-themes-extra;
    };
    iconTheme = {
      name = "Papirus-Dark";
      package = pkgs.papirus-icon-theme;
    };
  };

  # Set QT theme to dark
  qt = {
    enable = true;
    platformTheme.name = "gtk"; # Or "qt5ct" if you prefer
    style.name = "Adwaita-dark";
  };

  # Export environment variable for your own Electron apps
  home.sessionVariables = {
    DARKMODE = "1";
    # didn't work, still white mode default config:
    _JAVA_OPTIONS = "-Dswing.defaultlaf=com.formdev.flatlaf.FlatDarculaLaf";
  };

  # Set GSettings to prefer dark mode (important for some apps like Electron using portals)
  dconf.settings = {
    "org/gnome/desktop/interface" = {
      color-scheme = "prefer-dark";
      gtk-theme = "Adwaita-dark";
    };
  };
}
