{ pkgs, lib, ... }:
{
  environment.systemPackages = with pkgs; [

    # === Neovim with Lua init.lua ===
    (pkgs.neovim.override {
      configure = {
        customRC = ''
          luafile ${./init.lua}
        '';

        plugins = with pkgs.vimPlugins; [
          # === Core ===
          nvim-treesitter
          nvim-lspconfig
          nvim-cmp
          cmp-nvim-lsp
          mason-nvim
          mason-lspconfig-nvim
          fidget-nvim
          lualine-nvim
          nvim-web-devicons

          # images in nvim
          image-nvim

          # === Linting & Formatting ===
          conform-nvim
          none-ls-nvim
          mason-null-ls-nvim
          jsregexp

          # === Optional visual / UX ===
          trouble-nvim
          todo-comments-nvim
          which-key-nvim

          # === Extra Treesitter Parsers (for snacks, telescope, etc.) ===
          (nvim-treesitter.withPlugins (
            plugins: with plugins; [
              c
              lua
              markdown
              markdown_inline
              query
              vim
              vimdoc
              css
              html
              javascript
              latex
              norg
              scss
              svelte
              tsx
              typst
              vue
              regex
            ]
          ))
        ];
      };
    })

    # --- External dependencies & formatters ---
    git
    xclip
    ripgrep
    fd
    fzf
    lazygit

    # --- Image / PDF / Diagram / LaTeX rendering for snacks.nvim & image.nvim ---
    imagemagick # provides `magick` / `convert`
    ghostscript # provides `gs`
    tectonic # for LaTeX
    mermaid-cli # for Mermaid diagrams

    # --- Formatters / Linters for conform / none-ls ---
    black
    nodePackages.prettier
    # my old one:
    #   nixfmt
    # will be changed to nixfmt-classic
    # new formatter:
    nixfmt-rfc-style
    shfmt
    stylua
    shellcheck

    # asm:
    nasmfmt

    # --- Language runtime dependencies ---
    nodejs
    #python3Full
    ruby
    sqlite

    # markdown localhost server:
    deno

    # --- Lua runtime / LuaRocks / jsregexp for luasnip ---
    lua5_1
    lua51Packages.luarocks
    (luaPackages.jsregexp)
  ];
}
