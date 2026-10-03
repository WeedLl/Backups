local ok, lualine = pcall(require, "lualine")
if not ok then
  return
end

lualine.setup({
  sections = {
    lualine_a = { "mode" },
    lualine_b = { { "filename", path = 1 }, "modified", "readonly" },
    lualine_c = { "diagnostics" },
    lualine_x = { "encoding", "fileformat", "filetype" },
    lualine_y = { "progress" },
    lualine_z = { "location" },
  },
})

