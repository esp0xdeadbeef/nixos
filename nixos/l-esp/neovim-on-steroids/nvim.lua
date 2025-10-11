-- Bootstrap lazy.nvim
local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not vim.loop.fs_stat(lazypath) then
  vim.fn.system({ "git", "clone", "--filter=blob:none", "https://github.com/folke/lazy.nvim.git", lazypath })
end
vim.opt.rtp:prepend(lazypath)

require("lazy").setup({
  {
    "nmac427/guess-indent.nvim",
    config = function()
      require("guess-indent").setup({})
    end,
  },
  {
  "nvim-telescope/telescope.nvim",
  tag = "0.1.5",
  dependencies = { "nvim-lua/plenary.nvim" },
  config = function()
    local telescope = require("telescope")
    local builtin = require("telescope.builtin")

    telescope.setup({
      defaults = {
        layout_strategy = "horizontal",
        layout_config = { width = 0.9, preview_cutoff = 120 },
        sorting_strategy = "ascending",
        prompt_prefix = " ",
        selection_caret = " ",
      },
    })

    -- keymaps
    vim.keymap.set("n", "<leader>f", builtin.find_files, { desc = "Fuzzy find files" })
    vim.keymap.set("n", "<leader>g", builtin.live_grep, { desc = "Live grep" })
    vim.keymap.set("n", "<leader>b", builtin.buffers, { desc = "Fuzzy find buffers" })
    vim.keymap.set("n", "<leader>h", builtin.help_tags, { desc = "Help tags" })
  end,
},


  {
  "trixnz/sops.nvim",
  lazy = false,  -- or `true` and specify filetypes/patterns
  config = function()
    require("sops").setup({
      -- optional config overrides
      -- e.g. enable only for *.sops.yaml, etc.
    })
  end,
},
 -- Markdown preview in browser
  {
    "toppair/peek.nvim",
    build = "deno task --quiet build:fast",
    ft = { "markdown" },
    config = function()
      require("peek").setup({ theme = "dark", app = "browser" })
      vim.keymap.set("n", "<leader>M", function() require("peek").open() end,  { desc = "Markdown preview open" })
      vim.keymap.set("n", "<leader>m", function() require("peek").close() end, { desc = "Markdown preview close" })
    end,
  },

  -- Inline image rendering (Neovide only)
  {
    "3rd/image.nvim",
    dependencies = { "nvim-lua/plenary.nvim" },
    config = function()
      if not vim.g.neovide then return end
      vim.env.TERM = "xterm-256color"
      local ok, image = pcall(require, "image")
      if not ok then return end
      image.setup({
        backend = "magick_cli",
        integrations = {
          markdown = {
            enabled = true,
            download_remote_images = true,
            clear_in_insert_mode = false,
          },
        },
      })
    end,
  },

  -- File explorer
  {
    "nvim-tree/nvim-tree.lua",
    dependencies = { "nvim-tree/nvim-web-devicons" },
    config = function()
      require("nvim-tree").setup({
        view = { width = 35, side = "left" },
        filters = { dotfiles = false },
        git = { enable = true },
      })
      vim.keymap.set("n", "<leader>e", ":NvimTreeToggle<CR>", { desc = "Toggle file explorer" })
    end,
  },

  -- Paste clipboard images as files
  {
    "HakonHarnes/img-clip.nvim",
    config = function()
      require("img-clip").setup({
        default = {
          dir_path = "images",
          confirm_name = false,
          file_name = "%Y-%m-%d-%H%M%S",
          use_absolute_path = false,
          drag_and_drop = { insert_mode = true },
        },
      })
      vim.keymap.set("n", "<leader>p", function()
        local buf_dir = vim.fn.expand("%:p:h")
        if buf_dir == "" then buf_dir = vim.fn.getcwd() end
        require("img-clip").paste_image({
          dir_path = buf_dir .. "/images",
          confirm_name = false,
        })
      end, { desc = "Paste image to ./images" })
    end,
  },
  {
  "moll/vim-bbye",
  config = function()
    vim.keymap.set("n", "<leader>q", ":Bdelete<CR>", { desc = "Close buffer like VSCode tab" })
  end,
},
{
  "akinsho/bufferline.nvim",
  dependencies = "nvim-tree/nvim-web-devicons",
  config = function()
    require("bufferline").setup({})
    vim.opt.termguicolors = true
    vim.opt.showtabline = 2
  end,
},
{ "neovim/nvim-lspconfig" },
{ "hrsh7th/nvim-cmp" },
{ "hrsh7th/cmp-nvim-lsp" },
{ "L3MON4D3/LuaSnip" },
{ "saadparwaiz1/cmp_luasnip" },


  -- Optional: PDF reader, Avante AI assistant
  { "r-pletnev/pdfreader.nvim", dependencies = { "folke/snacks.nvim" } },
  { "yetone/avante.nvim", dependencies = { "MunifTanjim/nui.nvim", "nvim-lua/plenary.nvim" } },
})

-- Project-local session management (autosaves even if pkilled)
vim.opt.sessionoptions = { "buffers", "curdir", "tabpages", "winsize", "help", "globals" }

-- Local state
local function get_session_file()
  local cwd = vim.fn.getcwd()
  local hash = vim.fn.sha256(cwd):sub(1, 32)
  local sessions_dir = vim.fn.stdpath("data") .. "/sessions"
  vim.fn.mkdir(sessions_dir, "p")
  return sessions_dir .. "/" .. hash .. ".vim"
end

local function save_session()
  local ok, err = pcall(function()
    vim.cmd("silent! mksession! " .. vim.fn.fnameescape(get_session_file()))
  end)
  if not ok then
    vim.notify("Failed to save session: " .. err, vim.log.levels.WARN)
  end
end

local function load_session()
  local sessionfile = get_session_file()
  if vim.fn.filereadable(sessionfile) == 1 then
    vim.cmd("silent! source " .. vim.fn.fnameescape(sessionfile))
  end
  vim.schedule(function()
      require("nvim-tree.api").tree.open()
    end)
end

vim.api.nvim_create_autocmd("VimEnter", {
  once = true,
  callback = load_session,
})

vim.api.nvim_create_autocmd({ "BufLeave", "FocusLost", "BufWritePost", "VimLeavePre" }, {
  callback = save_session,
})

-- Periodic autosave (every 1 minute)
vim.fn.timer_start(1 * 60 * 1000, function()
  if vim.fn.bufnr('%') ~= -1 then
    save_session()
  end
end, { ['repeat'] = -1 })


vim.opt.number = true
vim.opt.relativenumber = true
