local M = {}

-- Golden-path constants. These are intentionally not configurable yet.
M.workspace_root = vim.fn.expand("~/workstreams")
M.copy_files = { ".env", ".env.local" }
M.keymaps = {
  create = "<leader>wc",
  delete = "<leader>wd",
}

return M
