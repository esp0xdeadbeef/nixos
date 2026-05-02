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

        local function force_black_background()
          local groups = {
            "Normal",
            "NormalNC",
            "NormalFloat",
            "FloatBorder",
            "SignColumn",
            "EndOfBuffer",
            "LineNr",
            "CursorLineNr",
            "FoldColumn",
            "StatusLine",
            "StatusLineNC",
            "VertSplit",
            "WinSeparator",
            "TabLine",
            "TabLineFill",
            "Pmenu",
            "PmenuSel",
          }

          for _, group in ipairs(groups) do
            vim.api.nvim_set_hl(0, group, { bg = "#000000" })
          end
        end

        local function map_if_free(mode, lhs, rhs, opts)
          local existing = vim.fn.maparg(lhs, mode)
          if existing ~= nil and existing ~= "" then
            vim.notify("Skipping keymap " .. lhs .. " because it already exists", vim.log.levels.WARN)
            return
          end

          vim.keymap.set(mode, lhs, rhs, opts)
        end

        vim.keymap.set("n", "<leader>w", "<cmd>write<cr>", { desc = "Write file" })
        vim.keymap.set("n", "<leader>q", "<cmd>quit<cr>", { desc = "Quit" })
        vim.keymap.set("n", "<leader>e", "<cmd>Neotree toggle<cr>", { desc = "Toggle file explorer" })
        vim.keymap.set("n", "<leader>ff", "<cmd>Telescope find_files<cr>", { desc = "Find files" })
        vim.keymap.set("n", "<leader>fg", "<cmd>Telescope live_grep<cr>", { desc = "Live grep" })
        vim.keymap.set("n", "<leader>fb", "<cmd>Telescope buffers<cr>", { desc = "Buffers" })
        vim.keymap.set("n", "<leader>fh", "<cmd>Telescope help_tags<cr>", { desc = "Help tags" })
        vim.keymap.set("n", "<leader>ca", vim.lsp.buf.code_action, { desc = "Code action" })
        vim.keymap.set("n", "<leader>rn", vim.lsp.buf.rename, { desc = "Rename symbol" })
        vim.keymap.set("n", "gd", vim.lsp.buf.definition, { desc = "Go to definition" })
        vim.keymap.set("n", "gr", vim.lsp.buf.references, { desc = "Go to references" })
        vim.keymap.set("n", "K", vim.lsp.buf.hover, { desc = "Hover" })
        vim.keymap.set("n", "[d", vim.diagnostic.goto_prev, { desc = "Previous diagnostic" })
        vim.keymap.set("n", "]d", vim.diagnostic.goto_next, { desc = "Next diagnostic" })

        vim.cmd.colorscheme("gruvbox")
        force_black_background()

        vim.api.nvim_create_autocmd("ColorScheme", {
          callback = force_black_background,
        })

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

        vim.g.mkdp_auto_start = 0
        vim.g.mkdp_auto_close = 1
        vim.g.mkdp_refresh_slow = 0
        vim.g.mkdp_command_for_global = 0
        vim.g.mkdp_open_to_the_world = 0
        vim.g.mkdp_open_ip = "127.0.0.1"
        vim.g.mkdp_browser = ""
        vim.g.mkdp_echo_preview_url = 1
        vim.g.mkdp_theme = "dark"

        map_if_free("n", "<leader>M", "<cmd>MarkdownPreview<cr>", { desc = "Markdown preview open" })
        map_if_free("n", "<leader>m", "<cmd>MarkdownPreviewStop<cr>", { desc = "Markdown preview close" })

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

        force_black_background()
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
