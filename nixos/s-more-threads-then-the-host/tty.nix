{
  boot.kernelParams = [
    "console=ttyS0,115200n8"
    "console=tty1"
  ];

  services.getty.autologinUser = "root";

  services.getty.extraArgs = [ "--noclear" ];

  systemd.services."serial-getty@ttyS0".enable = true;
}

