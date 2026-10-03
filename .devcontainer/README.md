# Claude Code Sandbox (devcontainer)

A devcontainer for running Claude Code with permission prompts skipped, in a
way that limits what the agent can **see** (secrets are masked) and where it can
**send** things (egress is allowlisted).

This folder holds the **generic** part. Everything project-specific comes from
the project layer in the slot `.devcontainer/project` (see the
[top-level README](../README.md) for the two layers and how to start a new project).

> Edit everything in this folder **from the host**. Inside the container,
> `.devcontainer/` is mounted read-only on purpose.

---

## How it works

```
 host (WSL)                                     docker
 ─────────────                                  ──────────────────────────────────────────────
 /workspace  ─────── bind mount ──────────►   ┌─ devcontainer ───────────────┐
 .devcontainer/ ──── bind mount (ro) ─────►   │ user: claude (uid 1000)      │
 project dummies ─── bind mount (ro) ─────►   │ cap_drop ALL                 │
                                              │ no-new-privileges            │
                                              │ HTTPS_PROXY=http://proxy:3128│
                                              └──────────────┬───────────────┘
                                                 network "sandbox" (internal, no gateway)
                                              ┌──────────────┴───────────────┐
                                              │ proxy (squid)                │
                                              │ allows: proxy/allowlist.txt  │
                                              │       + project/allowlist.txt│
                                              └──────────────┬───────────────┘
                                                 network "egress"
                                                          ▼
                                                      internet
```

There are three layers of protection:

1. **Secret masking.** Real secrets in the workspace are covered by read-only bind
   mounts: either placeholder "dummy" files or `/dev/null`. The agent sees the dummy,
   not the real file. The paths come from the project layer.
2. **Exclusion check.** `check-exclusions` checks that every path in
   `project/excluded-files` is really masked. It runs when the container starts,
   and the `claude` command runs it too: `claude` refuses to start if anything is
   unmasked, or if there is no project layer at all.
3. **Egress allowlist.** The devcontainer has no direct route to the internet.
   Its only way out is the `proxy` container, which allows HTTPS to the domains in
   `proxy/allowlist.txt` and `project/allowlist.txt` and blocks everything else.

The image **build** is not affected by the proxy. It runs on the normal Docker
network, so e.g. `uv sync` against a private index works during the build.

### Start sequence

1. **Host:** `initialize.sh` (`initializeCommand`) checks that the slot
   `project/` holds a complete layer and that the host prerequisites exist, then
   builds `base/` as `ai-envelope-base:latest`.
2. **Host:** compose merges `docker-compose.yml` + `project/compose.yml` and
   builds `project/Dockerfile` (`FROM ai-envelope-base:latest`). The build context
   is the workspace root, filtered by `project/Dockerfile.dockerignore`.
3. **Container:** `check-exclusions` (`postStartCommand`).

---

## Files

| File | Purpose |
|---|---|
| `devcontainer.json` | Entry point for VS Code. Runs `initialize.sh`, loads both compose files, sets the user and extensions. |
| `docker-compose.yml` | **The generic config:** build, mounts, capabilities, networks, proxy env. |
| `initialize.sh` | Runs on the host before start: checks the slot and prerequisites, builds the base image. |
| `compose.sh` | `docker compose` with both compose files. Use it instead of bare `docker compose`. |
| `base/Dockerfile` | Generic image: Node, Claude Code, zsh, git, rg, fd, jq, python3, uv, `claude` user. |
| `base/check-exclusions.sh` | The check. Installed in the image as `/usr/local/bin/check-exclusions`. |
| `base/claude-wrapper.sh` | Installed as `claude`. Runs the check, then starts `claude.real`. |
| `base/.zshrc` | Shell config for the `claude` user. |
| `proxy/` | Squid egress proxy: `Dockerfile`, `squid.conf`, generic `allowlist.txt`. |
| `.claude/` | Claude settings (Stop hook for ntfy), mounted read-only at `/workspace/.claude`. |
| `project-template/` | Template for new project layers. |
| `project-ki-zfw-wm/` | Current project layer (temporary, will move out). |
| `project` | **Slot**, not tracked: symlink to (or copy of) the active project layer. |

A project layer contains `compose.yml`, `Dockerfile`, `Dockerfile.dockerignore`,
`excluded-files`, `allowlist.txt` and `dummies/`. See
[`project-template/README.md`](project-template/README.md).

---

## Prerequisites (host)

These must exist on the host before the first build. `initialize.sh` checks them:

| Path | Used for |
|---|---|
| `.devcontainer/project` | The project layer (symlink or copy). |
| `~/.claude/` | Claude Code config/state (mounted into the container). |
| `~/.claude.json` | Claude Code state file. **Must exist as a file.** If it's missing, Docker creates a *directory* with that name and Claude breaks. Run `echo '{}' > ~/.claude.json` if needed. |
| `~/.gitconfig` | Git identity (read-only). Same rule: must exist as a file. |

The project layer may need more (e.g. `~/.build-secrets/` for build
credentials). Its README lists them.

You also need Docker with Compose v2 (`docker compose version`) and BuildKit,
which is on by default.

---

## Usage

### Start / rebuild

- VS Code: **Dev Containers: Reopen in Container**. After changing anything in
  `.devcontainer/` or the project layer: **Dev Containers: Rebuild Container**.
- CLI (devcontainer CLI, `npm install -g @devcontainers/cli`). Run it on the host
  from the repo root, i.e. the folder that contains `.devcontainer/`:
  ```bash
  devcontainer up --workspace-folder .                              # build if needed + start devcontainer AND proxy
  devcontainer exec --workspace-folder . zsh                        # shell as user 'claude'
  devcontainer up --workspace-folder . --remove-existing-container  # after changing .devcontainer/ or layer files
  .devcontainer/compose.sh down                                     # stop both containers
  ```
  The proxy is part of the compose project and starts automatically. You never
  start it separately.
- Avoid plain `docker compose up` and `.devcontainer/compose.sh up`. They start the
  containers but skip `devcontainer.json`: no `initialize.sh` (the base image
  may be stale or missing), no `check-exclusions` at start, and `exec` puts you
  in as root unless you pass `-u claude`.
- Update Claude Code / the base image: `docker build --no-cache -t ai-envelope-base:latest .devcontainer/base`,
  then rebuild the container.
- After starting, the terminal should show one `OK` line per masked path, e.g.:
  ```
  [exclusions] Checking masked files...
    OK (dummy)   my-repo/config
    OK (empty)   my-repo/.env
  [exclusions] All checks passed.
  ```

### Switch to another project layer

```bash
.devcontainer/compose.sh down
ln -sfn ../other-repo/ai-envelope .devcontainer/project
devcontainer up --workspace-folder .
```

Run `down` **before** switching: `compose.sh` uses the layer's compose `name:` to
find the containers.

### Run Claude

```bash
claude            # runs the exclusion check first, then Claude Code
```

`claude.real` skips the check. Only use it for debugging, never for real work.

### Mask an additional secret file

In the project layer:

1. Add the path (relative to `/workspace`) to `excluded-files`.
2. Add a read-only volume in `compose.yml` → `services.devcontainer.volumes`:
   ```yaml
   - /dev/null:/workspace/my-repo/path/to/secret.env:ro                                   # blank it
   - ./project/dummies/my-repo/path/secret.yml:/workspace/my-repo/path/secret.yml:ro       # or a dummy
   ```
   For a dummy, create it under `dummies/` at the **same path** as the masked one,
   with **placeholder values only**.
3. Rebuild. `check-exclusions` must show `OK` for the new path.

Prefer masking **whole directories** over single files. With single files, new or
nested files in that directory aren't covered.

### Allow an additional domain

1. Generic (needed by every project): add it to `proxy/allowlist.txt`.
   Project-specific: add it to the layer's `allowlist.txt`.
   A leading dot includes subdomains: `.example.com`.
2. Restart the proxy, from the host, in the repo root (the lists are mounted,
   no rebuild needed):
   ```bash
   .devcontainer/compose.sh restart proxy
   ```

Keep the lists short. Every domain on them is a place the agent can send data to.

---

## Debugging

### Which container is which?

```bash
.devcontainer/compose.sh ps
#   <name>-devcontainer-1
#   <name>-proxy-1          (<name> = 'name:' in project/compose.yml)
```

### Start fails before anything is built

`initialize.sh` prints `[init] ERROR: ...`:
- `no project layer` / `broken symlink` → link a layer into the slot (see the
  [top-level README](../README.md#starting-a-new-project)). Symlink targets are
  relative to `.devcontainer/`.
- `project layer is missing '…'` → every layer needs all files of
  `project-template/`, even if they only hold comments.
- `… must exist as a file` → see [Prerequisites](#prerequisites-host).

### "Something can't reach the network"

1. Watch the proxy log while you retry:
   ```bash
   .devcontainer/compose.sh logs -f proxy
   ```
   `TCP_DENIED/403 CONNECT some.domain:443` → the domain isn't on the allowlist.
   Add it if it's legitimate (see above).
2. From inside the container:
   ```bash
   env | grep -i proxy                              # proxy vars set?
   curl -sI https://api.anthropic.com | head -1     # expect an HTTP status → allowed
   curl -sI https://example.com                     # expect 403 → blocked by squid
   curl -sI --noproxy '*' https://example.com       # expect failure → no direct route (good)
   ```
   If the last command *succeeds*, the network isolation isn't working. Check that
   the devcontainer is only on the `sandbox` network:
   `docker inspect <name>-devcontainer-1 --format '{{json .NetworkSettings.Networks}}'`
3. A tool ignores the proxy: most tools (curl, git, uv/pip, Claude Code) read
   `HTTPS_PROXY`. Tools that don't will simply fail, which is the intended result.
4. Plain `http://` URLs are blocked entirely. Only HTTPS (port 443) is allowed.

### Proxy container keeps restarting / exits

```bash
.devcontainer/compose.sh logs proxy
.devcontainer/compose.sh run --rm proxy squid -k parse -f /etc/squid/squid.conf
```
`squid -k parse` shows config errors. A typo in one of the allowlists (e.g. a
stray character) is the usual cause. If `project/allowlist.txt` is missing,
Docker creates a directory in its place and squid fails. Recreate it as a file.

### VS Code can't install its server or extensions

VS Code downloads its server and extensions **inside** the container, through the
proxy. If this fails, look for `TCP_DENIED` in the proxy log and add the domain
it's trying to reach to `proxy/allowlist.txt`.

### `check-exclusions` shows WARN / Claude won't start

```
WARN   my-repo/config  <-- not masked!
```
- The mount for that path is missing or wrong in `project/compose.yml`. Compare
  the volume's target with the path in `project/excluded-files`.
- Check what's actually mounted, from inside the container:
  ```bash
  grep /workspace /proc/self/mountinfo | awk '{print $5, $6}'
  ```
- The dummy must be at `project/dummies/<same path>`. For directories, the check
  compares the *entire* directory against the dummy (`diff -rq`).
- `/usr/local/bin/check-exclusions` is baked into the base image. After editing
  `base/check-exclusions.sh` you must **rebuild**. To try an edit without rebuilding:
  `bash /workspace/.devcontainer/base/check-exclusions.sh`.

### Build fails

- `pull access denied for ai-envelope-base` → the base image wasn't built. Start
  via VS Code / `devcontainer up` (runs `initialize.sh`), or run
  `bash .devcontainer/initialize.sh` once.
- `COPY … not found` → the file isn't allowlisted in
  `project/Dockerfile.dockerignore`. (The root `/.dockerignore` excludes everything
  on purpose. It only applies if the layer's file is missing.)
- `secret …: file not found` → a build secret declared in `project/compose.yml`
  is missing on the host.
- Start over completely:
  ```bash
  docker build --no-cache -t ai-envelope-base:latest .devcontainer/base
  .devcontainer/compose.sh build --no-cache
  ```

### Claude Code login / state problems

- `~/.claude.json` became a directory on the host → delete it, `echo '{}' > ~/.claude.json`, rebuild.
- Login fails → check the proxy log. Login and token refresh need `.anthropic.com`
  and `.claude.ai`.

### ntfy notification doesn't arrive

- `ntfy.sh` must be in `proxy/allowlist.txt`.
- Test inside the container: `curl -d test https://ntfy.sh/<your-topic>`.

---

## Security notes & known gaps

What this setup does **not** protect against (yet):

- **Host `~/.claude` is mounted writable.** The agent can change your *host* Claude
  config (e.g. add hooks that then run on the host) and read your OAuth token.
  Planned: mount a separate `~/.claude-sandbox` instead.
- **Project layers outside `.devcontainer/` are writable** unless the layer's
  `compose.yml` mounts them read-only (see the template). The agent could otherwise
  change masks or the Dockerfile, and the host would apply them on the next rebuild.
- **ntfy Stop hook** sends the start of Claude's last message to the public
  service `ntfy.sh` under a guessable topic. Planned: send only a fixed text, and
  use a random topic name.
- **Allowlisted domains are still exfiltration channels.** In particular
  `.anthropic.com` (by design) and `ntfy.sh`.
- **The workspace itself is writable.** The agent can change project code. Review
  changes (git diff) before you commit or push. Pushing is done from the host; the
  container has no git credentials.
- `check-exclusions` and the `claude` wrapper protect against **accidents**
  (a forgotten mount), not against a deliberately misbehaving agent (it could run
  `claude.real`). The actual protection is the mounts and the network.
