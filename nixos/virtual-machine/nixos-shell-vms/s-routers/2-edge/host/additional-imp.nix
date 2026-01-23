# ./host/impermanence.nix
{ config, lib, ... }:

{
  environment.persistence."/persist" = {
    directories = [
      "/root/test"
    ];
  };
}

