{ config, pkgs, ... }: {
              environment.systemPackages = with pkgs; [

              ];

services.ollama = {
  enable = true;
  acceleration = "cuda";
};
}
