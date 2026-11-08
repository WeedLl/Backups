-- vimtex: грузим сразу (нужен для .tex файлов с самого начала)
require("configs.vimtex")  -- выставит vim.g ДО загрузки
vim.pack.add({
  "https://github.com/lervag/vimtex",
})
-- vimtex загрузится и прочитает vim.g

-- render-markdown: ленивая загрузка по filetype
vim.pack.add({
  "https://github.com/MeanderingProgrammer/render-markdown.nvim",
}, { load = function() end })

vim.api.nvim_create_autocmd("FileType", {
  group = vim.api.nvim_create_augroup("RenderMdLazy", { clear = true }),
  pattern = "markdown",
  callback = function()
    vim.cmd.packadd("render-markdown.nvim")
    -- treesitter должен быть загружен к этому моменту
    local ts_packs = vim.pack.get({ "nvim-treesitter" })
    local ts_pack = ts_packs["nvim-treesitter"]
    if not ts_pack or not ts_pack[1] or not ts_pack[1].active then
      vim.cmd.packadd("nvim-treesitter")
      require("configs.treesitter")
    end
    require("configs.render-markdown")
  end,
})

