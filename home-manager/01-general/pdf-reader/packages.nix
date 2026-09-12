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
      ];
    in
    stable;
}
