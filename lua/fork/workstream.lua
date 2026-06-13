local config = require("fork.config")

local M = {}

local function notify(message, level)
  vim.notify(message, level or vim.log.levels.INFO, { title = "fork.nvim" })
end

local function run(args, opts)
  opts = opts or {}
  local result = vim.system(args, { cwd = opts.cwd, text = true }):wait()
  if result.code ~= 0 then
    error((result.stderr and result.stderr ~= "" and result.stderr) or table.concat(args, " "))
  end
  return vim.trim(result.stdout or "")
end

local function require_executable(name)
  if vim.fn.executable(name) ~= 1 then
    error("fork.nvim requires `" .. name .. "` to be installed")
  end
end

local function require_tmux_client()
  if vim.env.TMUX == nil or vim.env.TMUX == "" then
    error("ForkCreate must be run from inside a tmux session so fork.nvim can switch to the new fork")
  end
end

local function exists(path)
  return vim.uv.fs_stat(path) ~= nil
end

local function mkdir(path)
  vim.fn.mkdir(path, "p")
end

local function current_repo_root()
  return run({ "git", "rev-parse", "--show-toplevel" })
end

local function current_repo_name(repo)
  return vim.fn.fnamemodify(repo, ":t")
end

local function session_name_for(repo_name, workstream_name)
  return (repo_name .. "-" .. workstream_name):gsub("[^%w_-]", "-")
end

local function normalize_dir(path)
  path = vim.fn.fnamemodify(path, ":p")
  return path:gsub("/$", "")
end

local function copy_setup_files(source, target)
  for _, file in ipairs(config.copy_files) do
    local from = source .. "/" .. file
    local to = target .. "/" .. file
    if exists(from) and not exists(to) then
      vim.fn.mkdir(vim.fn.fnamemodify(to, ":h"), "p")
      vim.fn.writefile(vim.fn.readfile(from, "b"), to, "b")
    end
  end
end

local function create_tmux_session(session_name, cwd)
  local has_session = vim.system({ "tmux", "has-session", "-t", session_name }, { text = true }):wait()
  if has_session.code ~= 0 then
    run({ "tmux", "new-session", "-d", "-s", session_name, "-c", cwd, "nvim ." })
  end
end

local function switch_to_tmux_session(session_name)
  run({ "tmux", "switch-client", "-t", session_name })
end

local function kill_tmux_session(session_name)
  local has_session = vim.system({ "tmux", "has-session", "-t", session_name }, { text = true }):wait()
  if has_session.code == 0 then
    run({ "tmux", "kill-session", "-t", session_name })
  end
end

function M.create(opts)
  opts = opts or {}

  require_executable("git")
  require_executable("tmux")
  require_executable("nvim")
  require_tmux_client()

  local repo = opts.repo or current_repo_root()
  local repo_name = current_repo_name(repo)
  local name = opts.name or vim.fn.input("Fork name: ")

  if name == nil or name == "" then
    notify("Fork creation cancelled", vim.log.levels.WARN)
    return
  end

  local branch = opts.branch or name
  local workspace_root = vim.fn.expand(config.workspace_root)
  local path = opts.path or (workspace_root .. "/" .. repo_name .. "/" .. name)
  local session_name = opts.session_name or session_name_for(repo_name, name)

  mkdir(vim.fn.fnamemodify(path, ":h"))

  if exists(path) then
    error("Fork already exists: " .. path)
  end

  local ok, err = pcall(function()
    run({ "git", "worktree", "add", "-b", branch, path }, { cwd = repo })
    copy_setup_files(repo, path)
    create_tmux_session(session_name, path)
  end)

  if not ok then
    if exists(path) then
      pcall(run, { "git", "worktree", "remove", "--force", path }, { cwd = repo })
    end
    error(err)
  end

  local fork = {
    name = name,
    branch = branch,
    repo = repo,
    path = path,
    session_name = session_name,
  }

  switch_to_tmux_session(session_name)
  notify("Created fork: " .. name)
  return fork
end

function M.delete(opts)
  opts = opts or {}

  local path = opts.path or vim.fn.input("Workspace path to delete: ", vim.fn.getcwd(), "dir")
  if path == nil or path == "" then
    notify("Workstream deletion cancelled", vim.log.levels.WARN)
    return
  end

  path = normalize_dir(path)
  local workstream_name = vim.fn.fnamemodify(path, ":t")
  local repo_name = vim.fn.fnamemodify(vim.fn.fnamemodify(path, ":h"), ":t")
  local session_name = opts.session_name or session_name_for(repo_name, workstream_name)

  local confirm = opts.force or vim.fn.confirm("Delete workstream at " .. path .. "?", "&Yes\n&No", 2)
  if confirm ~= true and confirm ~= 1 then
    notify("Workstream deletion cancelled", vim.log.levels.WARN)
    return
  end

  kill_tmux_session(session_name)
  run({ "git", "worktree", "remove", path })

  local workstream = {
    path = path,
    session_name = session_name,
  }

  notify("Deleted workstream: " .. path)
  return workstream
end

return M
