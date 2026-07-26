# devcontainer-templates

A personal collection of [Dev Container Templates](https://containers.dev/implementors/templates),
published as OCI artifacts to GHCR and discoverable in the "Add Dev Container
Configuration Files" picker.

Currently one template:

| Template | Reference | What it is |
| --- | --- | --- |
| `node` | `ghcr.io/andykenward/devcontainer-templates/node` | Reproducible Node dev container: digest-pinned `node` base, pnpm, prek, provenance-verified `gh`, zsh, Claude Code |

## The `node` template

A deliberately opinionated, fully pinned baseline — digest-pinned `node` base,
pnpm, provenance-verified `gh` (cosign + SLSA build provenance), prek, cosign,
zsh, and the Claude Code feature, with **no picker options**.

Apply it directly with the CLI:

```sh
devcontainer templates apply -t ghcr.io/andykenward/devcontainer-templates/node
```

Full highlights, host prerequisites, and apply instructions live with the
template in [`src/node/NOTES.md`](src/node/NOTES.md), which is embedded into the
template's auto-generated `README.md`.

## The prebuilt image

The same toolchain is also published as a multi-arch (amd64 + arm64) container
image, so you can skip the local build entirely:

```
ghcr.io/andykenward/devcontainer-images/node:1
```

It is built by CI from `src/node/.devcontainer/` — the *same* Dockerfile the
template ships, never a copy — using `devcontainer build`, which bakes the
template's `devcontainer.json` into the image as a `devcontainer.metadata`
label. Extensions, settings, lifecycle commands, `containerEnv`, `remoteUser`
and the zsh-history volume therefore come along with the image; a consuming
`devcontainer.json` only needs the `image` line.

Tags: `X.Y.Z`, `X.Y`, `X`, `latest` on release; `edge` and `sha-<12>` on every
push to `main`.

The image is signed and attested the same way it verifies `gh`:

```sh
gh attestation verify oci://ghcr.io/andykenward/devcontainer-images/node:1 \
  --repo andykenward/devcontainer-templates

cosign verify ghcr.io/andykenward/devcontainer-images/node:1 \
  --certificate-oidc-issuer=https://token.actions.githubusercontent.com \
  --certificate-identity-regexp='^https://github.com/andykenward/devcontainer-templates/\.github/workflows/release\.yaml@.*'
```

**Which do I want?** Use the `node` template if you intend to edit the
Dockerfile — you get the whole build in your repo. Use the image if you don't:
it trades a multi-minute first build for a pull.

## Dependency updates

Version bumps are handled by [Renovate](https://github.com/andykenward/renovate-config)
using the shared preset in the `andykenward/renovate-config` repo:

- **Native, no config**: base image `FROM` (tag + digest), the `COPY --from`
  images (prek, cosign), and the `claude-code` Feature.
- **Custom managers (in the preset)**: `pnpm@<version>` and `GH_VERSION=<version>`
  inside the Dockerfile.

- **Custom managers (in this repo's `renovate.json`)**: the devcontainer CLI,
  syft, and cosign pins inside the workflows.

When Renovate's conventional-commit PRs land, **release-please** bumps this
collection's own `version` in `src/node/devcontainer-template.json` and cuts a
release; the publish workflow then republishes to GHCR (it won't republish an
existing version, so the bump is what ships changes) and pushes the matching
semver image tags.

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
5. **Make the image package public**: after the first merge that runs the image
   job, open
   `https://github.com/users/andykenward/packages/container/devcontainer-images%2Fnode/settings`
   and set visibility to *public*. New GHCR packages are private by default, and
   a private image is unusable by anyone — including you, on a fresh host.
   Confirm the package's "Repository" link resolves to this repo; that comes
   from the `org.opencontainers.image.source` label added at build time. Leave
   `devcontainer-images/node-buildcache` **private**.
6. **Register for the picker**: open a PR against
   [`devcontainers/devcontainers.github.io`](https://github.com/devcontainers/devcontainers.github.io)
   adding this collection to `_data/collection-index.yml`:

   ```yaml
   - name: Andy Kenward's Dev Container Templates
     maintainer: Andy Kenward
     contact: https://github.com/andykenward/devcontainer-templates/issues
     repository: https://github.com/andykenward/devcontainer-templates
     ociReference: ghcr.io/andykenward/devcontainer-templates
   ```

7. **Install Renovate** (the GitHub App or self-hosted) on both repos.

## Layout

```
.
├── .github/workflows/
│   ├── release-please.yaml       # open release PRs, tag + cut GitHub releases
│   ├── release.yaml              # build+push the image, then publish templates
│   ├── test.yaml                 # PR smoke test (build + toolchain checks)
│   ├── update-documentation.yml  # regenerate src/*/README.md, open a PR
│   ├── update-skill.yaml         # resync the gh agent skill to GH_VERSION
│   └── zizmor.yml                # workflow static analysis
├── src/node/
│   ├── devcontainer-template.json
│   ├── NOTES.md         # template docs; embedded into the generated README.md
│   ├── README.md        # auto-generated by update-documentation.yml
│   ├── renovate.json    # optionalPath → lands at the applied repo's root
│   ├── .claude/skills/gh/SKILL.md   # gh agent skill, pinned to GH_VERSION
│   └── .devcontainer/   # also the build context for the prebuilt image
│       ├── devcontainer.json
│       ├── Dockerfile
│       └── zshrc
├── test/node/test.sh
├── release-please-config.json
└── .release-please-manifest.json
```
