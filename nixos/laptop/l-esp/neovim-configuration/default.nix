{ pkgs, ... }:

{
  programs.neovim = {
    enable = true;
    defaultEditor = true;
    viAlias = true;
    vimAlias = true;
    withNodeJs = true;
    withPython3 = true;

    configure = {
      packages.default = with pkgs.vimPlugins; {
        start = [
          blink-cmp
          friendly-snippets
          gitsigns-nvim
          gruvbox-nvim
          indent-blankline-nvim
          lualine-nvim
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
        set number
        set relativenumber
        set signcolumn=yes
        set termguicolors
        set mouse=a
        set clipboard=unnamedplus
        set expandtab
        set shiftwidth=2
        set tabstop=2
        set smartindent
        set ignorecase
        set smartcase
        set undofile
        set updatetime=250
        set timeoutlen=300
        set splitright
        set splitbelow
        set completeopt=menu,menuone,noselect

        lua << EOF
        vim.g.mapleader = " "
        vim.g.maplocalleader = " "

        vim.keymap.set("n", "<leader>w", "<cmd>write<cr>")
        vim.keymap.set("n", "<leader>q", "<cmd>quit<cr>")
        vim.keymap.set("n", "<leader>e", "<cmd>Neotree toggle<cr>")
        vim.keymap.set("n", "<leader>ff", "<cmd>Telescope find_files<cr>")
        vim.keymap.set("n", "<leader>fg", "<cmd>Telescope live_grep<cr>")
        vim.keymap.set("n", "<leader>fb", "<cmd>Telescope buffers<cr>")
        vim.keymap.set("n", "<leader>fh", "<cmd>Telescope help_tags<cr>")
        vim.keymap.set("n", "<leader>ca", vim.lsp.buf.code_action)
        vim.keymap.set("n", "<leader>rn", vim.lsp.buf.rename)
        vim.keymap.set("n", "gd", vim.lsp.buf.definition)
        vim.keymap.set("n", "gr", vim.lsp.buf.references)
        vim.keymap.set("n", "K", vim.lsp.buf.hover)
        vim.keymap.set("n", "[d", vim.diagnostic.goto_prev)
        vim.keymap.set("n", "]d", vim.diagnostic.goto_next)

        vim.cmd.colorscheme("gruvbox")

        require("which-key").setup({})
        require("gitsigns").setup({})
        require("ibl").setup({})
        require("lualine").setup({
          options = {
            theme = "gruvbox",
            globalstatus = true
          }
        })

        require("neo-tree").setup({
          filesystem = {
            follow_current_file = {
              enabled = true
            }
          }
        })

        require("telescope").setup({})
        pcall(require("telescope").load_extension, "fzf")

        require("nvim-treesitter.configs").setup({
          highlight = {
            enable = true
          },
          indent = {
            enable = true
          }
        })

        local capabilities = require("blink.cmp").get_lsp_capabilities()

        require("blink.cmp").setup({
          keymap = {
            preset = "default"
          },
          appearance = {
            nerd_font_variant = "mono"
          },
          sources = {
            default = { "lsp", "path", "snippets", "buffer" }
          }
        })

        local servers = {
          "bashls",
          "jsonls",
          "lua_ls",
          "nil_ls",
          "pyright",
          "ts_ls",
          "yamlls",
        }

        for _, server in ipairs(servers) do
          vim.lsp.config(server, {
            capabilities = capabilities,
          })
        end

        vim.lsp.enable(servers)

        vim.api.nvim_create_autocmd("BufWritePre", {
          callback = function()
            vim.lsp.buf.format({
              async = false,
              timeout_ms = 3000
            })
          end
        })
        EOF
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
