# devcontainer-templates

A personal collection of [Dev Container Templates](https://containers.dev/implementors/templates),
published as OCI artifacts to GHCR and discoverable in the "Add Dev Container
Configuration Files" picker.

Currently one template:

| Template | Reference | What it is |
| --- | --- | --- |
| `node` | `ghcr.io/andykenward/devcontainer-templates/node` | Reproducible Node dev container: digest-pinned `node` base, pnpm, prek, provenance-verified `gh`, zsh, Claude Code |

## The `node` template

A deliberately opinionated, fully pinned baseline rather than a configurable
menu — it has **no picker options**. Highlights:

- **Base**: `node:24.18.0-bookworm-slim`, pinned by digest. Non-root `node` user.
- **pnpm**: installed globally via npm (registry integrity hashes), not the
  remote install script and not Corepack.
- **GitHub CLI**: not from apt. The pinned, immutable release archive is
  downloaded and verified with **cosign** against GitHub's SLSA build-provenance
  attestation before install — proving the bytes were built by `cli/cli`'s own
  release workflow. See [Verification of binaries](https://github.com/cli/cli#verification-of-binaries).
- **prek** and **cosign**: copied as digest-pinned binaries from their official
  distroless images (no install script runs).
- **zsh**: hand-rolled config (history on a named volume, autosuggestions,
  `vcs_info` prompt) — no oh-my-zsh.
- **Claude Code**: installed via the Anthropic feature, with host credentials
  bind-mounted (`~/.claude`, `~/.claude.json`) and `gh` credentials shared
  read-only from `~/.config/gh`.
- **Optional `renovate.json`**: the picker offers to drop a root `renovate.json`
  that extends the shared preset (see below), so the applied repo keeps its
  pins current.

### Host prerequisites

The template bind-mounts a few host paths, and `initializeCommand` creates them
if missing. On the host, authenticate once so the mounts carry real credentials:

```sh
gh auth login          # writes ~/.config/gh
# Claude Code: sign in once on the host so ~/.claude.json / ~/.claude exist
```

macOS/Linux hosts only (the `initializeCommand` uses `touch`/`mkdir`).

### Applying it

Once published and registered (below), pick it from **Dev Containers: Add Dev
Container Configuration Files…**. Or apply directly with the CLI:

```sh
devcontainer templates apply -t ghcr.io/andykenward/devcontainer-templates/node
```

## Dependency updates

Version bumps are handled by [Renovate](https://github.com/andykenward/renovate-config)
using the shared preset in the `andykenward/renovate-config` repo:

- **Native, no config**: base image `FROM` (tag + digest), the `COPY --from`
  images (prek, cosign), and the `claude-code` Feature.
- **Custom managers (in the preset)**: `pnpm@<version>` and `GH_VERSION=<version>`
  inside the Dockerfile.

When Renovate's conventional-commit PRs land, **release-please** bumps this
collection's own `version` in `src/node/devcontainer-template.json` and cuts a
release; the publish workflow then republishes to GHCR (it won't republish an
existing version, so the bump is what ships changes).

## One-time setup runbook

1. **Create the repos**: this one (`andykenward/devcontainer-templates`) and the
   preset repo (`andykenward/renovate-config`, contents in the sibling folder).
2. **Enable release-please PRs**: Settings → Actions → General → Workflow
   permissions → check *Allow GitHub Actions to create and approve pull
   requests*.
3. **First publish**: merge to `main`; let release-please open its release PR,
   merge it, and the publish job runs.
4. **Make packages public**: in GHCR, set the `node` template package (and the
   collection metadata package) visibility to *public* —
   `https://github.com/users/andykenward/packages/container/devcontainer-templates%2Fnode/settings`.
5. **Register for the picker**: open a PR against
   [`devcontainers/devcontainers.github.io`](https://github.com/devcontainers/devcontainers.github.io)
   adding this collection to `_data/collection-index.yml`:

   ```yaml
   - name: Andy Kenward's Dev Container Templates
     maintainer: Andy Kenward
     contact: https://github.com/andykenward/devcontainer-templates/issues
     repository: https://github.com/andykenward/devcontainer-templates
     ociReference: ghcr.io/andykenward/devcontainer-templates
   ```

6. **Install Renovate** (the GitHub App or self-hosted) on both repos.

## Layout

```
.
├── .github/workflows/
│   ├── release.yaml     # release-please + publish to GHCR
│   └── test.yaml        # PR smoke test (build + toolchain checks)
├── src/node/
│   ├── devcontainer-template.json
│   ├── renovate.json    # optionalPath → lands at the applied repo's root
│   └── .devcontainer/
│       ├── devcontainer.json
│       ├── Dockerfile
│       └── zshrc
├── test/node/test.sh
├── release-please-config.json
└── .release-please-manifest.json
```
