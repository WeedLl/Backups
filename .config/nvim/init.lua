-- Обязательно первая строка: байткеш для быстрого старта
vim.loader.enable()

vim.g.mapleader = " "
vim.g.maplocalleader = " "

require("core.options")
require("core.autocmds")
require("core.keymaps")

-- Хук для TSUpdate: должен быть ДО vim.pack.add
vim.api.nvim_create_autocmd("PackChanged", {
  callback = function(ev)
    local name, kind = ev.data.spec.name, ev.data.kind
    if name == "nvim-treesitter" and kind == "update" then
      if not ev.data.active then
        vim.cmd.packadd("nvim-treesitter")
      end
      vim.cmd("TSUpdate")
    end
  end,
})
require("plugins")

-- Отключаем неиспользуемое, чтобы Health не ругался
vim.g.loaded_node_provider = 0
vim.g.loaded_perl_provider = 0
vim.g.loaded_ruby_provider = 0
