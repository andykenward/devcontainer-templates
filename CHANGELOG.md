# Changelog

## [1.2.0](https://github.com/andykenward/devcontainer-templates/compare/v1.1.0...v1.2.0) (2026-07-24)


### Features

* ai skills ([#13](https://github.com/andykenward/devcontainer-templates/issues/13)) ([4b6bec0](https://github.com/andykenward/devcontainer-templates/commit/4b6bec0b872b5f7c1039d2644dfeb12a7da6ef55))
* change claude code cli install ([#10](https://github.com/andykenward/devcontainer-templates/issues/10)) ([e9d1898](https://github.com/andykenward/devcontainer-templates/commit/e9d1898b86aee9b209ca2e26aeadaeccad5783cc))

## [1.1.0](https://github.com/andykenward/devcontainer-templates/compare/v1.0.0...v1.1.0) (2026-07-05)


### Features

* add gh ([fd9cb30](https://github.com/andykenward/devcontainer-templates/commit/fd9cb30a97e0e4acf8d0c40f252a74ef27aff52c))
* add github-cli ([98e9027](https://github.com/andykenward/devcontainer-templates/commit/98e9027c2c25956eeccdacce8d700114f1f0f7ae))
* docs and actions ([d346f90](https://github.com/andykenward/devcontainer-templates/commit/d346f908b5f2023f579903b5e362506070712064))
* node dev container template with provenance-verified gh ([7b7c8e3](https://github.com/andykenward/devcontainer-templates/commit/7b7c8e330f6f2ef2f6f9f5ce05538229c00a9ca8))


### Bug Fixes

* explicitly set platform for prek COPY --from ([f8ad1f9](https://github.com/andykenward/devcontainer-templates/commit/f8ad1f93ec4f63d93ac190dc490fe5309bc9a2ca))
* handle missing gh attestations in Dockerfile ([c0b72b4](https://github.com/andykenward/devcontainer-templates/commit/c0b72b482f8e186d008c7ac372f0a036440e12a7))
* move PREK_IMAGE ARG to global scope before first FROM ([d1d4564](https://github.com/andykenward/devcontainer-templates/commit/d1d45640e8b4bb6dd76bdd6247c288b299f9f9dd))
* pin prek to multi-arch index digest ([e10c53f](https://github.com/andykenward/devcontainer-templates/commit/e10c53ff82c297757b5359e04aa646a977d55b32))
* replace process substitution with pipe for POSIX sh compatibility ([295ab43](https://github.com/andykenward/devcontainer-templates/commit/295ab4396a893076af615b87defca711fbb63045))
* run test.sh with bash instead of relying on execute permissions and sudo ([64d177d](https://github.com/andykenward/devcontainer-templates/commit/64d177d4d7edc1db2ff67a5d7b01132313a97c7f))
* use multi-stage build for prek with explicit platform ([4c77ba4](https://github.com/andykenward/devcontainer-templates/commit/4c77ba42272b06301e400af5ee8373075fb26f3d))


### Reverts

* remove intermediate prek-stage to avoid circular dependency ([2f14e43](https://github.com/andykenward/devcontainer-templates/commit/2f14e4395eda49cd8d55aca5c40c19555d88d0fb))
