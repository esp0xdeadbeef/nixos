vim.g.mapleader = " "
vim.g.maplocalleader = " "

vim.opt.number = true
vim.opt.relativenumber = true
vim.opt.signcolumn = "yes"
vim.opt.termguicolors = true
vim.opt.mouse = "a"
vim.opt.clipboard = "unnamedplus"
vim.opt.expandtab = true
vim.opt.shiftwidth = 2
vim.opt.tabstop = 2
vim.opt.smartindent = true
vim.opt.ignorecase = true
vim.opt.smartcase = true
vim.opt.undofile = true
vim.opt.updatetime = 250
vim.opt.timeoutlen = 300
vim.opt.splitright = true
vim.opt.splitbelow = true
vim.opt.completeopt = { "menu", "menuone", "noselect" }

local function setup(name, configure)
local ok, plugin = pcall(require, name)
if not ok then
vim.notify("Plugin not available: " .. name, vim.log.levels.WARN)
return nil
end

if configure then
configure(plugin)
elseif type(plugin.setup) == "function" then
plugin.setup({})
end

return plugin
end

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
vim.api.nvim_create_autocmd("ColorScheme", { callback = force_black_background })

setup("which-key")
setup("gitsigns")
setup("ibl")
setup("lualine", function(lualine)
lualine.setup({
options = {
theme = "gruvbox",
globalstatus = true,
},
})
end)

setup("neo-tree", function(neo_tree)
neo_tree.setup({
filesystem = {
follow_current_file = {
enabled = true,
},
},
})
end)

setup("telescope")
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

setup("nvim-treesitter")
vim.api.nvim_create_autocmd("FileType", {
callback = function(event)
pcall(vim.treesitter.start, event.buf)

if pcall(require, "nvim-treesitter") then
vim.bo[event.buf].indentexpr = "v:lua.require'nvim-treesitter'.indentexpr()"
end
end,
})

local capabilities = vim.lsp.protocol.make_client_capabilities()
local blink = setup("blink.cmp", function(cmp)
cmp.setup({
keymap = {
preset = "default",
},
appearance = {
nerd_font_variant = "mono",
},
sources = {
default = { "lsp", "path", "snippets", "buffer" },
},
})
end)

if blink and type(blink.get_lsp_capabilities) == "function" then
capabilities = blink.get_lsp_capabilities(capabilities)
end

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
timeout_ms = 3000,
})
end,
})

force_black_background()
