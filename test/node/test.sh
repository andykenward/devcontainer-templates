#!/usr/bin/env bash
# Smoke test for the `node` template. Asserts the pinned toolchain resolves
# inside the built container. Run by .github/workflows/test.yaml, which copies
# this file into a throwaway project, brings the container up, and executes it.
# Self-contained on purpose (no external test lib to depend on).
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

check "node"   node --version
check "claude" claude --version
check "pnpm"   pnpm --version
check "gh"     gh --version
check "prek"   prek --version
check "cosign" cosign version
check "zsh"    zsh --version
check "git"    git --version

if [ "${fail}" -ne 0 ]; then
  echo "smoke test failed"
  exit 1
fi
echo "all checks passed"
