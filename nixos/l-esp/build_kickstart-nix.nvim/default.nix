{ inputs, config, pkgs, ... }:
{
  environment.systemPackages = with pkgs; [
    nvim-pkg
  ];
  environment.etc."nvim/init.lua".source =
    "${inputs.kickstart-nix-nvim}/nvim/init.lua";

  environment.etc."nvim/lua".source =
    "${inputs.kickstart-nix-nvim}/nvim/lua";

}
