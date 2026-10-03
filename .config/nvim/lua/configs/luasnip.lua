print("DEBUG: loading luasnip config")
vim.cmd("packadd LuaSnip")
print("DEBUG: after packadd")
local ok, luasnip = pcall(require, "luasnip")
print("DEBUG: pcall result", ok, luasnip)
if not ok then
  return
end

local ok, luasnip = pcall(require, "luasnip")
if not ok then
  return
end

require("luasnip.loaders.from_vscode").lazy_load()
require("luasnip.loaders.from_snipmate").lazy_load()
require("luasnip.loaders.from_lua").load({ paths = vim.fn.stdpath("config") .. "/luasnippets" })
require("luasnip.loaders.from_snipmate").lazy_load({ paths = vim.fn.stdpath("config") .. "/snippets" })

-- Клавиши (аналог UltiSnips-конфига)
-- Expand / jump — <C-l> (как UltiSnipsExpandTrigger)
vim.keymap.set({ "i", "s" }, "<C-l>", function()
  luasnip.expand_or_jump()
end, { desc = "Expand/jump snippet" })

-- Jump forward — <C-b> (как UltiSnipsJumpForwardTrigger)
vim.keymap.set({ "i", "s" }, "<C-b>", function()
  luasnip.jump(1)
end, { desc = "Jump forward" })

-- Jump backward — <C-z> (как UltiSnipsJumpBackwardTrigger)
vim.keymap.set({ "i", "s" }, "<C-z>", function()
  luasnip.jump(-1)
end, { desc = "Jump backward" })

