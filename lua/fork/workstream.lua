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

local function current_repo_root(cwd)
  return run({ "git", "rev-parse", "--show-toplevel" }, { cwd = cwd })
end

local function current_repo_name(repo)
  return vim.fn.fnamemodify(repo, ":t")
end

local function branch_sort_key(branch)
  local name = branch:gsub("^origin/", "")
  if name == "main" then
    return "0"
  end
  if name == "master" then
    return "1"
  end
  return "2" .. name
end

local function sort_branches(branches)
  table.sort(branches, function(left, right)
    return branch_sort_key(left) < branch_sort_key(right)
  end)
end

local function list_start_points(repo)
  local output = run({
    "git",
    "for-each-ref",
    "--format=%(refname)%09%(refname:short)%09%(symref)",
    "refs/heads",
    "refs/remotes/origin",
  }, { cwd = repo })
  local origin_branches = {}
  local local_branches = {}

  for line in output:gmatch("[^\n]+") do
    local refname, short_name, symref = line:match("^([^\t]+)\t([^\t]+)\t?(.*)$")
    if refname and short_name and not refname:match("^refs/remotes/.+/HEAD$") and symref == "" then
      if short_name:match("^origin/") then
        table.insert(origin_branches, short_name)
      elseif refname:match("^refs/heads/") then
        table.insert(local_branches, short_name)
      end
    end
  end

  sort_branches(origin_branches)
  sort_branches(local_branches)

  return vim.list_extend(origin_branches, local_branches)
end

local function select_start_point(repo)
  local branches = list_start_points(repo)
  if #branches == 0 then
    return nil
  end

  local choices = branches

  local menu = { "Fork from:" }
  for index, choice in ipairs(choices) do
    table.insert(menu, index .. ". " .. choice)
  end

  local choice = vim.fn.inputlist(menu)
  if choice == nil or choice < 1 or choice > #choices then
    return false
  end

  return choices[choice]
end

local function session_name_for(repo_name, workstream_name)
  local name = (repo_name .. "-" .. workstream_name):gsub("[^%w_-]", "-")
  name = name:gsub("^[^%w]+", ""):gsub("[^%w]+$", "")
  if name == "" then
    return "fork"
  end
  return name
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

local function create_input(opts, on_confirm)
  local snacks = rawget(_G, "Snacks")
  if snacks and snacks.input then
    if type(snacks.input) == "function" then
      return snacks.input(opts, on_confirm)
    elseif snacks.input.input then
      return snacks.input.input(opts, on_confirm)
    end
  end

  vim.ui.input(opts, on_confirm)
end

local function is_subpath(path, root)
  path = normalize_dir(path)
  root = normalize_dir(root)
  return path == root or path:sub(1, #root + 1) == root .. "/"
end

local function discover_repos()
  local repos = {}
  local seen = {}
  local workspace_root = vim.fn.expand(config.workspace_root)

  local function add(path)
    local ok, repo = pcall(current_repo_root, path)
    if not ok or repo == "" or is_subpath(repo, workspace_root) or seen[repo] then
      return
    end

    seen[repo] = true
    repos[#repos + 1] = repo
  end

  local ok, current = pcall(current_repo_root)
  if ok then
    add(current)
    add(vim.fn.fnamemodify(current, ":h"))
  end

  local roots = {
    vim.fn.expand("~/workspace"),
    vim.fn.expand("~/code"),
    vim.fn.expand("~/src"),
    vim.fn.expand("~/dev"),
    vim.fn.expand("~/projects"),
  }

  for _, root in ipairs(roots) do
    if exists(root) then
      local result = vim.system({ "find", root, "-maxdepth", "4", "-name", ".git" }, { text = true }):wait()
      if result.code == 0 then
        for git_path in (result.stdout or ""):gmatch("[^\n]+") do
          add(vim.fn.fnamemodify(git_path, ":h"))
        end
      end
    end
  end

  table.sort(repos, function(a, b)
    if a == current then
      return true
    elseif b == current then
      return false
    end
    return a < b
  end)

  return repos
end

local function picker_select(opts)
  local snacks = rawget(_G, "Snacks")
  if snacks and snacks.picker and snacks.picker.pick then
    return snacks.picker.pick({
      title = opts.title,
      prompt = opts.prompt,
      items = opts.items,
      format = "text",
      preview = "none",
      confirm = function(picker, item)
        picker:close()
        if item then
          vim.schedule(function()
            opts.on_choice(item.value)
          end)
        end
      end,
    })
  end

  vim.ui.select(opts.values, {
    prompt = opts.title,
    format_item = opts.format_item,
  }, opts.on_choice)
end

local function select_repo(on_choice)
  local repos = discover_repos()
  if #repos == 0 then
    notify("No Git repositories found", vim.log.levels.ERROR)
    return
  end

  local function label(repo)
    return current_repo_name(repo) .. "  " .. repo
  end

  local items = {}
  for _, repo in ipairs(repos) do
    items[#items + 1] = {
      text = label(repo),
      value = repo,
    }
  end

  picker_select({
    title = "Create fork in repository",
    prompt = "Repo  ",
    values = repos,
    items = items,
    format_item = label,
    on_choice = on_choice,
  })
end

local function repo_branches(repo)
  local result = vim.system({ "git", "branch", "--all", "--format=%(refname:short)" }, { cwd = repo, text = true }):wait()
  if result.code ~= 0 then
    error((result.stderr and result.stderr ~= "" and result.stderr) or "Could not list Git branches")
  end

  local branches = {}
  local seen = {}
  local function add(branch)
    branch = vim.trim(branch or "")
    if branch == "" or branch:match("/HEAD$") or seen[branch] then
      return
    end
    seen[branch] = true
    branches[#branches + 1] = branch
  end

  add("main")
  for branch in (result.stdout or ""):gmatch("[^\n]+") do
    add(branch)
  end

  table.sort(branches, function(a, b)
    if a == "main" then
      return true
    elseif b == "main" then
      return false
    elseif a == "master" then
      return true
    elseif b == "master" then
      return false
    end
    return a < b
  end)

  return branches
end

local function select_branch(repo, on_choice)
  local branches = repo_branches(repo)
  local items = {}
  for _, branch in ipairs(branches) do
    items[#items + 1] = {
      text = branch,
      value = branch,
    }
  end

  picker_select({
    title = "Base branch for " .. current_repo_name(repo),
    prompt = "Branch  ",
    values = branches,
    items = items,
    format_item = tostring,
    on_choice = on_choice,
  })
end

local function create_tmux_session(session_name, cwd)
  local has_session = vim.system({ "tmux", "has-session", "-t", session_name }, { text = true }):wait()
  if has_session.code ~= 0 then
    local escaped_session_name = vim.fn.shellescape(session_name)
    local pi_command = "pi --session-id " .. escaped_session_name .. " --name " .. escaped_session_name

    run({ "tmux", "new-session", "-d", "-s", session_name, "-n", "pi", "-c", cwd, pi_command })
    run({ "tmux", "new-window", "-t", session_name .. ":", "-n", "nvim", "-c", cwd, "nvim ." })
    run({ "tmux", "select-window", "-t", session_name .. ":pi" })
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

  if not opts.name then
    return M.create_dialog()
  end

  require_executable("git")
  require_executable("tmux")
  require_executable("pi")
  require_executable("nvim")
  require_tmux_client()

  local repo = current_repo_root(opts.repo)
  local repo_name = current_repo_name(repo)
  local name = vim.trim(opts.name)

  if name == nil or name == "" then
    notify("Fork creation cancelled", vim.log.levels.WARN)
    return
  end

  local branch = opts.branch or name
  local start_point = opts.start_point or opts.base
  if start_point == nil and opts.select_start_point then
    start_point = select_start_point(repo)
    if start_point == false then
      notify("Fork creation cancelled", vim.log.levels.WARN)
      return
    end
  end

  local workspace_root = vim.fn.expand(config.workspace_root)
  local path = opts.path or (workspace_root .. "/" .. repo_name .. "/" .. name)
  local session_name = opts.session_name or session_name_for(repo_name, name)

  mkdir(vim.fn.fnamemodify(path, ":h"))

  if exists(path) then
    error("Fork already exists: " .. path)
  end

  local ok, err = pcall(function()
    local args = { "git", "worktree", "add", "-b", branch, path }
    if start_point then
      table.insert(args, start_point)
    end
    run(args, { cwd = repo })
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
    start_point = start_point,
    base = start_point,
    repo = repo,
    path = path,
    session_name = session_name,
  }

  switch_to_tmux_session(session_name)
  notify("Created fork: " .. name)
  return fork
end

function M.create_dialog()
  select_repo(function(repo)
    if not repo then
      notify("Fork creation cancelled", vim.log.levels.WARN)
      return
    end

    local ok, err = pcall(select_branch, repo, function(base)
      if not base then
        notify("Fork creation cancelled", vim.log.levels.WARN)
        return
      end

      create_input({
        prompt = "Fork name for " .. current_repo_name(repo) .. " from " .. base .. ": ",
        default = "",
        icon = "󰘬 ",
      }, function(name)
        name = vim.trim(name or "")
        if name == "" then
          notify("Fork creation cancelled", vim.log.levels.WARN)
          return
        end

        local create_ok, create_err = pcall(M.create, {
          repo = repo,
          name = name,
          base = base,
        })
        if not create_ok then
          notify(create_err, vim.log.levels.ERROR)
        end
      end)
    end)

    if not ok then
      notify(err, vim.log.levels.ERROR)
    end
  end)
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
