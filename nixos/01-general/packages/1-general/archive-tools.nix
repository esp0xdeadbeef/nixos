{
  config,
  pkgs,
  lib,
  ...
}:
{
  environment = {
    systemPackages = with pkgs; [
      #unziping a archive zip file:
      unzip
      # unzipping a 7z file
      p7zip
      # unzipping a rar file
      unrar
      # unzipping a gzip file
      gzip
      # unzipping a bzip2 file
      bzip2
    ];
  };
}