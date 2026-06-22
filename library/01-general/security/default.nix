{ ... }:
{
  security.polkit.enable = true;
  security.sudo.extraConfig = ''
    Defaults lecture=never
  '';
}
