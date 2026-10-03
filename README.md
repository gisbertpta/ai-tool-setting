# AI dev envelope

A reusable workspace that wraps one or more **working repos** in a sandboxed
devcontainer for running Claude Code with permission prompts skipped.

This repo holds **no project code**. It only holds the parts around the code:
the container definition, the egress proxy, secret masking, Claude settings,
and workspace-wide AI instructions. The working repos are cloned into the
workspace root as independent git repositories and are ignored by this repo.

```
/workspace                    ← this repo (the envelope)
├── .devcontainer/            container, proxy, secret masking   → see .devcontainer/README.md
│   └── .claude/              project Claude settings + hooks (mounted ro at /workspace/.claude)
├── .dockerignore             allowlist for the image build context (the workspace root)
├── CLAUDE.md                 workspace-wide AI instructions
├── README.md
│
├── ki-zfw-wm-code/           ┐
├── ki-zfw-wm-specs/          ├ working repos: own git history, own AI instructions,
└── ki-zfw-wm-umbrella/       ┘ NOT tracked here (ignored via .git/info/exclude)
```

## What the envelope provides

- **Sandboxed container.** Runs as an unprivileged `claude` user with all
  capabilities dropped and `no-new-privileges`.
- **Egress allowlist.** The container has no direct internet route. All
  traffic goes through a squid proxy that only allows the domains in
  `.devcontainer/proxy/allowlist.txt`.
- **Secret masking.** Secret files and folders in the working repos are covered
  by read-only mounts, either with placeholder "dummy" copies or `/dev/null`.
  `check-exclusions` checks this at container start, and the `claude` command
  won't start if anything is left unmasked.
- **Read-only sandbox config.** Inside the container, `.devcontainer/` and
  `.claude/` are mounted read-only, so the agent can't change its own sandbox.
- **AI instructions per repo.** [`CLAUDE.md`](CLAUDE.md) tells the agent to read
  and follow each working repo's own `AGENTS.md` / `CLAUDE.md` / contributing
  rules, and to keep commits separate per repo.

How it works, prerequisites, usage and debugging are covered in
[`.devcontainer/README.md`](.devcontainer/README.md).

## Quick start

1. Clone this repo, then clone the working repos into its root:
   ```bash
   git clone <envelope-url> workspace && cd workspace
   git clone <working-repo-url> ki-zfw-wm-code
   ```
2. Make sure the working repos are ignored by the envelope (see below).
3. Create the host prerequisites listed in
   [`.devcontainer/README.md`](.devcontainer/README.md#prerequisites-host)
   (`~/.build-secrets/`, `~/.claude/`, `~/.claude.json`, `~/.gitconfig`).
4. Open the folder in VS Code and run **Dev Containers: Reopen in Container**,
   or use the devcontainer CLI:
   ```bash
   devcontainer up --workspace-folder .
   devcontainer exec --workspace-folder . zsh
   ```
5. Inside the container, run `claude`.

## Ignoring working repos

Working repos are ignored through `.git/info/exclude`, not `.gitignore`. This
keeps the envelope free of project-specific names, but the file is local to
each clone, so set it up after cloning:

```bash
echo '/ki-zfw-wm-*/' >> .git/info/exclude
git status    # the working repos must not show up
```

Run git commands from inside the respective directory: the envelope root for
setup changes, a working repo for project changes. Never commit project changes
to the envelope, or setup changes to a working repo.

## Adding a working repo

1. **Clone** it into the workspace root and add it to `.git/info/exclude`.
2. **Mask its secrets.** For each secret file or folder:
   - add the path to `.devcontainer/excluded-files`,
   - add a read-only mount in `.devcontainer/docker-compose.yml`
     (`/dev/null` or a dummy under `.devcontainer/dummy-<repo>/`),
   - rebuild and check that `check-exclusions` reports `OK`.

   Details are in
   [Mask an additional secret file](.devcontainer/README.md#mask-an-additional-secret-file).
3. **Build-time dependencies (optional).** If the image should preinstall the
   repo's toolchain, add the needed files to the `.dockerignore` allowlist and
   `COPY` them in `.devcontainer/Dockerfile`.
4. **Network access (optional).** If tooling inside the container needs another
   domain, add it to `.devcontainer/proxy/allowlist.txt`. Keep the list short.
5. **AI instructions.** Put repo-specific rules in the working repo itself
   (`AGENTS.md`, `CLAUDE.md`, …), not in the envelope.

## Current state

The envelope is generic in structure, but the current image is still built
around `ki-zfw-wm-code`. The `Dockerfile` copies that repo's `pyproject.toml`,
`uv.lock`, pre-commit config and CA certificate to preinstall its Python 3.11
environment. That means the image build needs `ki-zfw-wm-code` to be present.
The masked paths in `excluded-files` / `docker-compose.yml` are also specific
to that repo. To use the envelope for another project, adjust these places.

Known security gaps (writable host `~/.claude`, the ntfy Stop hook, allowlisted
domains as exfiltration channels) are listed in
[`.devcontainer/README.md`](.devcontainer/README.md#security-notes--known-gaps).
