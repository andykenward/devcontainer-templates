# syntax=docker/dockerfile:1

# Base image pinned by digest for reproducibility. Bumping the node version
# means updating both the tag and the digest — Renovate's Dockerfile manager
# does both together in one PR.
FROM node:24.18.0-bookworm-slim@sha256:b31e7a42fdf8b8aa5f5ed477c72d694301273f1069c5a2f71d53c6482e99a2fc

# System packages. Individual versions are not pinned — the digest-pinned base
# image plus Docker's layer cache provide reproducibility in practice.
# - zsh + zsh-autosuggestions: interactive shell, configured via zshrc.
# - openssh-client: provides ssh-keygen, which git invokes to SSH-sign commits
#   (gpg.format=ssh + commit.gpgsign=true); without it, signed commits fail.
# - jq: used below to pull the Sigstore bundle out of the GitHub attestations
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
RUN npm install -g pnpm@11.9.0

# cosign — copied as a digest-pinned binary out of Sigstore's official image,
# the same trust model as prek below: no install script runs at build time, and
# the tag+digest are bumped by Renovate's native Dockerfile manager. Used to
# verify gh's build provenance in the next step, and left on PATH so the
# container can verify other signed artifacts too.
# NOTE: pinned by tag here; Renovate (:pinDigests) adds and maintains the
# @sha256 digest on its first run, matching how prek is pinned.
COPY --from=ghcr.io/sigstore/cosign/cosign:v2.4.1 /ko-app/cosign /usr/local/bin/cosign

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
# TARGETARCH is supplied by BuildKit, so this works on amd64 and arm64.
#
# Maintenance:
#   - GH_VERSION is bumped by Renovate (github-releases custom manager).
#   - If cli/cli change their release workflow path/ref, a version bump will
#     fail verification here — update --certificate-identity to match.
ARG GH_VERSION=2.95.0
ARG TARGETARCH
RUN set -eux; \
    arch="${TARGETARCH:-amd64}"; \
    tarball="gh_${GH_VERSION}_linux_${arch}.tar.gz"; \
    cd /tmp; \
    wget -nv "https://github.com/cli/cli/releases/download/v${GH_VERSION}/${tarball}"; \
    digest="$(sha256sum "${tarball}" | cut -d' ' -f1)"; \
    wget -nv --header='Accept: application/vnd.github+json' -O bundle-raw.json \
      "https://api.github.com/repos/cli/cli/attestations/sha256:${digest}"; \
    jq '.attestations[0].bundle' bundle-raw.json > gh.sigstore.json; \
    cosign verify-blob-attestation \
      --bundle gh.sigstore.json \
      --new-bundle-format \
      --certificate-oidc-issuer='https://token.actions.githubusercontent.com' \
      --certificate-identity='https://github.com/cli/cli/.github/workflows/deployment.yml@refs/heads/trunk' \
      "${tarball}"; \
    tar -xzf "${tarball}"; \
    install -m 0755 "gh_${GH_VERSION}_linux_${arch}/bin/gh" /usr/local/bin/gh; \
    rm -rf "/tmp/gh_${GH_VERSION}_linux_${arch}" "/tmp/${tarball}" /tmp/bundle-raw.json /tmp/gh.sigstore.json; \
    gh --version

# prek — pre-commit hook manager, copied from the official digest-pinned
# distroless image. Content-addressed: if the tag were force-pushed, the digest
# would not match and the build fails closed. Renovate's Dockerfile manager
# bumps the tag+digest.
COPY --from=ghcr.io/j178/prek:v0.4.3@sha256:953593c93d253d44bad97b36b428c13edd074dc35de003ccbf3ff9a40c0c79b9 /prek /usr/local/bin/prek

# Drop to the non-root `node` user as the image default. devcontainer.json also
# sets `remoteUser: node` for VS Code, but this also covers plain
# `docker exec`/`docker run`, so nothing lands as root by default. All
# privileged install steps above run as root; dev container Features re-elevate
# on their own.
USER node
WORKDIR /workspace
