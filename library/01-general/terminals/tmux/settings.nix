{ config, pkgs, ... }:
{
  programs.tmux = {
    enable = true;
    extraConfig = ''
      # Set default shell (fucked in nixos)
      # set-option -g default-shell zsh

      # Use 256-color terminal
      set-option -g default-terminal "screen-256color"

      # Set status bar colors
      set-option -g status-interval 1
      set-option -g status-bg black
      set-option -g status-fg green

      # Use vi mode for copy mode
      setw -g mode-keys vi

      # Enable mouse support
      set-option -g mouse on
      set-option -g mouse off 

      # Key bindings
      bind-key -n Home send-keys "C-a"
      bind-key -n End send-keys "C-e"

      # Status bar
      set-option -g status-right '#[fg=green] #(date --rfc-3339=seconds | rev | sed "s/^......//" | rev)'
      set-option -g message-style 'fg=colour255 bg=colour233 bold'

      # Pane borders
      set-option -g pane-border-style fg=green
      set-option -g pane-active-border-style "bg=default fg=colour22"

      # Window styles
      set-option -g window-style 'fg=colour247,bg=colour236'
      set-option -g window-active-style 'fg=colour250,bg=colour232'

      # remember the pane location, if you open a new pane
      bind % split-window -h -c "#{pane_current_path}"
      bind \" split-window -v -c "#{pane_current_path}"
      bind c new-window -c "#{pane_current_path}"

      # Other configurations
      # set-option -g history-limit 100000
      set-option -g update-environment "DBUS_SESSION_BUS_ADDRESS DISPLAY SSH_AUTH_SOCK XAUTHORITY"

      bind-key -T copy-mode-vi 'v' send -X begin-selection     # Begin selection in copy mode.
      bind-key -T copy-mode-vi 'C-v' send -X rectangle-toggle  # Begin selection in copy mode.
      bind-key -T copy-mode-vi 'y' send-keys -X copy-pipe-and-cancel 'xclip -in -selection clipboard > /dev/null'


      # set -g status-right '#[fg=black,bg=color15] #{cpu_percentage}  %H:%M '
      # run-shell ${pkgs.tmuxPlugins.cpu}/share/tmux-plugins/cpu/cpu.tmux
    '';
  };
}
