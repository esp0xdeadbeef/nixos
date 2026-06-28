{ pkgs
, config
, lib
, ...
}:
{
  home.packages =
    let
      stable = with pkgs; [
        kdePackages.okular
        # koodo-reader # old version of electron
      ];
      unstable = with pkgs.unstable; [
        koodo-reader # old version of electron
      ];
    in
    stable ++ unstable;
}
