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
  both per-project named volumes (Claude Code state, zsh history) all arrive
  automatically. That is why the `.devcontainer/devcontainer.json` you get is
  only a few lines.
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
  to a specific version. Its state survives rebuilds on a per-project named
  volume — see [Claude Code state](#claude-code-state-persists-across-rebuilds).
- **`gh` agent skill**: ships the [`gh` agent skill](https://github.com/cli/cli#agent-skills)
  from `cli/cli` as a project-scoped skill at `.claude/skills/gh/`, pinned to the
  same `gh` release as the CLI in the image. It is deliberately committed into
  your repo rather than baked into the image: `~/.claude` is a writable named
  volume, which would shadow an image-baked user-scope skill — and worse, serve a
  stale copy of it forever, since a volume seeds from the image only once.
  Committed, it needs no network or credentials and the whole team picks it up on
  `git pull`.
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

## Claude Code state persists across rebuilds

Sign in to Claude Code **inside** the container, once. A per-project named volume
mounted at `/home/node/.claude` keeps you signed in, along with your settings,
session transcripts and prompt history, so **Rebuild Container** no longer throws
them away. This is the approach Anthropic
[documents for dev containers](https://code.claude.com/docs/en/devcontainer#persist-authentication-and-settings-across-rebuilds).

The mount arrives from the image's metadata label, so it is not in the
`devcontainer.json` you were given. It is:

```jsonc
"source=claude-code-config-${devcontainerId},target=/home/node/.claude,type=volume"
```

`${devcontainerId}` is resolved by your Dev Containers CLI, not baked into the
image, so it is unique to *your* workspace — two projects never share one volume,
even if their folders happen to have the same name.

Two things worth knowing:

- **Nothing inside the container clears it.** To reset, remove the volume from
  the host:

  ```sh
  docker volume ls | grep claude-code-config
  docker volume rm claude-code-config-<id>
  ```

- **Moving or re-cloning the repo to a different path changes the id**, so the
  old volume is orphaned and you'll be asked to sign in again. Your old sessions
  aren't gone — they're in the previous volume, which you can rename back if you
  need them.

> [!IMPORTANT]
> The volume holds an OAuth token and full session transcripts, unencrypted, and
> it outlives the container. Anything a session read — a `.env` file, a printed
> secret — is in there. Treat it like any other credential store on your machine,
> and prefer this template only with repositories you trust.

## Sharing host credentials (optional)

Out of the box the container mounts **no host paths**, so it starts cleanly on
any host and in any Dev Containers flow. If you'd like the container to reuse the
GitHub CLI login you already have on the host:

1. **Authenticate on the host** so the source path exists and carries real
   credentials (a bind mount requires its source to already exist):

   ```sh
   gh auth login          # writes ~/.config/gh
   ```

2. **Uncomment the bind mount** in `.devcontainer/devcontainer.json` (it sits
   under the "Optional host-credential mount" note) and rebuild the container. It
   mounts `~/.config/gh` read-only, so container processes can't tamper with your
   host auth.

3. **Keep the change local** (recommended in shared repos) so you don't commit a
   host-path dependency onto your teammates. There's no per-user override file
   for `devcontainer.json`, so tell git to ignore your local edit:

   ```sh
   git update-index --skip-worktree .devcontainer/devcontainer.json
   # undo later with: git update-index --no-skip-worktree .devcontainer/devcontainer.json
   ```

macOS/Linux hosts. This works best with the standard **Reopen in Container**
flow, where `${localEnv:HOME}` resolves to your real host home.

Claude Code needs no equivalent — it signs in inside the container and the volume
above keeps it signed in.

> [!IMPORTANT]
> **If you commit the uncommented mount**, everyone who opens the repo in a
> container inherits the same host-path dependency. A teammate who hasn't run
> `gh auth login` will hit `bind source path does not exist` when the container
> starts. To resolve it, they can either authenticate on their host (step 1) and
> rebuild, or re-comment the mount locally. Prefer keeping it commented in shared
> repos and letting each person opt in on their own machine.

## Applying it

Pick it from **Dev Containers: Add Dev Container Configuration Files…**, or apply
directly with the CLI:

```sh
devcontainer templates apply -t ghcr.io/andykenward/devcontainer-templates/node-image
```
