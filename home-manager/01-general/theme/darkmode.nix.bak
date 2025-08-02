{
  pkgs,
  config,
  lib,
  ...
}:

{
  # Enable Qt theming
  qt = {
    enable = true;
  };
  
  # User-specific GTK theme settings via Home Manager
  gtk.enable = true;
  gtk.theme = {
    name = "Adwaita-dark";
    package = pkgs.gnome-themes-extra;
  };
}