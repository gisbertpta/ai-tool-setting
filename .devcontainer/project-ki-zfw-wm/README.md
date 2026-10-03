# Project layer: ki-zfw-wm

Project layer for the `ki-zfw-wm-*` working repos (`ki-zfw-wm-code`,
`ki-zfw-wm-specs`, `ki-zfw-wm-umbrella`).

**Temporary location.** This layer is kept in the envelope repo only until it
moves into the project (planned: `ki-zfw-wm-umbrella`). After moving it, update
the slot symlink. `initialize.sh` then mounts the layer read-only by itself.

Activate it in a clone of the envelope:

```bash
ln -s project-ki-zfw-wm .devcontainer/project
```

| File | Content |
|---|---|
| `Dockerfile` | Build libs, Bitmarck CA, Python 3.11 + `uv sync` of `ki-zfw-wm-code`, tiktoken cache, pre-commit hooks |
| `Dockerfile.dockerignore` | Files of `ki-zfw-wm-code` the build may see |
| `compose.yml` | Compose name, build secrets (`~/.build-secrets/`), masking mounts |
| `excluded-files` | Masked paths: `configs/`, `build-secret/`, `backend/scripts/.env` |
| `allowlist.txt` | Extra proxy domains (none active) |
| `prereqs` | `ki-zfw-wm-code` must be cloned under that name; build secrets must exist |
| `dummies/` | Placeholder copies of the masked paths. **Placeholder values only.** |

Host prerequisites in addition to the generic ones (checked by `initialize.sh`
via `prereqs`): `~/.build-secrets/username` and `~/.build-secrets/password`
(Git/Artifactory credentials, used only during the build), and the clone
`ki-zfw-wm-code/` in the workspace root.
