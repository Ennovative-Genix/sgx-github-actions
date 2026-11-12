# Changelog

All notable changes to this project will be documented in this file.

## [1.1.0-AI] - 2026-11-12

### Added

- [AI] `init.yml` promote path: `skip_build` + digest-pinned `image` inputs, `resolve-image` job, and cross-region ECR copy via crane (e.g. QA `ap-south-1` → STG/PROD `us-east-1`).
- [AI] Nova frontend Helm `extraEnv.NOVA_SHOW_RESPONSE_TIME` on base/dev/qa/stg values for runtime `assets/config.json` (promotable UI image).

### Changed

- [AI] Deploy jobs consume `resolve-image` output so the same immutable digest can be deployed without rebuilding.
