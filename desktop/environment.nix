{ config, pkgs, ... }: {
              #############################
              # X11, Desktop and Window Manager
              #############################

     # i3status-rust (doesn't work):
     #environment.etc."i3status-rust/config.toml".source = /etc/nixos/i3status-rust/config.toml;
     #environment.etc."i3status-rust/get_ipv4.sh".source = /etc/nixos/i3status-rust/get_ipv4.sh;
     #environment.etc."i3status-rust/get_ipv6.sh".source = /etc/nixos/i3status-rust/get_ipv6.sh;
     #environment.etc."i3status-rust/gpu-load.sh".source = /etc/nixos/i3status-rust/gpu-load.sh;
     # i3status-rust:
     #home.file.".config/i3status-rust/config.toml".source = /etc/nixos/i3status-rust/config.toml;
     #home.file.".config/i3status-rust/get_ipv4.sh".source = /etc/nixos/i3status-rust/get_ipv4.sh;
     #home.file.".config/i3status-rust/get_ipv6.sh".source = /etc/nixos/i3status-rust/get_ipv6.sh;
     #home.file.".config/i3status-rust/gpu-load.sh".source = /etc/nixos/i3status-rust/gpu-load.sh;

     
     services.autorandr.enable = true;
     programs.dconf.enable = true;
              services.xserver = {
                enable = true;
                desktopManager = {
                  xterm.enable = false;
                  xfce = {
                    enable    = true;
                    noDesktop = true;
                    enableXfwm = false;
                  };
                };
              windowManager.i3 = {
                  enable = true;
                  extraPackages = with pkgs; [
                      #dmenu
                      rofi
                      i3status
                      i3lock
                      i3blocks
                      autotiling
                 ];
                configFile = builtins.toPath "/etc/nixos/home-manager/i3/config"; 
                #extraSessionCommands = ''
                #  exec --no-startup-id autotiling
                #'';
              };
                  xkb = {
                      layout  = "us";
                      variant = "";
                  };
              };
            
              #environment.variables.GTK_THEME = "Adwaita:dark";
              services.gnome.gnome-keyring.enable = true;
              #services.desktopManager.plasma6.enable = true;
              services.xserver.displayManager.gdm.enable = true;
              #services.xserver.desktopManager.gnome.enable = true;

              #programs.sway.enable = true;
              services.displayManager.defaultSession = "none+i3";
}
