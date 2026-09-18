# Riftos-builder

Public GitHub Actions worker for building the private `Arctic403/RiftOS` Android source.

The Editor manually dispatches `.github/workflows/riftos-worker.yml` with an exact RiftOS
source ref. The worker resolves that ref to a commit SHA, builds and signs the APK, then
publishes `RiftOS-Android-debug.apk` to a private RiftOS prerelease.

Builds remain `workflow_dispatch` only. The builder does not duplicate RiftOS product tests;
it runs the validation suite owned by the exact RiftOS source commit and adds artifact-level
checks that only the builder can perform. The workflow uses current Node-24-capable GitHub
Actions (`actions/checkout@v7`, `actions/setup-java@v5`, `gradle/actions/setup-gradle@v6`); the
Gradle action uses its open-source `basic` cache provider so this maintenance update does not
change the builder's trust boundary.

## Build gates

A build must pass all of these stages before publication:

1. Resolve the requested RiftOS ref to an exact commit SHA, verify `HEAD` matches it, and require the checked-out working tree to remain byte-clean (no tracked drift or untracked files) before source validation.
2. Preflight the Builder's own DEX-verifier assumption against RiftOS's exact mandatory Kotlin source list: every listed filename must exist and declare a matching top-level class/object/interface, otherwise the Builder fails early as stale instead of waiting for final APK smoke.
3. Run RiftOS `npm run check` so its wiring, transport, docs, protocol, native/live and explicitly retained-reference regressions gate the APK.
4. Compile the Android release APK with Gradle.
5. Align and sign the APK.
6. Verify zip alignment and the APK signature/certificate.
7. Run `scripts/verify-riftos-apk.sh` against the **final signed APK**.

The APK smoke gate verifies the Android payload exists and that the only OS-execution files under `assets/www/` are the exact byte-for-byte `src/riftpp-core.js` and `src/riftvm.js` headless assets. Any returned `index.html`, `styles.css`, `workspace-live/`, PWA/service-worker file, or other unexpected `assets/www/` content is a failure. Explicit runtime assets under `android/app/src/main/assets/` (including RiftBrowser adapters) are verified separately byte-for-byte.

Because important RiftOS fixes can live entirely in Kotlin, the final signed-APK gate derives
its required top-level native class descriptors from RiftOS's own
`android/app/build.gradle.kts` `verifyRiftOsAndroidSources` contract and requires every one in
the packaged DEX files. That now automatically covers current native surfaces such as
`MainActivity`, `RiftBrowserAppHost`, `RiftVolumePaths` and every other file in the current mandatory native snapshot without a second Builder list drifting behind the source contract. The private top-level
`RiftDevLabLocalAgent` object remains an explicit extra provenance assertion because it lives
inside `RiftVortexLocalAgent.kt`. The exact `SOURCE_SHA` compiled into runtime diagnostics must
also survive into DEX. This closes the gap where Web assets could match source while the final
native payload or provenance was not independently asserted.

The worker builds a **Git commit** from `Arctic403/RiftOS`, not the phone's local
`workspace/RiftOS-main` directory. Push RiftOS workspace changes to the RiftOS repository
before dispatching a build, then use the intended commit as `source_ref`. Dispatch remains
manual; updating either workspace does not start a build or publish an APK.

Failure logs are kept in `$RUNNER_TEMP/riftos-private-logs` and are returned through the private
RiftOS prerelease failure bundle when publication is enabled. This separates source-validation,
Android compile, APK packaging, alignment, signature, and private-release publication failures.
The publish stage creates the private prerelease first, then uploads the verified APK with up to
three bounded retries. `publish.log` captures GitHub CLI output, and a failed asset upload removes
the half-created release/tag before the private failure bundle is returned.

## Required secret

- `RIFTOS_PRIVATE_TOKEN` — fine-grained PAT restricted to `Arctic403/RiftOS` with
  Contents read/write.

Optional production-signing secrets:

- `RIFTOS_KEYSTORE_B64`
- `RIFTOS_KEYSTORE_PASSWORD`
- `RIFTOS_KEY_ALIAS`
- `RIFTOS_KEY_PASSWORD`

Without those four signing secrets, the worker uses RiftOS's alpha/debug keystore with the known development alias/password. That fallback is suitable only as an alpha/development signing identity and is not strong production publisher identity. A production distribution policy should require private release signing and remove the fallback separately.

The workflow currently references major-version GitHub Action tags rather than immutable action commit SHAs; that remains an external supply-chain/reproducibility limitation.

Builds never use `actions/upload-artifact`.
