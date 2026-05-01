{ pkgs }:
serviceXml:
{
  services.avahi = {
    enable = true;
    publish = {
      enable = true;
      addresses = true;
      workstation = true;
    };
  };

  environment.etc."avahi/services/runtime.service".text = serviceXml;
  environment.systemPackages = [ pkgs.avahi ];
}
