
# Node — pinned toolchain, provenance-verified, with Claude Code (node)

A reproducible Node dev container: digest-pinned node base, pnpm, prek, and a GitHub CLI verified via SLSA build provenance (cosign), plus zsh and the Claude Code CLI. Ships an optional renovate.json wired to a shared preset.

## Options

| Options Id | Description | Type | Default Value |
|-----|-----|-----|-----|


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
  to a specific version (no npm dependency, no unpinned `curl | bash`), with host
  credentials bind-mounted (`~/.claude`, `~/.claude.json`) and `gh` credentials
  shared read-only from `~/.config/gh`.
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

## Host prerequisites

The template bind-mounts a few host paths (some read-only, some writable), and
`initializeCommand` pre-creates them so the container can start — a modern Docker
daemon refuses to start when any bind source is missing, so this is required, not
optional. On the
host, authenticate once so the mounts carry real credentials instead of the empty
`{}` stub `initializeCommand` seeds into `~/.claude.json`:

```sh
gh auth login          # writes ~/.config/gh
# Claude Code: sign in once on the host so ~/.claude.json / ~/.claude exist
```

macOS/Linux hosts only (the `initializeCommand` uses `mkdir` and a POSIX shell).

> [!NOTE]
> **Clone Repository in Container Volume**: with this flow the VS Code server
> often runs as `root`, so `${localEnv:HOME}` is `/root` and the mount sources
> resolve to `/root/.claude.json`, `/root/.claude`, `/root/.config/gh`. If the
> container fails to start with `bind source path does not exist`, create them on
> that host and reopen:
>
> ```sh
> mkdir -p /root/.claude /root/.config/gh
> printf '{}' > /root/.claude.json
> ```

## Applying it

Pick it from **Dev Containers: Add Dev Container Configuration Files…**, or apply
directly with the CLI:

```sh
devcontainer templates apply -t ghcr.io/andykenward/devcontainer-templates/node
```


---

_Note: This file was auto-generated from the [devcontainer-template.json](https://github.com/andykenward/devcontainer-templates/blob/main/src/node/devcontainer-template.json).  Add additional notes to a `NOTES.md`._
