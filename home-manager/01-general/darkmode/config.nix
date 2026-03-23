{ pkgs, ... }:

{
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

    # Default preference: dark
    colorScheme = "dark";

    # Do not force GTK4 theme through the Home Manager workaround
    gtk4.theme = null;
  };

  qt = {
    enable = true;

    # Avoid current HM "gtk" -> "gtk2" weirdness.
    # "gtk3" is the safer choice right now.
    platformTheme.name = "gtk3";

    # Uncomment only if you want to FORCE Qt dark styling,
    # instead of just expressing the system preference.
    style.name = "adwaita-dark";
  };

  dconf.settings = {
    "org/gnome/desktop/interface" = {
      color-scheme = "prefer-dark";
      gtk-theme = "Adwaita-dark";
      icon-theme = "Papirus-Dark";
    };
  };

  home.sessionVariables = {
    # Not needed for the clean/default path:
    DARKMODE = "1";
    _JAVA_OPTIONS = "-Dswing.defaultlaf=com.formdev.flatlaf.FlatDarculaLaf";
  };
}
