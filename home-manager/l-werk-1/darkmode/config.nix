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
  };

  # Set GSettings to prefer dark mode (important for some apps like Electron using portals)
  dconf.settings = {
    "org/gnome/desktop/interface" = {
      color-scheme = "prefer-dark";
      gtk-theme = "Adwaita-dark";
    };
  };
}
