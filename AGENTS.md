# AGENTS.md

## Project direction

`fork.nvim` should start as a golden-path Neovim plugin for managing workstreams.

The initial implementation should not try to be broadly configurable. We should first make the core workflow feel right, then introduce configuration once the behavior and abstractions are clear.

## Golden path

A workstream currently means:

- a Git worktree
- a mandatory `tmux` session
- copied local setup files when present, such as `.env` and `.env.local`
- keyboard-driven Neovim commands for creating and deleting workstreams

`radar.nvim` is expected to handle workspace tracking and switching. `fork.nvim` should focus on creating, deleting, and managing workstreams.

## Implementation guidance

- Always push completed work to remote `main`.
- Prefer simple, explicit behavior over options.
- Do not add configuration unless the user explicitly asks for it later.
- Keep the workflow keyboard-first.
- Keep `tmux` mandatory for now.
- Keep the implementation lightweight and Lua-native.
- Avoid duplicating workspace tracking/switching functionality from `radar.nvim`.
