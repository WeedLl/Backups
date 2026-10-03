-- Blink.cmp: ленивая загрузка при входе в Insert
vim.pack.add({
  { src = "https://github.com/saghen/blink.cmp", version = "v1" },
  "https://github.com/rafamadriz/friendly-snippets",
}, { load = function() end })

vim.api.nvim_create_autocmd("InsertEnter", {
  group = vim.api.nvim_create_augroup("BlinkLazy", { clear = true }),
  once = true,
  callback = function()
    vim.cmd.packadd("blink.cmp")
    vim.cmd.packadd("friendly-snippets")
    require("configs.blink")
  end,
})

-- LuaSnip: ленивая загрузка при входе в Insert
vim.pack.add({
  { src = "https://github.com/L3MON4D3/LuaSnip", version=vim.version.range("2") },
}, { load = function() end })

vim.api.nvim_create_autocmd("InsertEnter", {
  group = vim.api.nvim_create_augroup("LuasnipLazy", { clear = true }),
  once = true,
  callback = function()
    vim.cmd.packadd("LuaSnip")
    vim.cmd.packadd("friendly-snippets")  -- уже может быть загружен blink, это ок
    require("configs.luasnip")
  end,
})

