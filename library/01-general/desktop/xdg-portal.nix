{
  pkgs,
  config,
  lib,
  ...
}:

{
  # System-wide dark mode settings, migrated to home-manager.
  # environment.variables = {
  #  GTK_THEME = "Adwaita-dark"; # Ensures GTK3 and GTK4 use dark mode
  #  QT_STYLE_OVERRIDE = "kvantum"; # Ensures Qt apps follow dark mode
  # };

  # # Enable Qt theming system-wide
  # qt = {
  #   enable = true;
  #   platformTheme = "qt5ct"; # Ensures Qt5 apps respect settings
  #   style = "kvantum"; # Use Kvantum for dark mode
  # };

  # # Install necessary dark mode packages
  # environment.systemPackages = with pkgs; [
  #  gnome-themes-extra # Provides Adwaita-dark
  #  lxappearance # GTK theme switcher (optional)
  #  libsForQt5.qt5ct # Qt5 settings manager
  #  qt6ct # Qt6 settings manager
  #  libsForQt5.qtstyleplugin-kvantum # Kvantum theme engine for Qt5
  # ];

  # # Enable Dconf to apply settings properly
  # programs.dconf.enable = true;

  # # Ensure applications respect dark mode
  # services.dbus = {
  #  enable = true;
  #  packages = [
  #    pkgs.xdg-desktop-portal
  #    pkgs.xdg-desktop-portal-gtk
  #  ];
  # };
  services.dbus = {
    enable = true;
    packages = [
      pkgs.xdg-desktop-portal
      pkgs.xdg-desktop-portal-gtk
    ];
  };

}
