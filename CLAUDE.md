# Workspace instructions

This repository is a reusable AI/devcontainer setup (Claude config, hooks,
container definition) that is shared across different projects. It holds no
project code itself.

## Nested repositories

The workspace root may contain subfolders that are not tracked by this repo
but are independent git repositories (typically ignored via
`.git/info/exclude`). Each has its own history, conventions and AI
instructions.

- Before working in such a repo (editing, committing, opening PRs, running
  tooling), read its local AI instruction files: `AGENTS.md`, `CLAUDE.md`,
  and similar (e.g. `.github/copilot-instructions.md`, `CONTRIBUTING.md`) at
  the repo root and in any subdirectories you touch.
- Their rules (commit message format, branching, testing, style, etc.) take
  precedence over general defaults and over these workspace instructions.
- Rules are scoped: apply a repo's instructions only to work inside that
  repo. When a task spans several repos, follow each repo's rules for its
  own changes (e.g. separate commits per repo, each in that repo's format).
- Run git commands from within the respective repo directory. Never commit
  project changes to this setup repo, and never commit setup changes to a
  project repo.
