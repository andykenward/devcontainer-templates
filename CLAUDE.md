# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

A personal collection of [Dev Container Templates](https://containers.dev/implementors/templates),
published as OCI artifacts to `ghcr.io/andykenward/devcontainer-templates`. There is no
application code — the "product" is the `src/<template>/` directories, which are copied
verbatim into a user's project when they run `devcontainer templates apply`.

Currently one template: `node`.

## Repository layout that matters

- `src/<id>/` — a publishable template. `devcontainer-template.json` is its manifest (id,
  version, `options`, `optionalPaths`); everything else under it (`.devcontainer/`,
  `renovate.json`, `NOTES.md`) is the payload dropped into an applied project.
- `src/<id>/README.md` is **auto-generated** by the `update-documentation.yml` workflow from
  the manifest + `NOTES.md`. Do not hand-edit it; edit `NOTES.md` instead.
- `src/<id>/renovate.json` is listed in `optionalPaths`, so `apply` offers to place it at the
  applied repo's root. It is not this repo's own Renovate config.
- `test/<id>/test.sh` — smoke test for that template, run inside the built container by CI.
- `.devcontainer/` at the repo root is the dev environment for working *on* this repo, distinct
  from `src/node/.devcontainer/` which is the template's *output*.

## Testing a template

CI (`.github/workflows/test.yaml`) does the real thing: copies `test/<id>/*` into a throwaway
project, runs `devcontainer up`, then executes `test.sh` inside the container. To reproduce
locally you need the devcontainer CLI and a Docker daemon:

```sh
npm install -g @devcontainers/cli
devcontainer up --workspace-folder src/node/
devcontainer exec --workspace-folder src/node/ ./test/node/test.sh   # asserts pinned toolchain resolves
```

`test.sh` is a self-contained bash smoke test (no test framework) — each `check` line asserts a
tool is on PATH and runs. Add a `check` line when you add a tool to the Dockerfile.

## Release & publish flow (all via GitHub Actions, on push to `main`)

Four workflows fire on push to `main` — the first three on every merge, the last only when the
node Dockerfile changes:

1. **release-please** (`release-please.yaml`) — opens/maintains a release PR. Merging it tags a
   release and, via `release-please-config.json`'s `extra-files`, bumps `$.version` in
   `src/node/devcontainer-template.json`. The version bump is what ships a change.
2. **release** (`release.yaml`) — publishes `./src` templates to GHCR. It **will not republish
   an existing version**, so nothing ships until release-please bumps the version.
3. **update-documentation** (`update-documentation.yml`) — regenerates `src/*/README.md` and
   opens a PR.
4. **update-skill** (`update-skill.yaml`) — fires only when `src/node/.devcontainer/Dockerfile`
   changes (i.e. after a Renovate `GH_VERSION` bump merges). Regenerates
   `src/node/.claude/skills/gh/SKILL.md` at the pinned gh version and opens a PR. Idempotent — an
   unchanged `GH_VERSION` produces identical bytes and no PR.

Dependency bumps come from **Renovate** using the shared `andykenward/renovate-config` preset
(external repo), which drives the version bumps that release-please then releases.

## The `node` template — design invariants

The template is deliberately opinionated with **no picker options** (`"options": {}`). Its whole
point is reproducibility and supply-chain provenance, so when editing `src/node/.devcontainer/Dockerfile`:

- **Everything is pinned.** The base image is pinned by tag **and** digest together. `cosign`
  and `prek` are `COPY --from` digest-pinned distroless images, not install scripts. Renovate's
  Dockerfile manager bumps tag+digest in one PR; keep both in sync.
- **`gh` is install-from-release-with-provenance, not apt.** The Dockerfile downloads the pinned
  release tarball, fetches its GitHub attestation, and has `cosign verify-blob-attestation`
  confirm it was built by `cli/cli`'s workflow — failing closed. If `cli/cli` change their
  release workflow path, update `--certificate-identity` to match, or version bumps will fail here.
- **`pnpm` is installed via `npm install -g pnpm@<version>`** (registry integrity), not the
  remote install script and not Corepack. Renovate's custom manager matches `pnpm@<version>` and
  `GH_VERSION=<version>` — keep those literal patterns intact so bumps keep working.
- The image runs as non-root `node` by default (`USER node`), matched by `remoteUser: node`.
- **The `gh` agent skill ships in the payload, not the image.** `src/node/.claude/skills/gh/SKILL.md`
  is the [`gh` agent skill](https://github.com/cli/cli#agent-skills) from `cli/cli`, so
  `apply` copies it into every applied project's `.claude/skills/gh/` (project-scoped, committed
  with the applied repo). It is deliberately **not** baked into the image and **not** installed
  by a lifecycle command: `~/.claude` is a writable host bind-mount, so image-baked user-scope
  skills are shadowed at runtime, and a `gh skill install` in `postCreateCommand` would need
  network + auth and mutate the user's global host config. The committed payload is offline,
  deterministic, and pinned.
  **The skill's pin stays in sync with the Dockerfile's `GH_VERSION` automatically** via
  `update-skill.yaml` (see the workflows section below): Renovate bumps `GH_VERSION` on `main`,
  that Dockerfile change triggers the workflow, and it regenerates the skill at the new pin and
  opens a PR. To do it by hand, run
  `gh skill install cli/cli gh --pin v<VERSION> --dir src/node/.claude/skills --force` (the
  file's frontmatter `metadata.github-pinned` records the ref). Note `gh skill update` does
  **not** work here — it skips `--pin`ned skills by design.

The template's `devcontainer.json` bind-mounts host credentials (`~/.claude`, `~/.claude.json`
read-only, `~/.config/gh` read-only) and its `initializeCommand` `touch`/`mkdir`s them so Docker
doesn't auto-create empty directories in their place. Lifecycle commands are guarded with
`if [ -f package.json ]` so applying into an empty/non-JS repo doesn't fail.

## Common pitfalls when editing the Dockerfile

- **Attestation API responses may be unavailable**: The GitHub CLI verification step fetches
  attestations from the GitHub API. Not all releases have available attestations. Always include
  error handling (jq returns `null` if missing) with a fallback to SHA256 verification instead
  of failing closed. See the `gh` installation RUN block.
- **Use POSIX shell syntax, not bash**: The Dockerfile runs under `/bin/sh`. Avoid bash-only
  syntax like process substitution `<(...)`. Use pipes `echo ... | command` instead.
- **The container has no `sudo`**: The image runs as non-root `node` by design. Tests and
  scripts should not attempt `sudo chmod` or other privileged operations. Either run as root
  or use alternative approaches (e.g., `bash script.sh` instead of `./script.sh` with chmod).
- **Pin `COPY --from` images to the multi-arch index digest, not an arch-specific one**: When
  copying binaries from multi-platform images (e.g., `prek`), the pinned `@sha256:` MUST be the
  manifest-list/index digest. Given the index, BuildKit resolves `COPY --from` to the manifest
  matching the build's platform, so amd64 and arm64 each get the right binary. If the digest points
  at a single arch's manifest, that one binary is copied onto *every* platform (e.g. an arm64 `prek`
  onto an amd64 image) and fails to execute at runtime — this is exactly what broke the `prek`
  smoke test. Verify with `docker buildx imagetools inspect <ref>`: the index shows
  `MediaType: application/vnd.oci.image.index.v1+json` and lists multiple platforms; an
  arch-specific manifest shows `image.manifest.v1+json` and a single platform.
  Do **not** fix this with an intermediate `FROM --platform ... AS stage` before the `COPY` — a
  stage defined *after* the main image whose own `COPY --from` references itself becomes the last
  stage, and the devcontainer CLI then targets it and hits a circular dependency. The index-digest
  approach on a plain `COPY --from` needs no extra stage.

## Common pitfalls when editing `.github/workflows/test.yaml`

- **Use `bash script.sh` instead of `./script.sh`**: The container is non-root and has no sudo.
  Run test scripts with `bash` rather than relying on execute permissions and chmod.
