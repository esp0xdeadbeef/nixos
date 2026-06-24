{ lib, config, ... }:
let
  cfg = config.local.laptop.monitorLayouts;

  samsungLu28r55Desk = {
    left = "edid:3d649f7f2aca7155";
    right = "edid:ccc5757174dd0f67";
    internal = "eDP-1";
  };

  mkSamsungLu28r55DeskLines = layout:
    [
      "wait=2"
      "rate=60"
      "primary=${samsungLu28r55Desk.left}"
      "order=${samsungLu28r55Desk.left}"
      "order=${samsungLu28r55Desk.right}"
      "order=${samsungLu28r55Desk.internal}"
      "scale=${samsungLu28r55Desk.left}=${layout.externalScale}"
      "scale=${samsungLu28r55Desk.right}=${layout.externalScale}"
    ]
    ++ lib.optional (layout.internalScale != null)
      "scale=${samsungLu28r55Desk.internal}=${layout.internalScale}";
in
{
  options.local.laptop.monitorLayouts.samsungLu28r55Desk = {
    enable = lib.mkEnableOption "the shared Samsung LU28R55 dual-monitor desk layout";

    externalScale = lib.mkOption {
      type = lib.types.str;
      default = "1.25x1.25";
      example = "1x1";
      description = "Scale applied to both external Samsung LU28R55 monitors.";
    };

    internalScale = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "1.25x1.25";
      description = "Optional best-effort scale for the internal eDP-1 panel.";
    };

    maxResolution = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "2560x1440";
      description = "Optional maximum output mode for this monitor layout.";
    };
  };

  config = lib.mkIf cfg.samsungLu28r55Desk.enable (lib.mkMerge [
    {
      local.laptop.xlayoutdisplayHotplug.configLines =
        mkSamsungLu28r55DeskLines cfg.samsungLu28r55Desk;
    }

    (lib.mkIf (cfg.samsungLu28r55Desk.maxResolution != null) {
      local.laptop.xlayoutdisplayHotplug.maxResolution =
        cfg.samsungLu28r55Desk.maxResolution;
    })
  ]);
}
