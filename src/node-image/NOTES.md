## Highlights

The same deliberately opinionated, fully pinned baseline as the
[`node`](https://github.com/andykenward/devcontainer-templates/tree/main/src/node)
template — but pulled as a prebuilt image instead of built on your machine. It
has **no picker options**.

- **Prebuilt and multi-arch**: `ghcr.io/andykenward/devcontainer-images/node:2`,
  built for `linux/amd64` and `linux/arm64`. First start is a pull, not a
  multi-minute build.
- **The config travels with the image.** It is built with `devcontainer build`,
  which bakes this repo's `devcontainer.json` into the image as a
  `devcontainer.metadata` label — so the VS Code extensions and settings,
  `postCreateCommand` / `updateContentCommand`, `containerEnv`, `remoteUser` and
  the persistent zsh-history volume all arrive automatically. That is why the
  `.devcontainer/devcontainer.json` you get is only a few lines.
- **Signed and attested**, with the same trust model the image uses internally to
  verify `gh` — see [Verifying the image](#verifying-the-image) below.
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
- **Claude Code**: installed with Anthropic's official native installer, pinned
  to a specific version. Sharing your host Claude Code / `gh` credentials into
  the container is **opt-in** — see [Sharing host credentials](#sharing-host-credentials-optional).
- **`gh` agent skill**: ships the [`gh` agent skill](https://github.com/cli/cli#agent-skills)
  from `cli/cli` as a project-scoped skill at `.claude/skills/gh/`, pinned to the
  same `gh` release as the CLI in the image. It is deliberately committed into
  your repo rather than baked into the image: `~/.claude` is often a writable
  bind mount, which would shadow an image-baked user-scope skill. Committed, it
  needs no network or credentials and the whole team picks it up on `git pull`.
- **Optional `renovate.json`**: applying the template offers to drop a root
  `renovate.json` that extends the shared
  [`andykenward/renovate-config`](https://github.com/andykenward/renovate-config)
  preset, so the applied repo keeps its pins current.

## Which template do I want?

Pick **`node`** if you intend to edit the Dockerfile — it puts the whole build in
your repo, so you can add packages and tools freely.

Pick **`node-image`** if you don't. It trades that away for a pull instead of a
build. You can still layer on top later by switching your `devcontainer.json` to
a `build.dockerfile` whose first line is
`FROM ghcr.io/andykenward/devcontainer-images/node:2`.

## Pinning

The shipped reference is the floating major tag `:1`, so you keep getting patch
and minor rebuilds. If you take the optional `renovate.json`, Renovate will pin
it to `:1@sha256:…` in *your* repo on its first run and keep that digest fresh —
which is where pinning belongs, since it records exactly what your project built
against.

## Verifying the image

Every published index carries SLSA build provenance, an SBOM per architecture,
and a keyless cosign signature:

```sh
gh attestation verify oci://ghcr.io/andykenward/devcontainer-images/node:2 \
  --repo andykenward/devcontainer-templates

cosign verify ghcr.io/andykenward/devcontainer-images/node:2 \
  --certificate-oidc-issuer=https://token.actions.githubusercontent.com \
  --certificate-identity-regexp='^https://github.com/andykenward/devcontainer-templates/\.github/workflows/release\.yaml@.*'
```

## Sharing host credentials (optional)

Out of the box the container mounts **no host paths**, so it starts cleanly on
any host and in any Dev Containers flow. If you'd like the container to reuse the
Claude Code and GitHub CLI credentials you're already signed into on the host:

1. **Authenticate on the host** so the source paths exist and carry real
   credentials (a bind mount requires its source to already exist):

   ```sh
   gh auth login          # writes ~/.config/gh
   # Claude Code: sign in once on the host so ~/.claude.json / ~/.claude exist
   ```

2. **Uncomment the three bind mounts** in `.devcontainer/devcontainer.json`
   (they sit under the "Host credential sharing" note) and rebuild the
   container. They mount `~/.claude` writable and `~/.claude.json` /
   `~/.config/gh` read-only.

3. **Keep the change local** (recommended in shared repos) so you don't commit a
   host-path dependency onto your teammates. There's no per-user override file
   for `devcontainer.json`, so tell git to ignore your local edit:

   ```sh
   git update-index --skip-worktree .devcontainer/devcontainer.json
   # undo later with: git update-index --no-skip-worktree .devcontainer/devcontainer.json
   ```

macOS/Linux hosts. This works best with the standard **Reopen in Container**
flow, where `${localEnv:HOME}` resolves to your real host home.

> [!IMPORTANT]
> **If you commit the uncommented mounts**, everyone who opens the repo in a
> container inherits the same host-path dependency. A teammate who hasn't signed
> in on their host will hit `bind source path does not exist` when the container
> starts. To resolve it, they can either authenticate on their host (step 1) and
> rebuild, or re-comment the three mounts locally. Prefer keeping them commented
> in shared repos and letting each person opt in on their own machine.

## Applying it

Pick it from **Dev Containers: Add Dev Container Configuration Files…**, or apply
directly with the CLI:

```sh
devcontainer templates apply -t ghcr.io/andykenward/devcontainer-templates/node-image
```
