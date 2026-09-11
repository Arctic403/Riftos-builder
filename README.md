# Riftos-builder

Public GitHub Actions worker for building private `Arctic403/RiftOS` source without consuming Actions minutes in the private source repository.

## Architecture

```text
Editor local workspace
  |
  | one private RiftOS source commit
  v
RiftOS (private source only, zero Actions workflows)
  |
  | Editor workflow_dispatches exact source SHA + client id
  v
Riftos-builder (public Actions worker)
  checkout exact private SHA ephemerally
  source policy checks
  one Android release build
  zipalign + APK signing
  APK/package/runtime verification
  provenance + SHA-256 manifest
  |
  | private prerelease tagged to exact source SHA
  v
RiftOS (private prereleases)
  |
  | Editor resolves source SHA + client id
  v
Local device
```

The public worker contains orchestration only. RiftOS product source is never committed into this repository and `actions/upload-artifact` is intentionally not used for private builds. GitHub-hosted runner storage is ephemeral.

## Required secret

Configure this repository secret before the first private build:

- `RIFTOS_PRIVATE_TOKEN` — fine-grained PAT restricted to `Arctic403/RiftOS`, with **Contents read/write**. It is used to resolve/check out the exact private source commit and create private RiftOS prereleases/assets.

The token should not grant write access to `Riftos-builder` itself.

## Optional production-signing secrets

If these are not configured, the worker uses RiftOS's existing alpha/debug keystore embedded in the private source tree:

- `RIFTOS_KEYSTORE_B64`
- `RIFTOS_KEYSTORE_PASSWORD`
- `RIFTOS_KEY_ALIAS`
- `RIFTOS_KEY_PASSWORD`

If production signing is enabled, configure all four together.

## Editor PAT permissions

The PAT entered into `Arctic403/Editor` needs:

- `Arctic403/RiftOS`: **Contents read/write** — push the local source snapshot and read/download private build releases.
- `Arctic403/Riftos-builder`: **Actions read/write** — dispatch `.github/workflows/riftos-worker.yml`.

The Editor does not need source write access to `Riftos-builder`.

## Worker workflow

`.github/workflows/riftos-worker.yml` is `workflow_dispatch` only and accepts:

- `source_ref` — exact RiftOS branch/tag/SHA.
- `client_id` — optional Editor/local correlation id.
- `publish` — return success/failure outputs to a private RiftOS prerelease.

The worker resolves `source_ref` to an immutable SHA before checkout. Successful releases contain:

- `RiftOS-Android-debug.apk`
- `RiftOS-verification-<sha>.zip`
- `build-manifest.json`
- `provenance.txt`
- `sha256sums.txt`

Failure runs return a private `RiftOS-worker-failure-<sha>.zip` when publishing is enabled.

## Source-repository policy

RiftOS is intended to become an Actions-free private source repository, matching the Vortex3D/VTXBuilder model. The Editor-side RiftOS build controller explicitly excludes/deletes `.github/workflows/` when synchronizing RiftOS source. The worker also refuses a source commit that still contains workflow files, preventing accidental private-repo Actions from creeping back into the build path.

Public workflow logs deliberately contain only coarse build-stage status where practical. Detailed build/verification logs are captured and returned through the private RiftOS release channel instead.

## Source validation

The worker owns its build checks. It validates the native MCP runtime plus the narrow
ChatGPT JavaScript connector that routes only MCP initialization, tool discovery, and tool calls.
The connector contains no tool implementation, remote relay, or direct model API path.
Run `bash tests/test-riftos-source-check.sh` to exercise the source-policy regressions.
