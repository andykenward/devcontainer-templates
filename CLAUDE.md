# CLAUDE.md

Guidance for Claude Code (claude.ai/code) working in this repository.

## What this repo is

No application code. The product is `src/<id>/` — directories copied **verbatim** into a user's
project by `devcontainer templates apply` — published as OCI artifacts to
`ghcr.io/andykenward/devcontainer-templates`.

Two templates: `node` (ships a Dockerfile) and `node-image` (pulls a prebuilt image). The image
itself is built from the `node` template's own build context and published to
`ghcr.io/andykenward/devcontainer-images/node`.

## Layout

| Path | Notes |
| --- | --- |
| `src/<id>/devcontainer-template.json` | manifest — id, version, `options`, `optionalPaths` |
| `src/<id>/**` (rest) | payload dropped into the applied project |
| `src/<id>/README.md` | **auto-generated** by `update-documentation.yml` from manifest + `NOTES.md`. Edit `NOTES.md`, never this |
| `src/<id>/renovate.json` | an `optionalPath` → lands at the *applied* repo's root. Not this repo's own config |
| `test/<id>/test.sh` | smoke test, run inside the built container by CI |
| `.devcontainer/` (root) | dev env for working *on* this repo — distinct from `src/node/.devcontainer/`, which is template output |
| `RELEASING.md` | human-facing version of "Releasing" below; keep the two in sync |

## Testing

CI (`test.yaml`) copies `test/<id>/*` into a throwaway project, runs `devcontainer up`, then
`test.sh` inside the container. Locally (needs the devcontainer CLI + Docker):

```sh
npm install -g @devcontainers/cli
devcontainer up --workspace-folder src/node/
devcontainer exec --workspace-folder src/node/ ./test/node/test.sh   # pinned toolchain resolves
```

`test.sh` is plain bash, no framework — each `check` line asserts a tool is on PATH and runs.
**Add a `check` when you add a tool to the Dockerfile.**

`test.yaml` pitfalls:

- **`bash script.sh`, not `./script.sh`** — non-root container, no sudo, no chmod.
- **Image templates test a locally built image, never the published one.** The build step tags
  `src/node` with the exact reference the template asks for; the CLI does `docker inspect` before
  `docker pull`, so `devcontainer up` resolves it locally. That's what lets a PR test its own
  Dockerfile changes through the image path. It keys off the template referencing
  `ghcr.io/andykenward/devcontainer-images/`, so it no-ops for `node`.
- **`src/node/.devcontainer/**` is listed under `node-image`'s paths filter on purpose** — that's
  where its image comes from, so a Dockerfile change must retest both.
- **`${{ matrix.templates }}` is indirected through a job-level `TEMPLATE_ID` env var** in `run:`
  blocks; zizmor flags direct interpolation as template injection.

## Releasing

Four workflows fire on push to `main` — the first three every merge, the last only on Dockerfile
changes:

1. **`release-please.yaml`** — opens/maintains the release PR. Merging it tags, and via
   `release-please-config.json`'s `extra-files` bumps `$.version` in both templates' manifests and
   rewrites the floating-major image tag. **The version bump is what ships a change.**
2. **`release.yaml`** — `plan` (resolve version, detect release) → `build` (amd64 on
   `ubuntu-latest`, arm64 on `ubuntu-24.04-arm`) → `merge` (manifest list, attestations, cosign) →
   `publish-templates`. **Template publish never overwrites an existing version**, so nothing ships
   until the version moves.
3. **`update-documentation.yml`** — regenerates `src/*/README.md`, opens a PR.
4. **`update-skill.yaml`** — on `src/node/.devcontainer/Dockerfile` changes only. Regenerates
   `src/node/.claude/skills/gh/SKILL.md` at the pinned `GH_VERSION` and mirrors it into
   `node-image`. Idempotent — unchanged `GH_VERSION` produces identical bytes and no PR. Adding a
   third template that ships the skill means extending its copy step.

Dependency bumps come from **Renovate** via the shared `andykenward/renovate-config` preset
(external repo).

**Renovate labels every bump `chore(deps)`, which is not releasable — so a Renovate PR touching
`src/**` must be retitled to `fix` before merging.** Merges are squashed, so the PR title is the
commit subject release-please reads. `release-type: simple` counts only feat/fix/breaking as
user-facing; otherwise it logs `No user facing commits found since <sha> - skipping` and opens no
PR. With no version bump, `publish-templates` won't republish and `plan`'s registry probe won't
re-tag `X.Y.Z`/`X.Y`/`X`/`latest` — the bump reaches `edge` and `sha-<12>` only and no user sees
it. Bumps confined to `.github/**` stay `chore`.

The retitle is deliberately manual. A `semanticCommitType` rule in `renovate.json` was proposed
and rejected — don't add one back without asking.

### The floating major tag

`node-image` ships `…/node:<major>`, which must track this repo's major. release-please rewrites
every occurrence via `extra-files` using its **Generic** updater, which acts only on annotated
lines: `x-release-please-major` (that line) or `x-release-please-start-major` …
`x-release-please-end` (every line between).

Annotated: `src/node-image/.devcontainer/devcontainer.json` (trailing JSONC comment),
`src/node-image/NOTES.md`, its generated `README.md`, and the root `README.md` (HTML comments,
invisible when rendered). Both READMEs are listed so the release PR is self-consistent; `NOTES.md`
remains the generator's source.

- **Every entry must be `{"type": "generic", "path": …}`, never a bare string.** A bare string
  ending `.json`/`.yaml`/`.yml`/`.toml`/`.xml` routes to a `CompositeUpdater` running
  `GenericJson('$.version')` — a strict `JSON.parse` — *before* the annotation pass. On JSONC that
  throws and does not fail soft: the job dies with `Unexpected token '/', "// Dev Con"... is not
  valid JSON` and **no release PR is created**. It broke `main` once. The explicit type skips the
  parse (needs release-please ≥ 17; 17.6.0 confirmed in the pinned action).
- **The regex is `/\d+\b/` — the first digit run on the line, whatever it is.** A block must not
  span a line containing any other number (wrapping the "Prebuilt and multi-arch" bullet would
  rewrite `linux/amd64` → `linux/amd3`). Use the inline form where a line has a stray digit; for a
  tag inside a fenced code block put the markers *outside* the fence and check every line between.
- **Only the major is annotated**, so non-major releases are no-ops and re-running is safe.
- **The boundary is safe**: one commit bumps both version and tag, and `publish-templates`
  `needs: [merge]`, so the new `:N` image exists before a template referencing it ships.

### Workflow naming

`name: "(Group) Sentence case"`, Group ∈ **Release / Test / Update / Claude** — GitHub sorts the
sidebar by name. **The group describes purpose, never trigger**; trigger-based names go stale
(`"PR - Test Updated Templates"` broke when `release.yaml` also started running on PRs). Don't
reintroduce `PR -`, `Push -`, or a verb true of only one trigger.

**Only `name:` is conformed — filenames are deliberately left alone** (including the `.yml`/`.yaml`
split): renaming orphans run history, and `release.yaml` self-references its own path in
`pull_request.paths`, so a rename would silently stop it triggering on its own changes.

## The prebuilt image — invariants

Each verified against `@devcontainers/cli@0.88.0`:

- **Exactly one Dockerfile, ever.** The image builds from `src/node/.devcontainer/` — the same
  bytes the template ships. No `images/` directory, no copy.
- **`devcontainer build`, not `docker buildx build`, is what bakes `devcontainer.metadata`.** That
  label is why `node-image` can be a two-line file. Baked even with zero Features — the CLI always
  appends a `dev_containers_target_stage` carrying it.
- **Metadata bakes from the *raw*, unsubstituted config**; the consuming CLI re-substitutes at
  runtime, so `zsh-history-${devcontainerId}` and `claude-code-config-${devcontainerId}` stay
  literal and resolve per-project. (In 0.88.0 `bn()` *composes* the substitution closure and the
  image-label metadata passes through it, so `${devcontainerId}` round-trips.) If either ever baked
  *substituted*, every consumer would share one shell-history volume and one Claude Code state
  volume — the latter holding an OAuth token and every session transcript.
- **`name`, `build`, and JSONC comments are NOT baked** (excluded from the metadata allowlist). So
  a host-credential mount or `name` change in `src/node/.devcontainer/devcontainer.json` must be
  mirrored in `src/node-image/`.
- **`devcontainer build --label` is a no-op for Dockerfile configs** — `additionalLabels` is wired
  only into the `image:`+Features path. OCI labels (`org.opencontainers.image.source`, which links
  the GHCR package to this repo) are appended to a `cp -R` scratch copy of the context in CI,
  keeping `src/node/` byte-identical for users. Re-check on CLI bumps and simplify if fixed. The
  appended `LABEL` lines are safe — not a trailing `FROM ... AS` stage, so they don't trip the
  circular-dependency pitfall below.
- **`--push` and `--output` are mutually exclusive, and there's no `--metadata-file`.** Docker's
  canonical push-by-digest multi-arch recipe is unreachable; each arch pushes a throwaway
  `:ci-<sha>-<arch>` tag and the digest is read back with `docker buildx imagetools inspect`.
- **Tags**: `edge` + `sha-<12>` every push to `main`; `X.Y.Z`/`X.Y`/`X`/`latest` additionally when
  `X.Y.Z` isn't yet in the registry. **The registry probe is the release detector** — `on: release`
  and `on: push: tags` cannot work, since release-please tags with `GITHUB_TOKEN` and
  `GITHUB_TOKEN`-created events don't trigger workflows.
- **`publish-templates` has `needs: [merge]` on purpose.** Never add `if: always()`.
- **`plan` and `build` also run on PRs** touching `release.yaml` or `src/node/.devcontainer/**`,
  building both arches without pushing (`--push` omitted ⇒ CLI passes `--load`). `merge` and every
  attestation/upload step is gated off, and **only main writes the layer cache** — a PR must not
  poison the cache release builds consume. New steps here need a `pull_request` gate.
- **The assertion step is a real gate.** It checks the four labels *and* that
  `devcontainer.metadata` still carries **both** unsubstituted volume mounts. Both halves are
  verified to fail when they should. Don't weaken it to a warning; add any new named volume to
  that loop.

## The `node` template — invariants

Deliberately opinionated, **no picker options** (`"options": {}`). The point is reproducibility and
supply-chain provenance:

- **Everything is pinned.** Base image by tag **and** digest together; `cosign` and `prek` are
  `COPY --from` digest-pinned distroless images, not install scripts. Renovate bumps tag+digest in
  one PR — keep them in sync.
- **`gh` installs from release with provenance, not apt.** The Dockerfile downloads the pinned
  tarball, fetches its GitHub attestation, and has `cosign verify-blob-attestation` confirm
  `cli/cli`'s workflow built it, failing closed. If `cli/cli` move their release workflow path,
  update `--certificate-identity` or bumps fail here.
- **`pnpm` via `npm install -g pnpm@<version>`** (registry integrity) — not the remote script, not
  Corepack. Renovate's custom manager matches the literal `pnpm@<version>` and `GH_VERSION=<version>`
  patterns; keep them intact.
- Runs as non-root `node` (`USER node`), matched by `remoteUser: node`.
- **The `gh` agent skill ships in the payload, not the image.**
  `src/node/.claude/skills/gh/SKILL.md` is copied by `apply` into each project's
  `.claude/skills/gh/`. Not baked into the image and not installed by a lifecycle command:
  `~/.claude` is a writable named volume, which seeds from the image *once* and then serves that
  copy forever, so image-baked user-scope skills are shadowed at runtime; and `gh skill install` in
  `postCreateCommand` would need network + auth and mutate global config. `update-skill.yaml` keeps
  the pin in sync automatically. By hand:
  `gh skill install cli/cli gh --pin v<VERSION> --dir src/node/.claude/skills --force` (frontmatter
  `metadata.github-pinned` records the ref). `gh skill update` does **not** work — it skips
  `--pin`ned skills by design.

### Volumes

`devcontainer.json` mounts **no host paths by default** — only two per-project named volumes, so it
starts cleanly on any host and in any Dev Containers flow:

- `zsh-history-${devcontainerId}` → `/home/node/.commandhistory`
- `claude-code-config-${devcontainerId}` → `/home/node/.claude` — the
  [documented way](https://code.claude.com/docs/en/devcontainer) to keep Claude Code's auth token,
  settings, transcripts and prompt history across rebuilds. Without it, **Rebuild Container**
  silently signs the user out.

**Key both by `${devcontainerId}`, never `${localWorkspaceFolderBasename}`** — and any volume added
later too. The basename isn't unique: two unrelated repos sharing a folder name would collide.
Claude's volume holds an OAuth token, and since both containers use `/workspaces/<basename>` as cwd
their transcripts would collide under one `projects/<encoded-cwd>/` key; shell history routinely
contains tokens pasted into `curl` or `gh`. `${devcontainerId}` derives from the container's
identifying labels. Cost — an opaque name in `docker volume ls`, and a new id if the repo moves —
accepted deliberately.

Three invariants for **both** volumes; the last two are why the Dockerfile's final `RUN` exists:

- **Every mountpoint must live under `/home/node`.** When the host uid isn't 1000 (GitHub runners
  are 1001, as are many Linux dev machines) the CLI rebuilds via `scripts/updateUID.Dockerfile`,
  which remaps `node` and repairs ownership with `chown -R $NEW_UID:$NEW_GID $HOME_FOLDER` — the
  home folder and nothing else. A mountpoint outside it keeps uid 1000 and is silently unwritable
  for exactly those users. `/commandhistory` had this bug; it's now `~/.commandhistory`. Don't move
  either back out, and don't add a third outside.
- **The mountpoint must exist in the image and be owned by `node`** — otherwise the volume is
  created root-owned and the first write fails `EACCES`.
- **It must be empty in the image.** Docker seeds a named volume from the image exactly once, at
  creation; anything baked there is frozen into every user's volume forever. Hence `rm -rf` before
  `mkdir`.

Both `test.sh` files assert each volume is *mounted* **and** *writable* — the writability half
catches the uid trap; a mount check alone passes while history silently fails to persist.

Host credentials are **opt-in**, one bind mount: `~/.config/gh` read-only, shipped commented out,
uncommented after `gh auth login` on the host (bind mounts require an existing source).
Deliberately **no `~/.claude` bind mount** — it would collide with the volume on the same target
and Docker rejects duplicate targets. No `~/.claude.json` mount either: with `CLAUDE_CONFIG_DIR`
set, Claude Code reads `$CLAUDE_CONFIG_DIR/.claude.json`, so `/home/node/.claude.json` is a path it
never reads. No `initializeCommand`: with the mount off there's nothing to pre-create. Lifecycle
commands are guarded with `if [ -f package.json ]` so applying into an empty/non-JS repo doesn't
fail.

## Dockerfile pitfalls

- **The `gh` attestation check fails closed. Keep it that way.** The API is unauthenticated and
  rate-limited per IP per hour, which shared CI runner pools exhaust (403), so the fetch retries.
  If verification still can't complete the build **fails** — no "proceed anyway" branch. Never
  "verify" a download against a digest computed from that same download; it's a tautology. Any
  integrity fallback must compare against a digest pinned *in this repo*.
- **Three non-obvious facts about GitHub's attestations API**, each of which silently breaks
  verification:
  1. `.attestations[].bundle` is **always null** and gone from the documented schema. The Sigstore
     bundle lives behind `.bundle_url`, snappy-compressed (`Content-Type: application/x-snappy`) —
     hence the `python3-snappy` install/purge.
  2. There are **several attestations per artifact**, and order isn't guaranteed. `[0]` is the
     in-toto *release* attestation with no transparency-log entry, so cosign fails "not enough
     verified log entries: 0 < 1". Select by `predicateType == "https://slsa.dev/provenance/v1"`.
  3. `cosign verify-blob-attestation` defaults to `--type custom` and rejects SLSA with "invalid
     predicate type". It needs `--type slsaprovenance1`.

  cli/cli's own "Verification of binaries" README section — which the Dockerfile cites — assumes a
  hand-downloaded `.sigstore.json` and omits `--type`, so it can't be copied verbatim. Success
  prints `Verified OK`; no such line in the build log means it did not verify.
- **Declare `ARG TARGETARCH` *inside* the stage, not before the first `FROM`.** A pre-`FROM` ARG is
  global scope and invisible in a stage, so `${TARGETARCH}` expands empty and the build quietly
  produces an arm64 image carrying an amd64 `gh` (exit 126 at `gh --version`). The
  `${TARGETARCH:?…}` guard makes that loud. Every predefined BuildKit arg (`TARGETARCH`,
  `TARGETPLATFORM`, `BUILDPLATFORM`) needs its own in-stage `ARG`.
- **POSIX `sh`, not bash** — no process substitution `<(…)`; pipe instead.
- **No `sudo`** — the image is non-root by design. Don't add privileged steps to tests or scripts.
- **Pin `COPY --from` images to the multi-arch *index* digest.** Given the index, BuildKit resolves
  to the manifest matching the build platform. An arch-specific digest copies that one binary onto
  *every* platform (an arm64 `prek` onto amd64), failing at runtime — this broke the `prek` smoke
  test. Check with `docker buildx imagetools inspect <ref>`: an index is
  `application/vnd.oci.image.index.v1+json` with multiple platforms; arch-specific is
  `image.manifest.v1+json` with one. Do **not** fix this with an intermediate
  `FROM --platform … AS stage` — a stage defined after the main image whose own `COPY --from`
  references itself becomes the last stage, which the devcontainer CLI then targets, hitting a
  circular dependency. A plain `COPY --from` on the index digest needs no extra stage.

## The `node-image` template

`.devcontainer/devcontainer.json` is essentially one `image:` line at
`ghcr.io/andykenward/devcontainer-images/node:<major>`, for users who'd rather pull than build.
Everything else is a copy of the `node` payload.

- **Floating major tag, not a digest.** A digest or exact version would make every image rebuild
  require a template release, and would break the PR smoke test (which `docker tag`s the reference
  — impossible with `@sha256:`). Digest pinning is the *consumer's* Renovate's job; `renovate.json`
  disables the `devcontainer` manager for this one file to stop the shared preset's
  `docker:pinDigests` doing it here. **No literal major version anywhere in this file** — another
  copy to forget. `:1` survived in `NOTES.md` through the whole 2.x line for exactly that reason.
- **Its `devcontainer.json` must carry whatever the metadata label can't**: `name`, and the
  commented-out `~/.config/gh` mount. The two named volumes are *not* restated — they arrive via
  the label, and duplicating them would be a second source of truth that silently drifts.
