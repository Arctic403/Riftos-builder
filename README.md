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

1. Resolve the requested RiftOS ref to an exact commit SHA and check out Builder + RiftOS.
2. Syntax-check both Builder shell scripts with `bash -n`, verify RiftOS `HEAD` matches the resolved SHA, and require the checked-out source tree to remain byte-clean (no tracked drift or untracked files).
3. Preflight Builder assumptions against RiftOS Gradle: root KGP `2.4.10` paired with `quickjs-kt 1.0.14`, namespace/application ID `com.riftos.app`, compile/target Android 36, minSdk 26, Java 17, release minification disabled, `kotlinx-coroutines-android 1.11.0`, and every mandatory Kotlin filename declaring a matching top-level class/object/interface. Any drift fails explicitly as a stale Builder contract before source tests/Gradle.
4. Run RiftOS `npm run check` so its wiring, transport, docs, protocol, native/live and explicitly retained-reference regressions gate the APK.
5. Run the dedicated Gradle validation tasks (`verifyRiftOsAndroidSources` and `validateRiftBrowserWebViewOwnership`) and capture them separately in `gradle-validation.log`.
6. Compile/package the Android release APK with Gradle.
7. Align and sign the APK.
8. Verify zip alignment and the APK signature/certificate.
9. Run `scripts/verify-riftos-apk.sh` against the **final signed APK**. The final smoke reads package identity with AAPT2 `packagename`, reads minSdk/targetSdk from the compiled `AndroidManifest.xml` via AAPT2 `xmltree` while accepting AAPT2's decimal or typed-hex rendering of the same numeric value, verifies non-debuggable release state, rejects duplicate/unsafe ZIP entries, leaked source/VCS/keystore material, retired native class descriptors, stale OS web assets, missing mandatory native classes/provenance, and byte-mismatched runtime assets.

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
RiftOS prerelease failure bundle when publication is enabled. This separates source-validation, dedicated Gradle-validation, Android compile/package, APK smoke, alignment, signature, and private-release publication failures.
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

## Rift Clang payload proof

The builder also contains a separate manual `Rift Clang Payload Proof` workflow. It is not part of normal RiftOS APK builds.

It pins:
- LLVM 23.1.1;
- Android NDK r30 / 30.0.16248370;
- Android API 26;
- ARM + AArch64 LLVM backends only.

The payload workflow builds native host TableGen tools first, then cross-compiles Clang + LLD for the selected Android host ABI using the NDK CMake toolchain. It strips the two executables, renames them to Android-packageable `libriftclang.so` / `libriftlld.so`, stages the matching NDK sysroot target tree and Clang resource headers, and writes a deterministic manifest/hash set.

Publication is opt-in. The normal RiftOS worker does not consume a payload until a later pin-by-hash integration gate is implemented and device proof passes.

