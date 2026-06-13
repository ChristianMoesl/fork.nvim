local config = require("fork.config")
local workstream = require("fork.workstream")

local M = {}

M.create = workstream.create
M.delete = workstream.delete

function M.setup()
  vim.api.nvim_create_user_command("ForkCreate", function(command)
    M.create({ name = command.args ~= "" and command.args or nil })
  end, {
    nargs = "?",
    desc = "Create a new fork.nvim fork",
    force = true,
  })

  vim.api.nvim_create_user_command("ForkDelete", function(command)
    M.delete({ path = command.args ~= "" and command.args or nil })
  end, {
    nargs = "?",
    complete = "dir",
    desc = "Delete a fork.nvim workstream",
    force = true,
  })

  vim.keymap.set("n", config.keymaps.create, M.create, { desc = "Create fork" })
  vim.keymap.set("n", config.keymaps.delete, M.delete, { desc = "Delete workstream" })
end

return M
