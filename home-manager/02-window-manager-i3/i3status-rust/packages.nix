{ config
, lib
, osConfig ? null
, pkgs
, sopsSecrets
, ...
}:

let
  cfg = config.local.i3.statusRust;
  os = if osConfig == null then { } else osConfig;
  systemPackageNames = map (pkg: pkg.pname or pkg.name or "") (os.environment.systemPackages or [ ]);
  hasNvidia =
    lib.elem "nvidia" (os.services.xserver.videoDrivers or [ ])
    || lib.attrByPath [ "hardware" "nvidia" "prime" "nvidiaBusId" ] "" os != "";
  hasRocmSmi = lib.any (name: lib.hasInfix "rocm-smi" name) systemPackageNames;
  hasGpuStatus = hasNvidia || hasRocmSmi;
in
{
  options.local.i3.statusRust = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable the shared i3status-rust Home Manager config.";
    };

    battery.enable = lib.mkOption {
      type = lib.types.bool;
      default = os.services.upower.enable or false;
      description = "Whether to show the battery block.";
    };
  };

  config = lib.mkIf cfg.enable {
    home.file."/.config/i3status-rust/gpu-load.sh" = lib.mkIf hasGpuStatus {
      text = ''
        #!/usr/bin/env bash

        # Initialize variables
        GPU_LOAD=""
        STATE=""
        TEXT=""

        # Check if nvidia-smi is available (for NVIDIA GPU)
        if command -v nvidia-smi &> /dev/null; then
          GPU_LOAD=$(nvidia-smi --query-gpu=utilization.gpu --format=csv,noheader,nounits)
          GPU_TYPE="nvidia"
        # Check if rocm-smi is available (for AMD GPU)
        elif command -v rocm-smi &> /dev/null; then
          GPU_LOAD=$(rocm-smi --showuse | grep "GPU use" | rev | awk '{print $1}')
          GPU_TYPE="amd"
        else
          exit 0
        fi

        # Determine the state based on GPU load percentage
        if [ "$GPU_LOAD" -le 25 ]; then
          STATE="Idle"
          TEXT=""
        elif [ "$GPU_LOAD" -le 50 ]; then
          STATE="Info"
          TEXT=""
        elif [ "$GPU_LOAD" -le 75 ]; then
          STATE="Good"
          TEXT=""
        elif [ "$GPU_LOAD" -le 90 ]; then
          STATE="Warning"
          TEXT=""
        else
          STATE="Critical"
          TEXT=""
        fi

        TEXT="GPU ($GPU_TYPE): $GPU_LOAD%"
        TEXT="GPU: $GPU_LOAD%"
        # Output the JSON block
        printf '{"icon":"","state":"%s","text":"%s"}\n' "$STATE" "$TEXT"
      '';
      executable = true;
    };

    home.file.".config/i3status-rust/config.toml" = {
      text = ''
        # Config for i3blocks-rs
        icons_format = "{icon}"

        [theme]
        theme = "solarized-dark"

        [theme.overrides]
        #idle_bg = "#123456"
        idle_bg = "#000000"
        idle_fg = "#dddddd"

        [icons]
        icons = "awesome6"
        [icons.overrides]
        ${lib.optionalString cfg.battery.enable ''
          bat_charging = "\uf1e6 CHR" # fa-plug
          bat = [
              "\uf244", # fa-battery-empty
              "\uf243", # fa-battery-quarter
              "\uf242", # fa-battery-half
              "\uf241", # fa-battery-three-quarters
              "\uf240", # fa-battery-full
          ]
          bat_not_available = "\uf244 ? UNK" # fa-battery-empty
        ''}

        [[block]]
        block = "net"
        format = " $icon {$signal_strength $ssid $frequency|LAN} via $device "


        [[block]]
        block = "custom"
        cycle = [
            "(echo -n '🏠 '; ip a s $(ip a | grep wlp | cut -d ' ' -f 2 | cut -d ':' -f 1) | grep inet | grep dynamic | grep -v temp | awk '{print $2}' | sed 's|/.*||g' | tail -n2 | head -n1)",
            "(echo -n '🏠 '; ip a s $(ip a | grep wlp | cut -d ' ' -f 2 | cut -d ':' -f 1) | grep inet | grep dynamic | grep -v temp | awk '{print $2}' | sed 's|/.*||g' | tail -n1 | head -n1)",
            "(echo -n '🌍 '; ${pkgs.curl}/bin/curl -s ifconfig.me -4)",
            "(echo -n '🌍 '; ${pkgs.curl}/bin/curl -s ifconfig.me -6)",
        ]

        interval = 60

        [[block]]
        block = "sound"

        [[block.click]]
        button = "left"
        cmd = "pavucontrol"

        [[block]]
        block = "custom"
        cycle = [
            "df -h / | awk 'NR==2 {print \"/: \"$4}'",
            "df -h /mnt/second-ssd | awk 'NR==2 {print \"mnt: \"$4}'"
        ]
        interval = 20

        [[block]]
        block = "memory"
        format = " $icon $mem_total_used_percents.eng(w:2) "
        format_alt = " $icon_swap $swap_used_percents.eng(w:2) "

        [[block]]
        block = "cpu"
        info_cpu = 20
        warning_cpu = 50
        critical_cpu = 90

        ${lib.optionalString hasGpuStatus ''
          [[block]]
          block = "custom"
          command = "~/.config/i3status-rust/gpu-load.sh"
          interval = 1
          json = true
          hide_when_empty = true
        ''}

        ${lib.optionalString cfg.battery.enable ''
          [[block]]
          block = "battery"
          format = "$icon $percentage {$time |}"
          device = "DisplayDevice"
          driver = "upower"
        ''}

        [[block]]
        block = "time"
        interval = 1
        format = " $timestamp.datetime(f:'%Y-%m-%d %R:%S') "
      '';
    };
  };
}
