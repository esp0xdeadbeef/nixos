{ lib, config, ... }:
let
  cfg = config.local.laptop.monitorLayouts;

  samsungLu28r55Desk = {
    left = "edid:3d649f7f2aca7155";
    right = "edid:ccc5757174dd0f67";
    internal = "eDP-1";
  };

  mkSamsungLu28r55DeskLines = layout:
    let
      left = layout.left;
      right = layout.right;
      internal = layout.internal;
    in
    [
      "wait=2"
      "dpi=${toString layout.dpi}"
      "primary=${left}"
      "order=${left}"
      "order=${right}"
      "order=${internal}"
    ]
    ++ lib.optional (layout.targetResolution != null)
      "target-resolution=${layout.targetResolution}"
    ++ lib.optional (layout.rate != null)
      "rate=${toString layout.rate}"
    ++ lib.optionals (layout.externalScale != null) [
      "scale=${left}=${layout.externalScale}"
      "scale=${right}=${layout.externalScale}"
    ]
    ++ lib.optional (layout.internalScale != null)
      "scale=${internal}=${layout.internalScale}";
in
{
  options.local.laptop.monitorLayouts.samsungLu28r55Desk = {
    enable = lib.mkEnableOption "the shared Samsung LU28R55 dual-monitor desk layout";

    left = lib.mkOption {
      type = lib.types.str;
      default = samsungLu28r55Desk.left;
      description = "Selector for the left Samsung LU28R55 monitor.";
    };

    right = lib.mkOption {
      type = lib.types.str;
      default = samsungLu28r55Desk.right;
      description = "Selector for the right Samsung LU28R55 monitor.";
    };

    internal = lib.mkOption {
      type = lib.types.str;
      default = samsungLu28r55Desk.internal;
      description = "Selector for the internal laptop panel.";
    };

    dpi = lib.mkOption {
      type = lib.types.ints.positive;
      default = 96;
      description = "Fixed Xft DPI for this monitor layout.";
    };

    rate = lib.mkOption {
      type = lib.types.nullOr lib.types.ints.positive;
      default = null;
      example = 30;
      description = "Optional refresh rate passed to xlayoutdisplay.";
    };

    targetResolution = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = "2560x1440";
      example = null;
      description = "Optional logical size target for outputs larger than this resolution.";
    };

    externalScale = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "1x1";
      description = "Optional manual scale applied to both external Samsung LU28R55 monitors.";
    };

    internalScale = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "0.666667x0.666667";
      description = "Optional manual scale applied to the internal eDP-1 panel.";
    };

    externalMaxResolution = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "2560x1440";
      description = "Optional maximum mode for external outputs when a host cannot drive the shared monitors at their native mode.";
    };
  };

  config = lib.mkIf cfg.samsungLu28r55Desk.enable (lib.mkMerge [
    {
      local.laptop.xlayoutdisplayHotplug.configLines =
        mkSamsungLu28r55DeskLines cfg.samsungLu28r55Desk;
    }

    (lib.mkIf (cfg.samsungLu28r55Desk.externalMaxResolution != null) {
      local.laptop.xlayoutdisplayHotplug.maxResolution =
        cfg.samsungLu28r55Desk.externalMaxResolution;
    })
  ]);
}
