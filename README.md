# Riftos-builder

Public GitHub Actions worker for building the private `Arctic403/RiftOS` Android source.

The Editor manually dispatches `.github/workflows/riftos-worker.yml` with an exact RiftOS
source ref. The worker resolves that ref to a commit SHA, builds and signs the APK, then
publishes `RiftOS-Android-debug.apk` to a private RiftOS prerelease.

Builds remain `workflow_dispatch` only. The builder does not duplicate RiftOS product tests;
it runs the validation suite owned by the exact RiftOS source commit and adds artifact-level
checks that only the builder can perform.

## Build gates

A build must pass all of these stages before publication:

1. Resolve the requested RiftOS ref to an exact commit SHA, verify `HEAD` matches it, and require the checked-out working tree to remain byte-clean (no tracked drift or untracked files) before source validation.
2. Run RiftOS `npm run check` so its wiring, transport, docs, protocol, shell/Git and app-import regressions gate the APK.
3. Compile the Android release APK with Gradle.
4. Align and sign the APK.
5. Verify zip alignment and the APK signature/certificate.
6. Run `scripts/verify-riftos-apk.sh` against the **final signed APK**.

The APK smoke gate verifies the Android payload exists, every packaged RiftOS `src/`
and `workspace-live/` file—including the desktop taskbar and local Records changes—matches
the checked-out source byte-for-byte, and no stale `assets/www/` files slipped in. It also
verifies every runtime native asset under `android/app/src/main/assets/` (including new
adapters), rejects retired PWA/service-worker packaging and the removed Rift AI cockpit CSS,
and checks that the packaged workspace surface is the current Workspace Records UI.

Because important RiftOS fixes can live entirely in Kotlin, the final signed-APK gate also
scans all packaged DEX files for the core native RiftOS classes (`MainActivity`, native desktop,
local UI agent, structured Dev Lab agent, shell bridge/runtime and tool host) and for the exact `SOURCE_SHA` compiled into
RiftOS runtime diagnostics. This closes the gap where Web assets could match source while the
final native payload or provenance was not independently asserted.

The worker builds a **Git commit** from `Arctic403/RiftOS`, not the phone's local
`workspace/RiftOS-main` directory. Push RiftOS workspace changes to the RiftOS repository
before dispatching a build, then use the intended commit as `source_ref`. Dispatch remains
manual; updating either workspace does not start a build or publish an APK.

Failure logs are kept in `$RUNNER_TEMP/riftos-private-logs` and are returned through the private
RiftOS prerelease failure bundle when publication is enabled. This separates source-validation,
Android compile, APK packaging, alignment and signature failures.

## Required secret

- `RIFTOS_PRIVATE_TOKEN` — fine-grained PAT restricted to `Arctic403/RiftOS` with
  Contents read/write.

Optional production-signing secrets:

- `RIFTOS_KEYSTORE_B64`
- `RIFTOS_KEYSTORE_PASSWORD`
- `RIFTOS_KEY_ALIAS`
- `RIFTOS_KEY_PASSWORD`

Without those four signing secrets, the worker uses RiftOS's alpha/debug keystore.
Builds never use `actions/upload-artifact`.
