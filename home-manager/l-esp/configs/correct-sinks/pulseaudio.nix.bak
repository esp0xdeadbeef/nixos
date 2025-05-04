{ config, pkgs, ... }:

{
  home.file."bin/set-default-audio.sh" = {
    text = ''
      #!${pkgs.bash}/bin/bash

      PACTL="${pkgs.pulseaudio}/bin/pactl"

      # Set default sink if Thunderbolt sink is found
      SINK=$($PACTL list short sinks | grep Thunderbolt | head -n1 | awk '{print $1}')
      if [ -n "$SINK" ]; then
        $PACTL set-default-sink "$SINK"
      fi

      # Set default source if Blue microphone is found
      SOURCE=$($PACTL list short sources | grep -i blue_microphone | head -n1 | awk '{print $1}')
      if [ -n "$SOURCE" ]; then
        $PACTL set-default-source "$SOURCE"
      fi
    '';
    executable = true;
  };

  systemd.user.services.set-default-audio = {
    Unit = {
      Description = "Set default audio sink and source";
      After = [ "default.target" ];
    };
    Service = {
      Type = "oneshot";
      ExecStart = "%h/bin/set-default-audio.sh";
    };
    Install = {
      WantedBy = [ "default.target" ];
    };
  };

  systemd.user.paths.set-default-audio = {
    Unit = {
      Description = "Watch for audio device changes";
    };
    PathConfig = {
      PathChanged = "/proc/asound";
      TriggerUnit = "set-default-audio.service";
    };
    Install = {
      WantedBy = [ "default.target" ];
    };
  };
}
