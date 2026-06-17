{ pkgs, ... }:

let
  unstablePkgs = pkgs.unstable;
in

{
  programs.neovim = {
    enable = true;
    package = unstablePkgs.neovim-unwrapped;
    defaultEditor = true;
    viAlias = true;
    vimAlias = true;
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
    git
    jq
    lua-language-server
    nil
    nixfmt
    nodejs
    prettier
    pyright
    ripgrep
    typescript-language-server
    vscode-langservers-extracted
    yaml-language-server
  ];
}
