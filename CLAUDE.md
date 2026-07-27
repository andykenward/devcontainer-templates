# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

A personal collection of [Dev Container Templates](https://containers.dev/implementors/templates),
published as OCI artifacts to `ghcr.io/andykenward/devcontainer-templates`. There is no
application code — the "product" is the `src/<template>/` directories, which are copied
verbatim into a user's project when they run `devcontainer templates apply`.

Two templates, `node` and `node-image`, plus a prebuilt image published from the
`node` template's build context to `ghcr.io/andykenward/devcontainer-images/node`.

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
   `extra-files` also carries the **floating-major image tag** — see "Bumping the image's major
   tag" below.
2. **release** (`release.yaml`) — builds and publishes the prebuilt image, **then** publishes
   `./src` templates to GHCR. Four jobs: `plan` (resolve version + decide whether this push is
   the release-PR merge) → `build` (matrix: amd64 on `ubuntu-latest`, arm64 on
   `ubuntu-24.04-arm`) → `merge` (manifest list, attestations, cosign signature) →
   `publish-templates`. The template publish **will not republish an existing version**, so
   nothing ships until release-please bumps the version. See "The prebuilt image" below.
3. **update-documentation** (`update-documentation.yml`) — regenerates `src/*/README.md` and
   opens a PR.
4. **update-skill** (`update-skill.yaml`) — fires only when `src/node/.devcontainer/Dockerfile`
   changes (i.e. after a Renovate `GH_VERSION` bump merges). Regenerates
   `src/node/.claude/skills/gh/SKILL.md` at the pinned gh version and opens a PR. Idempotent — an
   unchanged `GH_VERSION` produces identical bytes and no PR.

Dependency bumps come from **Renovate** using the shared `andykenward/renovate-config` preset
(external repo), which drives the version bumps that release-please then releases.

### Bumping the image's major tag

`node-image` ships `ghcr.io/andykenward/devcontainer-images/node:<major>`, and that major must
track this repo's own major version. It is **not** maintained by hand — release-please rewrites
every occurrence via `extra-files`. A path listed as a bare string (not a `{type, path, jsonpath}`
object) gets release-please's **Generic** updater, which acts only on lines carrying an
annotation:

- `x-release-please-major` on the line → replace the first integer on **that line**.
- `x-release-please-start-major` … `x-release-please-end` → same replacement on **every line
  between the markers**.

Annotated today: `src/node-image/.devcontainer/devcontainer.json` (a trailing JSONC comment),
plus `src/node-image/NOTES.md`, its generated `README.md`, and the root `README.md` (HTML
comments, invisible when rendered). Both README copies are listed so the release PR is
self-consistent; `NOTES.md` is still the source the generator reads.

Three things to know before touching this:

- **The replacement regex is `/\d+\b/` — the first digit run on the line, whatever it is.** So a
  block must not span a line containing any other number. Wrapping the "Prebuilt and multi-arch"
  bullet in a block would rewrite `linux/amd64` to `linux/amd3`. Where a line has a stray digit,
  use the inline form; where the tag sits inside a fenced code block (no comment syntax available
  without it showing in rendered output), put the block markers *outside* the fence and check
  every line in between for digits first.
- **Only the major is annotated, so non-major releases are no-ops** — a `3.0.1` release rewrites
  `3` with `3`. Re-running is safe and produces no diff.
- **Nothing breaks at the boundary.** On a major release the same commit bumps the template
  version and the tag, and `publish-templates` `needs: [merge]`, so the new `:N` image tag is in
  the registry before a template referencing it ships.

### Workflow naming convention

`name: "(Group) Sentence case"`, where Group is one of **Release / Test / Update / Claude**.
GitHub sorts the Actions sidebar by name, so the prefix is what groups them.

**The group describes purpose, never trigger.** Trigger-based names go stale the moment a
trigger changes — `"PR - Test Updated Templates"` became wrong when `release.yaml` also
started running on PRs, and `"(Release) Publish ..."` became wrong when it stopped always
publishing. Don't reintroduce `PR -`, `Push -`, or a verb that only holds for one trigger.

Only the `name:` is conformed. **Filenames are deliberately left alone** (including the
`.yml`/`.yaml` split): renaming a workflow file orphans its run history, and `release.yaml`
self-references its own path in `pull_request.paths`, so a rename there would silently stop it
triggering on its own changes.

## The prebuilt image — design invariants

`release.yaml` publishes `ghcr.io/andykenward/devcontainer-images/node` (multi-arch, amd64 +
arm64). Constraints that are load-bearing, each verified against `@devcontainers/cli@0.88.0`:

- **There is exactly one Dockerfile and there must never be a second.** The image is built from
  `src/node/.devcontainer/` — the same bytes the template ships. Do not add an `images/`
  directory or copy the Dockerfile.
- **`devcontainer build` (not `docker buildx build`) is what bakes `devcontainer.metadata`.**
  That label is the entire reason the `node-image` template can be a two-line file. It is baked
  even with zero Features — the CLI always appends a `dev_containers_target_stage` carrying it.
- **The metadata is baked from the *raw*, unsubstituted config**, and the consuming CLI
  re-substitutes at runtime. So `zsh-history-${devcontainerId}` and
  `claude-code-config-${devcontainerId}` stay literal in the label and resolve per-project.
  (Verified in CLI 0.88.0: `bn()` *composes* the substitution closure, and the image-label
  metadata is substituted through that same closure — so `${devcontainerId}` round-trips just
  like any other variable.) If either ever bakes *substituted*, every consumer silently shares
  one shell-history volume and one Claude Code state volume — the latter holding an OAuth token
  and every session transcript. The `build` job's assertion step catches regressions here.
- **`name`, `build`, and JSONC comments are NOT baked** (the metadata allowlist excludes them).
  Consequence: if you add a host-credential mount or change `name` in
  `src/node/.devcontainer/devcontainer.json`, you must mirror it in `src/node-image/`.
- **`devcontainer build --label` is a no-op for Dockerfile-based configs.** `additionalLabels`
  is only wired into the `image:`+Features build path, never the Dockerfile path. OCI labels
  (`org.opencontainers.image.source`, which is what links the GHCR package to this repo) are
  therefore appended to a `cp -R` scratch copy of the context in CI, keeping `src/node/`
  byte-identical for users. If you bump the CLI, re-check whether `--label` started working and
  simplify. The appended `LABEL` lines are safe — they are not a trailing `FROM ... AS` stage,
  so they don't trip the circular-dependency pitfall below.
- **`--push` and `--output` are mutually exclusive and there is no `--metadata-file`.** Docker's
  canonical push-by-digest multi-arch recipe is unreachable. Each arch pushes a throwaway
  `:ci-<sha>-<arch>` tag and the digest is read back with `docker buildx imagetools inspect`.
- **Tag policy**: `edge` + `sha-<12>` on every push to `main`; `X.Y.Z`/`X.Y`/`X`/`latest`
  additionally when `X.Y.Z` is not yet in the registry. `on: release` and `on: push: tags`
  **cannot** be used — release-please tags with `GITHUB_TOKEN`, and `GITHUB_TOKEN`-created
  events do not trigger workflows. The registry probe is the release detector.
- **`publish-templates` has `needs: [merge]` on purpose.** Do not add `if: always()` — the
  ordering is what guarantees the image tag exists before a template referencing it ships.
- **`plan` and `build` also run on PRs** that touch `release.yaml` or `src/node/.devcontainer/**`,
  building both arches without pushing (`--push` omitted ⇒ the CLI passes `--load`, so the image
  is inspectable locally). `merge` and every attestation/upload step is gated off. **Only main
  writes the layer cache** — a PR must not be able to poison the cache release builds consume.
  If you add a step here, ask whether it needs a `pull_request` gate.
- **The assertion step is a real gate, not decoration.** It checks the four labels *and* that
  `devcontainer.metadata` still carries **both** unsubstituted volume mounts
  (`zsh-history-${devcontainerId}`, `claude-code-config-${devcontainerId}`). Both
  halves are verified to fail when they should. Don't weaken it to a warning. If you add a named
  volume to `src/node/.devcontainer/devcontainer.json`, add it to that loop.

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
  by a lifecycle command: `~/.claude` is a writable named volume (and optionally a host bind
  mount), so image-baked user-scope skills are shadowed at runtime — worse with a volume, which
  seeds from the image *once* and then serves that copy forever. A `gh skill install` in
  `postCreateCommand` would need network + auth and mutate global config. The committed payload
  is offline, deterministic, and pinned.
  **The skill's pin stays in sync with the Dockerfile's `GH_VERSION` automatically** via
  `update-skill.yaml` (see the workflows section below): Renovate bumps `GH_VERSION` on `main`,
  that Dockerfile change triggers the workflow, and it regenerates the skill at the new pin and
  opens a PR. To do it by hand, run
  `gh skill install cli/cli gh --pin v<VERSION> --dir src/node/.claude/skills --force` (the
  file's frontmatter `metadata.github-pinned` records the ref). Note `gh skill update` does
  **not** work here — it skips `--pin`ned skills by design.

The template's `devcontainer.json` mounts **no host paths by default** — only two per-project
named volumes — so it starts cleanly on any host and in any Dev Containers flow:

- `zsh-history-${devcontainerId}` → `/home/node/.commandhistory`
- `claude-code-config-${devcontainerId}` → `/home/node/.claude`

The Claude one is the [documented way](https://code.claude.com/docs/en/devcontainer) to keep
Claude Code's auth token, settings, session transcripts and prompt history across rebuilds;
without it a **Rebuild Container** silently signs the user out.

**Both are keyed by `${devcontainerId}`, never `${localWorkspaceFolderBasename}`** — keep it that
way for any volume added later. The basename is not unique: two unrelated repos in different
directories that happen to share a folder name would get the same volume. That matters for both
of these. Claude's holds an OAuth token, and since both containers use `/workspaces/<basename>`
as cwd their session transcripts would collide under the same `projects/<encoded-cwd>/` key;
shell history routinely contains tokens pasted into `curl` or `gh` commands. `${devcontainerId}`
is derived from the container's identifying labels, so it is unique per workspace. The cost is an
opaque name in `docker volume ls` and a new id if the repo moves to a different host path —
accepted deliberately.

Three invariants apply to **both** volumes; two of them are why the Dockerfile's final `RUN`
exists:

- **Every volume mountpoint must live under `/home/node`.** This is the non-obvious one. When
  the host user's uid isn't 1000 — GitHub runners are 1001, as are many Linux dev machines — the
  CLI rebuilds the image through its `scripts/updateUID.Dockerfile`, which remaps `node` to the
  host uid and then repairs ownership with `chown -R $NEW_UID:$NEW_GID $HOME_FOLDER`: the home
  folder, and nothing else. A mountpoint outside it keeps uid 1000 and is silently unwritable for
  exactly those users. `/commandhistory` was top-level and had this bug from the start; it is now
  `~/.commandhistory`. Do not move either volume back out of the home directory, and do not add a
  third one outside it.
- **The mountpoint must exist in the image and be owned by `node`.** A named volume whose
  mountpoint is missing is created root-owned and the first write fails with `EACCES`.
- **It must be empty in the image.** Docker seeds a named volume from the image's directory
  contents exactly once, at volume creation, and never again — anything baked in there would be
  frozen into every user's volume forever. Hence `rm -rf` before the `mkdir`.

Both `test.sh` files assert each volume is *mounted* **and** *writable*. The writability half is
what catches the uid trap; a mount check alone passes while history silently fails to persist.

Sharing host credentials is **opt-in** and now just one bind mount: `~/.config/gh` read-only,
shipped commented out, uncommented after `gh auth login` on the host (a bind mount requires its
source to already exist). There is deliberately **no `~/.claude` bind mount** — it would collide
with the volume above on the same target, and Docker rejects duplicate mount targets. There is
also no `~/.claude.json` mount: with `CLAUDE_CONFIG_DIR` set, Claude Code reads
`$CLAUDE_CONFIG_DIR/.claude.json`, so a mount at `/home/node/.claude.json` is a path it never
reads. There is intentionally no `initializeCommand`: with the mount off there is nothing to
pre-create. Lifecycle commands are guarded with `if [ -f package.json ]` so applying into an
empty/non-JS repo doesn't fail.

## Common pitfalls when editing the Dockerfile

- **The `gh` attestation check fails closed. Keep it that way.** The API is unauthenticated and
  rate-limited per IP per hour, which shared CI runner pools exhaust (403), so the fetch retries.
  If verification still cannot complete, the build **fails** — do not add a "proceed anyway"
  branch. In particular, never "verify" the download against a digest computed from that same
  download: it is a tautology that cannot fail. Any integrity fallback must compare against a
  digest pinned *in this repo*.
- **Three non-obvious facts about GitHub's attestations API**, each of which independently
  breaks verification silently if you get it wrong:
  1. `.attestations[].bundle` is **always null** and is gone from the documented schema. The
     Sigstore bundle lives behind `.bundle_url`, snappy-compressed
     (`Content-Type: application/x-snappy`) — hence the `python3-snappy` install/purge.
  2. There are **several attestations per artifact**. `[0]` is the in-toto *release*
     attestation with no transparency-log entry, so cosign fails with "not enough verified log
     entries: 0 < 1". Select by `predicateType == "https://slsa.dev/provenance/v1"`; the order
     is not guaranteed.
  3. `cosign verify-blob-attestation` defaults to `--type custom` and rejects SLSA with
     "invalid predicate type". It needs `--type slsaprovenance1`.

  cli/cli's own "Verification of binaries" README section — which this block cites — assumes a
  hand-downloaded `.sigstore.json` and omits `--type`, so it cannot be copied verbatim.
  A successful verification prints `Verified OK`; if you don't see that line in the build log,
  it did not verify.
- **Declare `ARG TARGETARCH` *inside* the stage, not before the first `FROM`.** A pre-`FROM` ARG
  is global scope and invisible inside a build stage, so `${TARGETARCH}` expands to empty and the
  build quietly produces an arm64 image carrying an amd64 `gh` (exit 126 at `gh --version`). The
  `${TARGETARCH:?...}` guard makes that loud. Any use of a predefined BuildKit arg
  (`TARGETARCH`, `TARGETPLATFORM`, `BUILDPLATFORM`) needs its own in-stage `ARG` line.
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

## The `node-image` template

A thin template whose `.devcontainer/devcontainer.json` is essentially just an `image:` line
pointing at `ghcr.io/andykenward/devcontainer-images/node:<major>`. It exists so users who don't
want to edit a Dockerfile can pull instead of build. Everything else in it is a copy of the
`node` payload (`renovate.json`, `.claude/skills/gh/SKILL.md`, `NOTES.md`).

- **It references a floating major tag, not a digest.** A digest or exact version would make
  every image rebuild require a template release, and would break the PR smoke test (which
  `docker tag`s the reference — impossible with `@sha256:`). Digest pinning is the consumer's
  Renovate's job. `renovate.json` disables the `devcontainer` manager for this one file to stop
  the shared preset's `docker:pinDigests` doing it here.
  **Deliberately no literal major version anywhere in this file** — quoting one here just adds
  another copy to forget. `:1` survived in `NOTES.md` through the whole 2.x line for exactly
  that reason.
- **Its `devcontainer.json` must carry anything the metadata label can't**: `name`, and the
  commented-out `~/.config/gh` host-credential mount. See the metadata allowlist note above.
  The two named volumes are *not* restated here — they arrive via the metadata label, and
  duplicating them would be a second source of truth that silently drifts.
- **`update-skill.yaml` regenerates the skill once and mirrors it into this template.** If you
  add a third template that ships the skill, extend that copy step — the workflow's PR step
  already commits N files via the Git Data API.

## Common pitfalls when editing `.github/workflows/test.yaml`

- **Use `bash script.sh` instead of `./script.sh`**: The container is non-root and has no sudo.
  Run test scripts with `bash` rather than relying on execute permissions and chmod.
- **Image-based templates are tested against a locally built image, never the published one.**
  The "Build and locally tag the prebuilt image" step builds `src/node` and tags it with the
  exact reference the template asks for; the devcontainer CLI does `docker inspect` before
  `docker pull`, so `devcontainer up` resolves it locally. That is what lets a PR test its own
  Dockerfile changes through the image path. The step is generic — it keys off the template
  referencing `ghcr.io/andykenward/devcontainer-images/`, so it no-ops for `node`.
- **The paths filter lists `src/node/.devcontainer/**` under `node-image` on purpose** — that
  is where `node-image`'s image comes from, so a Dockerfile change must retest both.
- **`${{ matrix.templates }}` is indirected through a job-level `TEMPLATE_ID` env var** in
  `run:` blocks; zizmor flags direct interpolation as template injection.
