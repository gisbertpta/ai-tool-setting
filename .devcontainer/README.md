# Claude Code Sandbox (devcontainer)

A devcontainer for running Claude Code on `ki-zfw-wm-code` with permission prompts
skipped, in a way that limits what the agent can **see** (secrets are masked) and
where it can **send** things (egress is allowlisted).

> Edit everything in this folder **from the host**. Inside the container,
> `.devcontainer/` is mounted read-only on purpose.

---

## How it works

```
 host (WSL)                                     docker
 ─────────────                                  ──────────────────────────────────────────────
 /workspace  ─────── bind mount ──────────►   ┌─ devcontainer ───────────────┐
 .devcontainer/ ──── bind mount (ro) ─────►   │ user: claude (uid 1000)      │
 dummy configs ───── bind mount (ro) ─────►   │ cap_drop ALL                 │
                                              │ no-new-privileges            │
                                              │ HTTPS_PROXY=http://proxy:3128│
                                              └──────────────┬───────────────┘
                                                 network "sandbox" (internal, no gateway)
                                              ┌──────────────┴───────────────┐
                                              │ proxy (squid)                │
                                              │ allows: proxy/allowlist.txt  │
                                              └──────────────┬───────────────┘
                                                 network "egress"
                                                          ▼
                                                      internet
```

There are three layers of protection:

1. **Secret masking.** Real secrets in the workspace are covered by read-only bind
   mounts: either placeholder "dummy" files or `/dev/null`. The agent sees the dummy,
   not the real file.
2. **Exclusion check.** `check-exclusions` checks that every path in
   `excluded-files` is really masked. It runs when the container starts, and the
   `claude` command runs it too: `claude` refuses to start if anything is unmasked.
3. **Egress allowlist.** The devcontainer has no direct route to the internet.
   Its only way out is the `proxy` container, which allows HTTPS to the domains in
   `proxy/allowlist.txt` and blocks everything else.

The image **build** is not affected by the proxy. It runs on the normal Docker
network, so `uv sync` against Artifactory works during the build.

---

## Files

| File | Purpose |
|---|---|
| `devcontainer.json` | Entry point for VS Code. Only points at the compose file and sets the user and extensions. |
| `docker-compose.yml` | **The real config:** build, mounts, capabilities, networks, proxy env. |
| `Dockerfile` | Sandbox image: Node, Claude Code, Python 3.11 via uv, project deps, pre-commit hooks, Bitmarck CA. |
| `proxy/` | Squid egress proxy: `Dockerfile`, `squid.conf`, `allowlist.txt`. |
| `excluded-files` | Paths (relative to `/workspace`) that must be masked in the container. |
| `check-exclusions.sh` | The check. Installed in the image as `/usr/local/bin/check-exclusions`. |
| `claude-wrapper.sh` | Installed as `claude`. Runs the check, then starts `claude.real`. |
| `dummy-ki-zfw-wm-code/dummy.configs/` | Placeholder copy of `ki-zfw-wm-code/configs/`. **Placeholder values only.** |
| `dummy.build-secret/` | Placeholder for `ki-zfw-wm-code/build-secret/`. |
| `.claude/` | Project Claude settings (Stop hook for ntfy), mounted read-only at `/workspace/.claude`. |
| `.zshrc` | Shell config for the `claude` user. |
| `___new__Dockerfile` | Unfinished draft (native installer instead of npm). **Not used.** |

---

## Prerequisites (host)

These must exist on the host before the first build:

| Path | Used for |
|---|---|
| `~/.build-secrets/username`, `~/.build-secrets/password` | Git/Artifactory credentials for the image build (BuildKit secrets, not stored in the image). |
| `~/.claude/` | Claude Code config/state (mounted into the container). |
| `~/.claude.json` | Claude Code state file. **Must exist as a file.** If it's missing, Docker creates a *directory* with that name and Claude breaks. Run `echo '{}' > ~/.claude.json` if needed. |
| `~/.gitconfig` | Git identity (read-only). Same rule: must exist as a file. |

You also need Docker with Compose v2 (`docker compose version`) and BuildKit, which is on by default.

---

## Usage

### Start / rebuild

- VS Code: **Dev Containers: Reopen in Container**. After changing anything in
  `.devcontainer/`: **Dev Containers: Rebuild Container**.
- CLI (devcontainer CLI, `npm install -g @devcontainers/cli`). Run it on the host
  from the repo root, i.e. the folder that contains `.devcontainer/`:
  ```bash
  devcontainer up --workspace-folder .                              # build if needed + start devcontainer AND proxy
  devcontainer exec --workspace-folder . zsh                        # shell as user 'claude'
  devcontainer up --workspace-folder . --remove-existing-container  # after changing .devcontainer/ files
  docker compose -f .devcontainer/docker-compose.yml down           # stop both containers
  ```
  The proxy is part of the compose project and starts automatically. You never
  start it separately.
- Avoid plain `docker compose up`. It starts the containers but ignores
  `devcontainer.json`: no `check-exclusions` at start, and `exec` puts you in
  as root unless you pass `-u claude`.
- First start after switching from the old single-container setup: remove the old
  container once (`docker ps -a`, then `docker rm -f <old vsc-… container>`).
  `docker compose -f .devcontainer/docker-compose.yml ps` should then list
  `claude-sandbox-devcontainer-1` and `claude-sandbox-proxy-1`.
- After starting, the terminal should show:
  ```
  [exclusions] Checking masked files...
    OK (dummy)   ki-zfw-wm-code/configs
    OK (dummy)   ki-zfw-wm-code/build-secret
    OK (empty)   ki-zfw-wm-code/backend/scripts/.env
  [exclusions] All checks passed.
  ```

### Run Claude

```bash
claude            # runs the exclusion check first, then Claude Code
```

`claude.real` skips the check. Only use it for debugging, never for real work.

### Mask an additional secret file

1. Add the path (relative to `/workspace`) to `excluded-files`.
2. Add a read-only volume in `docker-compose.yml` → `services.devcontainer.volumes`:
   ```yaml
   - /dev/null:/workspace/ki-zfw-wm-code/path/to/secret.env:ro                        # blank it
   - ./dummy-ki-zfw-wm-code/dummy.secret.yml:/workspace/ki-zfw-wm-code/path/secret.yml:ro  # or a dummy
   ```
   For a dummy, create it with **placeholder values only**. The check looks for
   `dummy-<top-dir>/dummy.<basename>` first, then `dummy.<basename>`.
3. Rebuild. `check-exclusions` must show `OK` for the new path.

Prefer masking **whole directories** over single files. With single files, new or
nested files in that directory aren't covered.

### Allow an additional domain

1. Add it to `proxy/allowlist.txt`. A leading dot includes subdomains:
   `.example.com`.
2. Rebuild just the proxy, from the host, in the repo root:
   ```bash
   docker compose -f .devcontainer/docker-compose.yml up -d --build proxy
   ```

Keep the list short. Every domain on it is a place the agent can send data to.
Internal systems (S3, Azure DI, Kafka, Netezza, …) are **not** allowed on purpose.
Tests against external resources are not run in this container.

---

## Debugging

### Which container is which?

```bash
docker compose -f .devcontainer/docker-compose.yml ps
#   claude-sandbox-devcontainer-1
#   claude-sandbox-proxy-1
```

### "Something can't reach the network"

1. Watch the proxy log while you retry:
   ```bash
   docker logs -f claude-sandbox-proxy-1
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
   `docker inspect claude-sandbox-devcontainer-1 --format '{{json .NetworkSettings.Networks}}'`
3. A tool ignores the proxy: most tools (curl, git, uv/pip, Claude Code) read
   `HTTPS_PROXY`. Tools that don't will simply fail, which is the intended result.
4. Plain `http://` URLs are blocked entirely. Only HTTPS (port 443) is allowed.

### Proxy container keeps restarting / exits

```bash
docker logs claude-sandbox-proxy-1
docker compose -f .devcontainer/docker-compose.yml run --rm proxy squid -k parse -f /etc/squid/squid.conf
```
`squid -k parse` shows config errors. A typo in `allowlist.txt` (e.g. a stray
character) is the usual cause.

### VS Code can't install its server or extensions

VS Code downloads its server and extensions **inside** the container, through the
proxy. If this fails, look for `TCP_DENIED` in the proxy log and add the domain
it's trying to reach to `allowlist.txt`.

### `check-exclusions` shows WARN / Claude won't start

```
WARN   ki-zfw-wm-code/configs  <-- not masked!
```
- The mount for that path is missing or wrong in `docker-compose.yml`. Compare
  the volume's target with the path in `excluded-files`.
- Check what's actually mounted, from inside the container:
  ```bash
  grep /workspace /proc/self/mountinfo | awk '{print $5, $6}'
  ```
- The dummy on the host changed but the mounted copy didn't match: for directories,
  the check compares the *entire* directory against the dummy (`diff -rq`).
- `/usr/local/bin/check-exclusions` is baked into the image. After editing
  `check-exclusions.sh` you must **rebuild**. To try an edit without rebuilding:
  `bash /workspace/.devcontainer/check-exclusions.sh`.

### Build fails

- `secret git-username: file not found` → `~/.build-secrets/username` / `password`
  missing on the host.
- `uv sync` authentication errors → wrong credentials in `~/.build-secrets/`.
- TLS / certificate errors → `ki-zfw-wm-code/bitmarck-ca-chain.crt` missing or
  outdated.
- `COPY … not found` → the file isn't allowlisted in the root `/.dockerignore`
  (the build context is the repo root, and `.dockerignore` excludes everything by default).
- Start over completely:
  ```bash
  docker compose -f .devcontainer/docker-compose.yml build --no-cache
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
