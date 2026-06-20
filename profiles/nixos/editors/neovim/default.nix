{ pkgs, ... }:

let
  unstablePkgs = pkgs.unstable or pkgs;
in
{
  programs.neovim = {
    enable = true;
    package = unstablePkgs.neovim-unwrapped;
    withNodeJs = true;
    withPython3 = true;

    configure = {
      packages.default = with unstablePkgs.vimPlugins; {
        start = [
          blink-cmp
          friendly-snippets
          gitsigns-nvim
          gruvbox-nvim
          indent-blankline-nvim
          lualine-nvim
          markdown-preview-nvim
          neo-tree-nvim
          nui-nvim
          nvim-lspconfig
          nvim-treesitter.withAllGrammars
          nvim-web-devicons
          plenary-nvim
          telescope-fzf-native-nvim
          telescope-nvim
          which-key-nvim
        ];
      };

      customRC = ''
        lua dofile("${./init.lua}")
      '';
    };
  };

  environment.systemPackages = with pkgs; [
    bash-language-server
    fd
    lua-language-server
    nil
    nixfmt
    nodejs
    prettier
    pyright
    typescript-language-server
    vim
    vscode-langservers-extracted
    yaml-language-server
  ];
}
