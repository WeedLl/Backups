local neo_tree = require("neo-tree")

neo_tree.setup({
  sources = { "filesystem", "buffers", "git_status" },
  filesystem = {
    filtered_items = {
      visible = true,
      hide_dotfiles = false,
      hide_gitignored = false,
    },
    follow_current_file = { enabled = true },
    use_libuv_file_watcher = true,
  },
  window = { width = 30 },
})

