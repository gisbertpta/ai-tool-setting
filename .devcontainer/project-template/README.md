# Project layer template

Copy this folder to start a new project layer. Every file is required
(`initialize.sh` checks for them), but each one may contain nothing but
comments. Copied unchanged, the template gives you the plain generic sandbox:
no extra tools, no masks, no extra domains.

| File | Purpose |
|---|---|
| `compose.yml` | Merged on top of `.devcontainer/docker-compose.yml`: compose `name`, masking mounts, build secrets, env vars. |
| `Dockerfile` | `FROM` the generic base image; adds the project toolchain and dependencies. |
| `Dockerfile.dockerignore` | Allowlist of workspace files the `Dockerfile` may `COPY`. The build context is the whole workspace. |
| `excluded-files` | Paths that must be masked. `check-exclusions` checks them. |
| `allowlist.txt` | Extra proxy domains. |
| `dummies/` | Placeholder copies of masked paths, mirroring the path: `dummies/<repo>/<path>`. |

See "Starting a new project" in the envelope's [README](../../README.md).
