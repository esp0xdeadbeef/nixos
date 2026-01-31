{
  config,
  pkgs,
  sops,
  ...
}:
{
  systemd.services.echoSecret = {
    description = "Echo secret for testing";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${pkgs.bash}/bin/bash -c 'echo \"test\"'";
    };
    wantedBy = [ "multi-user.target" ];
  };
}
