# Releasing

How a change in this repo reaches someone else's machine.

There is no version to edit and no tag to push — all of that is automated. But
one thing is on you, and getting it wrong fails silently:

> **The type on your PR title decides whether your change ships at all.**

## Why the PR title

Merges to `main` are squashed, so the squashed commit's subject *is* your PR
title. That is the only thing [release-please](https://github.com/googleapis/release-please)
reads. `chore(deps): update node.js to v24.18.1 (#63)` on the PR becomes exactly
that commit on `main`, and release-please decides from the `chore` prefix.

## What each type does

| PR title starts with | Release | Ships? |
| --- | --- | --- |
| `feat:` / `feat(node):` | minor — `3.1.0` → `3.2.0` | yes |
| `fix:` / `fix(node):` | patch — `3.1.0` → `3.1.1` | yes |
| `perf:`, `revert:` | patch | yes |
| `feat!:` or a `BREAKING CHANGE:` footer | major — `3.1.0` → `4.0.0` | yes |
| `chore:`, `ci:`, `build:`, `docs:`, `test:`, `refactor:`, `style:` | none | **no** |

The bottom row is the trap. Those merge perfectly happily, every check green,
and then nothing happens. If your change is something a *user* of the templates
would notice, it needs one of the top rows.

Use `chore:`/`ci:` deliberately for things that only affect how this repo builds
itself — a workflow tweak, a bumped action. Those genuinely shouldn't cut a
release.

## The flow

1. **Merge your PR** into `main` with a releasable title.
2. **release-please opens a release PR** titled `chore(main): release X.Y.Z`. It
   accumulates — merge three `fix:` PRs and one release PR covers all three.
   Review the changelog it drafts; that is your last chance to correct it.
3. **Merge the release PR.** This is the moment of release. It tags `vX.Y.Z`,
   cuts a GitHub release, and writes the new version into both templates'
   `devcontainer-template.json` via `extra-files` in
   [`release-please-config.json`](release-please-config.json).
4. **Publishing runs automatically** off that merge — it is just another push to
   `main`. The image is built and pushed, *then* both templates are published.

Step 4 is where the version bump earns its keep. Template publishing refuses to
overwrite a version that already exists in the registry, and the image only gets
its semver tags when the version isn't already there. Without a bump, both steps
no-op.

## What "released" actually means

| Consumer | Gets your change when |
| --- | --- |
| `node` template users | the template is republished at the new version — i.e. on release |
| `node-image` users on `:3` | the `X` tag is re-pointed — i.e. on release |
| Anyone pulling `:edge` or `:sha-<12>` | immediately, on every push to `main` |

That last row is why an unreleased change can look like it worked. The image
really was rebuilt and pushed; it just went nowhere anyone is watching. `:3` and
`:latest` keep serving the previous build until a release moves them.

## Dependency PRs need a decision

Renovate opens every bump as `chore(deps): …` — a non-releasing type, from the
table above. Before merging one, look at **which files it touches**:

| It changes | Do |
| --- | --- |
| `src/**` — template payload, or the Dockerfile the prebuilt image is built from | **retitle to `fix(deps): …`**, then merge |
| `.github/**` only — a workflow, a pinned action | leave it as `chore`, merge |

The first row is the one to watch. A Node base image bump, a `pnpm@` or
`GH_VERSION=` bump, a Claude Code bump — all of those change what users get, and
merged as `chore` they land on `main` and go nowhere. Edit the PR title in the
GitHub UI; the squash takes it from there.

Retitle before you merge. Once it's on `main` the type is fixed, and you're into
the recovery section below.

## Checking it worked

After merging, look at the **(Release) Version + changelog** run for your commit.
If no release PR appeared, the log says so plainly:

```
✔ No user facing commits found since <sha> - skipping
```

That is the "you used a non-releasing type" message.

## If you already merged with the wrong type

The commit can't be retyped — it's on `main`. Two ways out:

- **Let the next release sweep it up.** Version bumps aren't per-commit: the
  next `fix:` or `feat:` that lands cuts a release containing *everything*
  merged since the last one, your stranded commit included. Fine if something
  else is due soon.
- **Force one.** Land a commit whose message body carries a `Release-As:` footer:

  ```sh
  git commit --allow-empty -m "chore: release 3.1.1" -m "Release-As: 3.1.1"
  ```

  release-please honours that footer and opens a release PR at exactly that
  version.

There is also a `force-semver-tags` input on the **(Release) Image + templates**
workflow, which re-pushes `X.Y.Z`/`X.Y`/`X`/`latest` at the current build without
a version bump. It is for repairing a botched publish, not for shipping changes —
it moves the image tags while both templates still claim the old version, so use
it knowing the two are briefly out of step.

## Major versions

`node-image` references `ghcr.io/andykenward/devcontainer-images/node:<major>`,
and that major is rewritten everywhere it appears — the template, both `NOTES.md`
and generated `README.md` files, and the root README — by release-please as part
of the release PR. Don't edit those by hand; the annotations that drive it are
documented in [`CLAUDE.md`](CLAUDE.md).

Ordering is safe by construction: the same commit bumps the template version and
the tag, and template publishing waits on the image, so the new `:N` image exists
before a template pointing at it ships.
