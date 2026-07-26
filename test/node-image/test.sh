#!/usr/bin/env bash
# Smoke test for the `node-image` template. Asserts two things:
#   1. the prebuilt image's toolchain resolves (mirrors test/node/test.sh), and
#   2. the config baked into the image's `devcontainer.metadata` label was
#      actually applied by the consuming CLI.
#
# (2) is the whole risk surface of this template: the config file it ships is
# nearly empty, so anything that stops the metadata round-trip working is
# invisible until a user hits it. test/node/test.sh cannot catch that — it tests
# a config the CLI read directly off disk.
#
# Deliberately duplicated rather than sourced from test/node/test.sh: the test
# workflow copies test/<id>/* into the container with `cp -Rp`, so a symlink
# would be copied verbatim and dangle.
set -uo pipefail

fail=0
check() {
  local label="$1"; shift
  if "$@" >/dev/null 2>&1; then
    echo "ok   - ${label}"
  else
    echo "FAIL - ${label} (\`$*\`)"
    fail=1
  fi
}

# ── toolchain (keep in sync with test/node/test.sh) ──
check "node"   node --version
check "claude" claude --version
check "pnpm"   pnpm --version
check "gh"     gh --version
check "prek"   prek --version
check "cosign" cosign version
check "zsh"    zsh --version
check "git"    git --version

# ── metadata round-trip ──
# None of these come from src/node-image/.devcontainer/devcontainer.json. They
# are only true if the image's devcontainer.metadata label was read and applied.
check "remoteUser applied"   test "$(id -un)" = "node"
check "containerEnv applied" test "${CLAUDE_CONFIG_DIR:-}" = "/home/node/.claude"
check "autoupdater disabled" test "${DISABLE_AUTOUPDATER:-}" = "1"
check "history volume mount" grep -q ' /commandhistory ' /proc/mounts
# The claude volume is named with ${devcontainerId}. Seeing it mounted proves the
# variable was baked into the label unsubstituted AND re-resolved at runtime.
check "claude volume mount"  grep -q ' /home/node/.claude ' /proc/mounts
check "claude vol writable"  touch /home/node/.claude/.write-check

if [ "${fail}" -ne 0 ]; then
  echo "smoke test failed"
  exit 1
fi
echo "all checks passed"
