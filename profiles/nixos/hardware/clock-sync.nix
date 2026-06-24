{ ... }:
{
  services.chrony = {
    enable = true;

    makestep = {
      enable = true;
      threshold = 1.0;
      limit = 3;
    };

    enableRTCTrimming = true;
    autotrimThreshold = 10;
  };
}
