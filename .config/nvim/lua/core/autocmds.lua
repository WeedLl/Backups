local augroup = vim.api.nvim_create_augroup("UserAutocmds", { clear = true })

-- Отключение подсветки строки в режиме Insert
vim.api.nvim_create_autocmd("InsertEnter", {
  group = augroup,
  callback = function() vim.opt.cursorline = false end,
})
vim.api.nvim_create_autocmd("InsertLeave", {
  group = augroup,
  callback = function() vim.opt.cursorline = true end,
})

-- Fallback на indent-folding для файлов без Treesitter-парсера (режим fold)
vim.api.nvim_create_autocmd("FileType", {
  group = augroup,
  callback = function()
    local ft = vim.bo.filetype
    if ft == "" or ft == "text" or ft == "plaintext" then
      vim.opt_local.foldmethod = "indent"
    end
  end,
})

-- Оставляем обычные табы для файлов .snippets (проблемы парсера luasnip из .snippets)
-- требует табы в теле сниппетов
vim.api.nvim_create_autocmd({ "BufRead", "BufNewFile" }, {
  pattern = "*.snippets",
  callback = function()
    vim.bo.expandtab = false
    vim.bo.tabstop = 4
    vim.bo.shiftwidth = 4
  end,
})
-- Python: обрезка пробелов перед сохранением
vim.api.nvim_create_autocmd("BufWritePre", {
  group = augroup,
  pattern = "*.py",
  callback = function()
    local save = vim.fn.winsaveview()
    vim.cmd([[%s/\s\+$//e]])
    vim.fn.winrestview(save)
  end,
})

-- Python: умные отступы
-- treesitter indent должен это делать сам, поэтому закомментировано.
--vim.api.nvim_create_autocmd("BufRead", {
--  group = augroup,
--  pattern = "*.py",
--  callback = function()
--    vim.opt.smartindent = true
--    vim.opt.cinwords = "if,elif,else,for,while,try,except,finally,def,class"
--  end,
--})

-- Закрытие Neovim, если последнее окно — файловое дерево
vim.api.nvim_create_autocmd("BufEnter", {
  group = augroup,
  pattern = "*",
  callback = function()
    local bufname = vim.api.nvim_buf_get_name(0)
    if vim.fn.tabpagenr("$") == 1 and vim.fn.winnr("$") == 1
       and (bufname:match("neo%-tree") or bufname:match("NvimTree")) then
      vim.schedule(function()
        if vim.fn.winnr("$") == 1 then
          vim.cmd("quit")
        end
      end)
    end
  end,
})
