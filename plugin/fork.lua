if vim.g.loaded_fork_nvim then
  return
end
vim.g.loaded_fork_nvim = true

-- Commands are registered from require('fork').setup().
