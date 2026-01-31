{ pkgs, lib, ... }:

let
  neovim-with-tools = pkgs.symlinkJoin {
    name = "neovim-with-tools";
    paths = [ pkgs.neovim ];
    buildInputs = [ pkgs.makeWrapper ];
    postBuild = ''
      wrapProgram $out/bin/nvim \
        --prefix PATH : ${
          lib.makeBinPath [
            pkgs.imagemagick
          ]
        }
    '';
  };

in
{
  programs.neovim = {
    enable = true;
    defaultEditor = true;
    configure.customRC = ''
      luafile ${./nvim.lua}
    '';
  };

  environment.systemPackages = with pkgs; [
    git
    curl
    imagemagick
    imagemagick.dev
    pkg-config
    lua5_1
    lua51Packages.luarocks
    readline
    neovim-with-tools
    neovide
    deno
  ];

}
