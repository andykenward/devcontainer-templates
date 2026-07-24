## Highlights

A deliberately opinionated, fully pinned baseline rather than a configurable
menu — it has **no picker options**.

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
  to a specific version (no npm dependency, no unpinned `curl | bash`). Sharing
  your host Claude Code / `gh` credentials into the container is **opt-in** — see
  [Sharing host credentials](#sharing-host-credentials-optional) below.
- **`gh` agent skill**: ships the [`gh` agent skill](https://github.com/cli/cli#agent-skills)
  from `cli/cli` as a project-scoped skill at `.claude/skills/gh/`, pinned to the
  same `gh` release as the CLI. It teaches agents (Claude Code and any other
  agent that reads `.claude/skills`) to drive `gh` well — structured `--json`
  output, pagination, search vs list, `gh api` fallback. Because it is committed
  into the applied repo it needs no network or credentials to be present, and the
  whole team picks it up on `git pull`. Refresh it with `gh skill update gh`.
- **Optional `renovate.json`**: applying the template offers to drop a root
  `renovate.json` that extends the shared
  [`andykenward/renovate-config`](https://github.com/andykenward/renovate-config)
  preset, so the applied repo keeps its pins current.

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
   (they sit under the "Optional host-credential mounts" note) and rebuild the
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
devcontainer templates apply -t ghcr.io/andykenward/devcontainer-templates/node
```
