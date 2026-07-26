# syntax=docker/dockerfile:1@sha256:87999aa3d42bdc6bea60565083ee17e86d1f3339802f543c0d03998580f9cb89

# Base image pinned by digest for reproducibility. Bumping the node version
# means updating both the tag and the digest — Renovate's Dockerfile manager
# does both together in one PR.
FROM node:24.18.0-bookworm-slim@sha256:6f7b03f7c2c8e2e784dcf9295400527b9b1270fd37b7e9a7285cf83b6951452d

# System packages. Individual versions are not pinned — the digest-pinned base
# image plus Docker's layer cache provide reproducibility in practice.
# - zsh + zsh-autosuggestions: interactive shell, configured via zshrc.
# - openssh-client: provides ssh-keygen, which git invokes to SSH-sign commits
#   (gpg.format=ssh + commit.gpgsign=true); without it, signed commits fail.
# - jq: used below to locate the Sigstore bundle in the GitHub attestations
#   API response when verifying the gh release.
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl wget ca-certificates \
    git openssh-client bash zsh zsh-autosuggestions jq \
    && rm -rf /var/lib/apt/lists/* \
    && chsh -s /usr/bin/zsh node

# Persisted zsh history. /commandhistory is mounted as a named volume in
# devcontainer.json so history survives container rebuilds. The directory must
# exist and be owned by `node` before the volume mounts, otherwise the first
# write fails with EACCES.
RUN mkdir -p /commandhistory \
    && touch /commandhistory/.zsh_history \
    && chown -R node:node /commandhistory

# Shell config lives in a sibling file so it can be edited without escaping
# shell quoting inside a Dockerfile RUN. See .devcontainer/zshrc.
COPY --chown=node:node zshrc /home/node/.zshrc

# pnpm — installed globally from the npm registry rather than piping the
# get.pnpm.io install script to bash. npm resolves the package against its
# registry integrity hashes, so there is no unpinnable remote shell script
# executing as root at build time. npm's global prefix on the node image is
# /usr/local, so the binary lands on PATH for the non-root `node` user. Not
# Corepack: pnpm's docs flag an outdated-signatures issue that adds
# bootstrapping friction. Renovate bumps this via the shared preset's custom
# manager (matches `pnpm@<version>`).
ENV PNPM_HOME="/usr/local/share/pnpm"
ENV PATH="$PNPM_HOME:$PNPM_HOME/bin:$PATH"
RUN npm install -g pnpm@11.16.0

# cosign — copied as a digest-pinned binary out of Sigstore's official image,
# the same trust model as prek below: no install script runs at build time, and
# the tag+digest are bumped by Renovate's native Dockerfile manager. Used to
# verify gh's build provenance in the next step, and left on PATH so the
# container can verify other signed artifacts too.
# NOTE: pinned by tag here; Renovate (:pinDigests) adds and maintains the
# @sha256 digest on its first run, matching how prek is pinned.
COPY --from=ghcr.io/sigstore/cosign/cosign:v3.1.2@sha256:d91bc4e7e95e8d2f549c747a72dc174f90579e410a1695f57f686674f84ce849 /ko-app/cosign /usr/local/bin/cosign

# GitHub CLI — verified by SLSA build provenance instead of apt-key trust.
# gh is NOT installed from the apt repo. Instead we download the pinned,
# immutable release archive (gh releases are immutable since v2.93.0), fetch its
# GitHub Artifact Attestation, and have the digest-pinned cosign confirm the
# bytes were built by cli/cli's own release workflow on public-good Sigstore.
# Verification fails closed.
#
# cosign (not `gh attestation verify`) because gh isn't installed yet at this
# point — this is the tool-agnostic path GitHub documents for the "gh not yet
# installed" case: https://github.com/cli/cli#verification-of-binaries
#
# TARGETARCH is supplied by BuildKit, so this works on amd64 and arm64. It MUST
# be declared inside the stage: an `ARG TARGETARCH` before the first `FROM` is
# global scope and is NOT visible here, so `${TARGETARCH}` would silently expand
# to empty and the fallback below would fetch the amd64 tarball on every
# platform. That produces an arm64 image carrying an amd64 `gh`, which fails at
# the `gh --version` check at the end of this block with exit code 126.
#
# This fails closed, and there is deliberately no "verify the download against a
# hash we just computed from that same download" fallback — that check cannot
# fail and proves nothing, so it silently installed an unverified gh whenever the
# attestations API was unavailable.
#
# The bundle comes from `.attestations[].bundle_url`, NOT `.attestations[].bundle`.
# GitHub moved the Sigstore bundle out of the API response body: `bundle` is now
# always null (it is gone from the documented schema), and the real bundle is a
# snappy-compressed blob behind a signed URL. Reading `.bundle` therefore always
# yielded null, every build silently took the old "attestation unavailable"
# fallback, and no provenance was ever actually checked. python3-snappy is
# installed and purged inside this single RUN, so the layer keeps ~none of it.
#
# GitHub returns SEVERAL attestations per artifact. Do not take [0]: that is the
# in-toto release attestation, which carries no transparency-log entry, so cosign
# rejects it with "not enough verified log entries from transparency log: 0 < 1".
# The SLSA build provenance is a different entry, and the order is not
# guaranteed, so we select it by predicateType.
#
# The attestations API is unauthenticated here and rate-limited per source IP per
# hour, which shared CI runner pools do exhaust (403). The retry loop rides out
# transient failures; a genuinely exhausted limit needs a re-run once it resets.
#
# Maintenance:
#   - GH_VERSION is bumped by Renovate (github-releases custom manager).
#   - If cli/cli change their release workflow path/ref, a version bump will
#     fail verification here — update --certificate-identity to match.
ARG TARGETARCH
ARG GH_VERSION=2.96.0
RUN set -eux; \
    arch="${TARGETARCH:?TARGETARCH is empty — see the note above about ARG scope}"; \
    tarball="gh_${GH_VERSION}_linux_${arch}.tar.gz"; \
    cd /tmp; \
    wget -nv "https://github.com/cli/cli/releases/download/v${GH_VERSION}/${tarball}"; \
    digest="$(sha256sum "${tarball}" | cut -d' ' -f1)"; \
    attempt=1; \
    while :; do \
      if wget -nv --header='Accept: application/vnd.github+json' -O bundle-raw.json \
        "https://api.github.com/repos/cli/cli/attestations/sha256:${digest}"; then \
        break; \
      fi; \
      if [ "${attempt}" -ge 5 ]; then \
        echo "FATAL: could not fetch a build attestation for ${tarball} after ${attempt} attempts." >&2; \
        echo "Refusing to install an unverified gh. Retry once api.github.com is reachable" >&2; \
        echo "and its unauthenticated rate limit has reset." >&2; \
        exit 1; \
      fi; \
      echo "attestation fetch failed (attempt ${attempt}); retrying in $((attempt * 15))s"; \
      sleep "$((attempt * 15))"; \
      attempt="$((attempt + 1))"; \
    done; \
    apt-get update; \
    apt-get install -y --no-install-recommends python3-snappy; \
    count="$(jq -r '.attestations | length' bundle-raw.json)"; \
    i=0; found=''; \
    while [ "${i}" -lt "${count}" ]; do \
      url="$(jq -r ".attestations[${i}].bundle_url // empty" bundle-raw.json)"; \
      i="$((i + 1))"; \
      [ -n "${url}" ] || continue; \
      wget -nv -O candidate.json.sn "${url}"; \
      python3 -c "import snappy,sys; sys.stdout.buffer.write(snappy.uncompress(open('candidate.json.sn','rb').read()))" \
        > candidate.json; \
      if jq -r '.dsseEnvelope.payload' candidate.json | base64 -d \
         | jq -e '.predicateType == "https://slsa.dev/provenance/v1"' >/dev/null 2>&1; then \
        mv candidate.json gh.sigstore.json; found=1; break; \
      fi; \
    done; \
    apt-get purge -y python3-snappy; \
    apt-get autoremove -y; \
    rm -rf /var/lib/apt/lists/*; \
    if [ -z "${found}" ]; then \
      echo "FATAL: no SLSA provenance attestation among ${count} attestation(s) for ${tarball}." >&2; \
      echo "Refusing to install an unverified gh." >&2; \
      exit 1; \
    fi; \
    cosign verify-blob-attestation \
      --bundle gh.sigstore.json \
      --new-bundle-format \
      --type slsaprovenance1 \
      --certificate-oidc-issuer='https://token.actions.githubusercontent.com' \
      --certificate-identity='https://github.com/cli/cli/.github/workflows/deployment.yml@refs/heads/trunk' \
      "${tarball}"; \
    tar -xzf "${tarball}"; \
    install -m 0755 "gh_${GH_VERSION}_linux_${arch}/bin/gh" /usr/local/bin/gh; \
    rm -rf "/tmp/gh_${GH_VERSION}_linux_${arch}" "/tmp/${tarball}" /tmp/bundle-raw.json \
      /tmp/gh.sigstore.json /tmp/gh.sigstore.json.sn; \
    gh --version

# prek — pre-commit hook manager, copied from the official digest-pinned
# distroless image. Content-addressed: if the tag were force-pushed, the digest
# would not match and the build fails closed. Renovate's Dockerfile manager
# bumps the tag+digest.
#
# The digest MUST be the multi-arch index (manifest list) digest, not an
# arch-specific manifest digest. With the index, BuildKit resolves COPY --from
# to the manifest matching the build's platform, so amd64 and arm64 each get the
# right binary. Pinning an arch-specific digest here copies that one arch's
# binary onto every platform (e.g. an arm64 prek onto an amd64 image), and it
# fails to execute at runtime — the `prek --version` smoke test catches this.
COPY --from=ghcr.io/j178/prek:v0.4.3@sha256:ef02821aae78d53bf766e2764641b62b5fb7cf3a2394147395f0bf4105e30484 /prek /usr/local/bin/prek

# Drop to the non-root `node` user as the image default. devcontainer.json also
# sets `remoteUser: node` for VS Code, but this also covers plain
# `docker exec`/`docker run`, so nothing lands as root by default. All
# privileged install steps above run as root; dev container Features re-elevate
# on their own.
USER node
WORKDIR /workspace

# Claude Code — installed with Anthropic's official native installer, pinned to a
# specific version via the installer's `[stable|latest|VERSION]` argument. This
# is NOT an unpinned `curl | bash`: the version is fixed here for reproducibility
# and frozen at runtime by DISABLE_AUTOUPDATER=1 (devcontainer.json). The
# installer refuses to run under sudo and installs into the invoking user's
# ~/.local, so it runs as `node` (USER above) and its launcher dir is put on
# PATH. Not the npm package — the native installer has no Node/npm dependency.
# Renovate bumps CLAUDE_CODE_VERSION; the native channel tracks the
# @anthropic-ai/claude-code package versions (npm datasource).
# renovate: datasource=npm depName=@anthropic-ai/claude-code
ARG CLAUDE_CODE_VERSION=2.1.218
ENV PATH="/home/node/.local/bin:$PATH"
RUN curl -fsSL https://claude.ai/install.sh | bash -s "${CLAUDE_CODE_VERSION}" \
    && claude --version
