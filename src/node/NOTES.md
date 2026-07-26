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
- **zsh**: hand-rolled config (history on a per-project named volume,
  autosuggestions, `vcs_info` prompt) — no oh-my-zsh.
- **Claude Code**: installed with Anthropic's official native installer, pinned
  to a specific version (no npm dependency, no unpinned `curl | bash`). Its state
  survives rebuilds on a per-project named volume — see
  [Claude Code state](#claude-code-state-persists-across-rebuilds) below.
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

## Claude Code state persists across rebuilds

Sign in to Claude Code **inside** the container, once. A per-project named volume
mounted at `/home/node/.claude` keeps you signed in, along with your settings,
session transcripts and prompt history, so **Rebuild Container** no longer throws
them away. This is the approach Anthropic
[documents for dev containers](https://code.claude.com/docs/en/devcontainer#persist-authentication-and-settings-across-rebuilds).

```jsonc
"source=claude-code-config-${devcontainerId},target=/home/node/.claude,type=volume"
```

Your zsh history persists the same way, on a second volume:

```jsonc
"source=zsh-history-${devcontainerId},target=/home/node/.commandhistory,type=volume"
```

`${devcontainerId}` is unique to this workspace, so two projects never share
either volume — even if their folders happen to have the same name. That matters
for both: one holds an auth token and your transcripts, and shell history
routinely picks up tokens pasted into `curl` or `gh` commands.

They are kept separate on purpose, so you can wipe your Claude Code state without
losing your shell history, or the reverse.

Two things worth knowing:

- **Nothing inside the container clears them.** To reset, remove the volume from
  the host — `${devcontainerId}` resolves to an opaque hash, so list them first:

  ```sh
  docker volume ls | grep -E 'claude-code-config|zsh-history'
  docker volume rm claude-code-config-<id>    # sign-in, settings, transcripts
  docker volume rm zsh-history-<id>           # shell history only
  ```

- **Moving or re-cloning the repo to a different path changes the id**, so the
  old volumes are orphaned and you'll be asked to sign in again. Your old sessions
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
devcontainer templates apply -t ghcr.io/andykenward/devcontainer-templates/node
```
