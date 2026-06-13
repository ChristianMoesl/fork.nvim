# fork.nvim

`fork.nvim` is a lightweight Neovim plugin, written in Lua, for creating, deleting, and managing parallel work streams.

The goal is to make it fast to branch off from your current context when a new task appears. `fork.nvim` is intended to complement [`radar.nvim`](https://github.com/ChristianMoesl/radar.nvim): `radar.nvim` keeps track of available workspaces and makes it easy to switch between them, while `fork.nvim` focuses on creating, deleting, and managing those workspaces. For example, while working on one issue you may notice a small unrelated fix in the same repository. Instead of disrupting your current editor, terminal, and Git state, `fork.nvim` should help you create a separate workspace for that new thread of work.

A workspace may include things like:

- a new `tmux` session
- a Git worktree for the selected branch or task
- copied project setup files, such as `.env` or other local configuration
- a Neovim instance opened in the new workspace

The plugin should support creating workspaces both inside the current repository and in other repositories, making it easy to switch between multiple active tasks without losing context. Once a task is finished, there should also be a clean way to delete the work stream and remove the resources it created. All core actions should be available through keyboard shortcuts.

## Project vision

`fork.nvim` aims to provide a small, composable workflow for:

- starting a new work stream from the current project
- starting a new work stream in a different project
- isolating task-specific Git state with worktrees
- preserving local project setup where useful
- jumping between active work streams quickly
- cleanly deleting finished work streams
- controlling the workflow through keyboard shortcuts
- integrating naturally with terminal-based workflows such as `tmux`

The focus is on being lightweight and practical rather than imposing a large project-management system. The initial implementation follows a single golden path instead of exposing configuration too early. Configuration can be added later once the core workflow feels right. It should integrate well with `radar.nvim` instead of duplicating workspace tracking and switching functionality.

## Initial implementation

The first implementation provides a small Lua API, user commands, and fixed golden-path keymaps:

```lua
require("fork").setup()
```

Current golden-path behavior:

- workstreams are created below `~/workstreams`
- `.env` and `.env.local` are copied when present
- `ForkCreate` must be run from inside `tmux`
- every workstream gets a mandatory `tmux` session running `nvim .`
- after creation, fork.nvim immediately switches to the new `tmux` session
- `<leader>wc` creates a workstream
- `<leader>wd` deletes a workstream

Commands:

- `:ForkCreate [name]` creates a new Git worktree, starts a `tmux` session running Neovim, and immediately switches to it.
- `:ForkDelete [path]` removes a Git worktree and kills the matching `tmux` session.

Lua API:

```lua
require("fork").create({ name = "small-fix" })
require("fork").delete({ path = "~/workstreams/my-project/small-fix" })
```

Later, once the golden path is working well, we can add configuration and explicit `radar.nvim` integration points.
