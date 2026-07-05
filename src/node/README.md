
# Node — pinned toolchain, provenance-verified, with Claude Code (node)

A reproducible Node dev container: digest-pinned node base, pnpm, prek, and a GitHub CLI verified via SLSA build provenance (cosign), plus zsh and the Claude Code feature. Ships an optional renovate.json wired to a shared preset.

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
- **Claude Code**: installed via the Anthropic feature, with host credentials
  bind-mounted (`~/.claude`, `~/.claude.json`) and `gh` credentials shared
  read-only from `~/.config/gh`.
- **Optional `renovate.json`**: applying the template offers to drop a root
  `renovate.json` that extends the shared
  [`andykenward/renovate-config`](https://github.com/andykenward/renovate-config)
  preset, so the applied repo keeps its pins current.

## Host prerequisites

The template bind-mounts a few host paths, and `initializeCommand` creates them
if missing. On the host, authenticate once so the mounts carry real credentials:

```sh
gh auth login          # writes ~/.config/gh
# Claude Code: sign in once on the host so ~/.claude.json / ~/.claude exist
```

macOS/Linux hosts only (the `initializeCommand` uses `touch`/`mkdir`).

## Applying it

Pick it from **Dev Containers: Add Dev Container Configuration Files…**, or apply
directly with the CLI:

```sh
devcontainer templates apply -t ghcr.io/andykenward/devcontainer-templates/node
```


---

_Note: This file was auto-generated from the [devcontainer-template.json](https://github.com/andykenward/devcontainer-templates/blob/main/src/node/devcontainer-template.json).  Add additional notes to a `NOTES.md`._
