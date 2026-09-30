# Riftos-builder

Public GitHub Actions worker for building the private `Arctic403/RiftOS` Android source.

The Editor manually dispatches `.github/workflows/riftos-worker.yml` with an exact RiftOS
source ref. The worker resolves that ref to a commit SHA, builds and signs the APK, then
publishes `RiftOS-Android-debug.apk` to a private RiftOS prerelease.

Builds remain `workflow_dispatch` only. The builder does not duplicate RiftOS product tests;
it runs the validation suite owned by the exact RiftOS source commit and adds artifact-level
checks that only the builder can perform. The workflow uses Node 24 through `actions/setup-node@v4` and current build actions
(`actions/checkout@v7`, `actions/setup-java@v5`, `gradle/actions/setup-gradle@v6`); the Gradle
action uses its open-source `basic` cache provider so this maintenance update does not change
the builder's trust boundary.

## Build gates

A build must pass all of these stages before publication:

1. Resolve the requested RiftOS ref to an exact commit SHA and check out Builder + RiftOS.
2. Syntax-check both Builder shell scripts with `bash -n`, syntax-check the pinned `prepare-riftbuild-toolchain.py` generator plus its package-layout regression, run that regression against both canonical Termux-prefix and legacy flat-prefix fixtures, verify RiftOS `HEAD` matches the resolved SHA, and require the checked-out source tree to remain byte-clean (no tracked drift or untracked files).
3. Independently run `node --check` on the critical RiftOS source-gate entrypoints before invoking them, including `test-riftbuild-native.mjs`, `test-rift-shell-bridge.mjs`, `test-riftllm-bridge.mjs`, and the three Semnexis source gates (`test-semnexis-bootstrap.mjs`, `test-semnexis-arm32-exec.mjs`, `test-semnexis-shell.mjs`). Builder also requires `package.json` to keep those Semnexis gates plus the wiring, transport, docs, RiftCLI push, retired RiftCLI Batch V2, direct Local Agent batch, persistent MCP operation-journal reconciliation, DebugHub, RiftBuild native, and RiftLLM bridge checks reachable from `npm run check`. The promoted Semnexis v18/v19/v25 fixtures are presence/reference-preflighted before `npm run check`; their actual semantic and ARM32 assertions remain source-owned. See `SEMNEXIS_SELFHOSTING.md`.
4. Preflight Builder assumptions against RiftOS Gradle: root KGP `2.4.10` paired with `quickjs-kt 1.0.14`, namespace/application ID `com.riftos.app`, compile/target Android 36, minSdk 26, Java 17, release minification disabled, `kotlinx-coroutines-android 1.11.0`, pinned NDK `28.2.13676358`, CMake `3.22.1`, ARM64 + ARM32 ABI filters, and every mandatory Kotlin filename declaring a matching top-level class/object/interface. The preflight now also locks RiftBuild Native Compile V1 and generic native-app preparation: `RiftBuildNativeToolchain.kt` + `RiftBuildNativeApp.kt` must remain in the mandatory Gradle source contract, `compile-native`/`toolchain-status`/`toolchain-install-bundled`/`prepare-native-app` must remain wired, compiler execution must remain structured-argv `ProcessBuilder` rather than `/system/bin/sh`, and the bounded toolchain/project/app schemas plus ELF verification, bundled ZIP extraction, `%COMPILER_DIR%`, compiler-local `LD_LIBRARY_PATH`, generated JNI source-set, legacy JNI extraction and `extractNativeLibs=true` contracts must remain present. The same preflight explicitly locks the Codynex C0 editor/provider contract: provider manifest authority/export state, pinned editor signer, strict C0 `0.11.0`/`0.12.0` transition allowlist and bounds, current `.cx` editor compile/preview path, the bounded RiftOs+ `c0-compile` / `c0-run` project host, the R1 `c0-run-host` versioned 24-byte host-snapshot ABI, the R1.1 `c0-run-host-call` bounded request/response turn protocol, and their final-Dex schemas, rejection of obsolete MC2-A active-path markers, and the `codynex_editor_vm` CMake/source payload. Any drift fails explicitly before source tests/Gradle.
5. Run RiftOS `npm run check` so its wiring, transport, docs, protocol, native/live and explicitly retained-reference regressions gate the APK.
6. Generate the bounded RiftBuild Android-host toolchain payload before Gradle: pinned Termux `clang`/`lld` 21.1.8-3 package closures for ARM32 + ARM64 are SHA-verified, extracted executables/libraries are resolved from Termux's canonical `data/data/com.termux/files/usr` package prefix (with the legacy flat `usr` fixture supported only for regression compatibility), runtime ELF dependencies are renamed/patched into private JNI library names, an ABI-matched `libld_lld_shim.so` is compiled to re-exec the renamed bundled LLD with `argv[0] = "ld.lld"`, and the pinned Android NDK `28.2.13676358` sysroot/resource tree is emitted as `assets/riftbuild/android-clang-v1.zip`. Generation is bounded and logged privately.
7. Run the dedicated Gradle validation tasks (`verifyRiftOsAndroidSources`, `validateCodynexCompilerTransition`, and `validateRiftBrowserWebViewOwnership`) and capture them separately in `gradle-validation.log`.
8. Compile/package the Android release APK with Gradle.
9. Align and sign the APK.
10. Verify zip alignment and the APK signature/certificate.
11. Run `scripts/verify-riftos-apk.sh` against the **final signed APK**. The verifier requires `assets/riftbuild/android-clang-v1.zip`, `libclang_exec.so` + `libld_lld_exec.so` + `libld_lld_shim.so` for both `arm64-v8a` and `armeabi-v7a`, compiled `extractNativeLibs=true`, and no x86/x86_64 host-toolchain copies. In addition to deriving every mandatory Kotlin class from RiftOS's Gradle source contract, the final DEX smoke now requires RiftBuild Native Compile V1/generic-native-app command and schema markers (`compile-native`, `toolchain-status`, `prepare-native-app`, structured argv, toolchain/project/app schemas, and `%TOOLCHAIN%`/`%SYSROOT%` expansion) so source-only wiring cannot be mistaken for a live build. The final smoke reads package identity with AAPT2 `packagename`, reads minSdk/targetSdk from the compiled `AndroidManifest.xml` via AAPT2 `xmltree` while accepting AAPT2's decimal or typed-hex rendering of the same numeric value, verifies non-debuggable release state, rejects duplicate/unsafe ZIP entries, leaked source/VCS/keystore material, retired native class descriptors, stale OS web assets, missing mandatory native classes/provenance, and byte-mismatched runtime assets. Builder preflight also requires the native CMake targets `riftcli`, `codynex_mc0_host`, `codynex_mc1a_host`, `codynex_mc1b_host`, `riftpp_app0_host`, and `riftpp_compiler_host` plus their source files before source tests or Gradle compilation begin. Before release compilation, Builder discards CMake/native packaging intermediates and disables Gradle build-cache so native proof/compiler libraries are rebuilt from the resolved RiftOS source rather than reused across worker revisions. Native RiftCLI Bootstrap-0 additionally requires the exact ZIP entries `lib/arm64-v8a/libriftcli.so` and `lib/armeabi-v7a/libriftcli.so` and forbids x86/x86_64 copies. The verifier's `require_entry` helper is literal/exact (not regex). The final APK must also contain the ARM32 proof hosts `lib/armeabi-v7a/libcodynex_mc0_host.so`, `lib/armeabi-v7a/libcodynex_mc1a_host.so`, and `lib/armeabi-v7a/libcodynex_mc1b_host.so`, because native RiftBuild reads those disposable hosts from RiftOS's own APK when preparing the corresponding Codynex machine-proof packages. The generated-runtime Rift++ U0 lane requires both `lib/arm64-v8a/libriftpp_app0_host.so` and `lib/armeabi-v7a/libriftpp_app0_host.so`. The S2 self-host lane separately requires both `lib/arm64-v8a/libriftpp_compiler_host.so` and `lib/armeabi-v7a/libriftpp_compiler_host.so`; missing compiler-host packaging now fails the final signed-APK gate. The app0 libraries are two ABI builds of the same generic VM1/output/NativeActivity runtime source: ARM64 is canonical/default, ARM32 is compatibility, and neither contains application semantics. The Codynex C0 editor path additionally requires the compiled provider manifest authority, exact C0/provider DEX markers, mirrored `com.codynex.editor*` DEX payload, and `lib/armeabi-v7a/libcodynex_editor_vm.so`; missing or stale editor payload fails the final signed-APK gate before publication. The same final DEX smoke gate now requires the fixed `text-encoding-prime-b2` shell route, its frozen B2 source-path/SHA markers, both RiftPack qualification shell aliases and exact Provider methods, the fixed no-argument process-death start/status aliases and `rift_micro_process_death_start` / `rift_micro_process_death_status` Provider methods, the fixed `train-v2-adversarial-start` / `train-v2-adversarial-status` aliases and exact `train_v2_adversarial_start` / `train_v2_adversarial_status` Provider methods, plus the fixed `train-v2-builder-start` / `train-v2-builder-status` aliases and exact `train_v2_builder_start` / `train_v2_builder_status` Provider methods. This proves the bounded RiftPack, process-death, RiftTrainData V2 adversarial, and V2 deterministic-builder qualification bridge surfaces survived compilation.

The APK smoke gate verifies the Android payload exists and that the only OS-execution files under `assets/www/` are the exact byte-for-byte `src/riftpp-core.js`, `src/riftvm.js`, and `src/semnexis-bootstrap.js` headless assets. Any returned `index.html`, `styles.css`, `workspace-live/`, PWA/service-worker file, or other unexpected `assets/www/` content is a failure. Explicit runtime assets under `android/app/src/main/assets/` (including RiftBrowser adapters) are verified separately byte-for-byte. Semnexis self-host fixtures remain source-regression inputs and are intentionally not packaged into the APK; Builder's current promoted source contract is documented in `SEMNEXIS_SELFHOSTING.md`.

Because important RiftOS fixes can live entirely in Kotlin or C++, the final signed-APK gate derives
its required top-level Kotlin class descriptors from RiftOS's own
`android/app/build.gradle.kts` `verifyRiftOsAndroidSources` contract and requires every one in
the packaged DEX files. That now automatically covers current native surfaces such as
`MainActivity`, `RiftBrowserAppHost`, `RiftVolumePaths` and every other file in the current mandatory native snapshot without a second Builder list drifting behind the source contract. The private top-level
`RiftDevLabLocalAgent` object remains an explicit extra provenance assertion because it lives
inside `RiftVortexLocalAgent.kt`. The exact `SOURCE_SHA` compiled into runtime diagnostics must
also survive into DEX. RiftCLI N1.5 additionally requires the final signed DEX to retain the
`riftcli.event-bus` and `mcp.relay` component markers plus `event.created`,
`cli.event.send`, `relay.ready`, `cli.replay.request`, `cli.replay.send` and `cli.ack`.
That proves the specific passive push-diagnostics patch survived compilation rather than merely
proving the containing Kotlin classes exist. This closes the gap where Web assets could match
source while the final native payload or provenance was not independently asserted.

The worker builds a **Git commit** from `Arctic403/RiftOS`, not the phone's local
`workspace/RiftOS-main` directory. Push RiftOS workspace changes to the RiftOS repository
before dispatching a build, then use the intended commit as `source_ref`. Dispatch remains
manual; updating either workspace does not start a build or publish an APK.

Failure logs are kept in `$RUNNER_TEMP/riftos-private-logs` and are returned through the private
RiftOS prerelease failure bundle when publication is enabled. This separates source-validation, dedicated Gradle-validation, Android compile/package, APK smoke, alignment, signature, and private-release publication failures.
The publish stage creates the private prerelease first, then uploads the verified APK with up to
three bounded retries. `publish.log` captures GitHub CLI output, and a failed asset upload removes
the half-created release/tag before the private failure bundle is returned.

## Semnexis self-hosting contract

Builder now has an explicit source-contract document for the Semnexis self-hosting frontier: `SEMNEXIS_SELFHOSTING.md`.

The current RiftOS-promoted source fixtures are v18 frontend, v19 semantic graph, and v25 full canonical graph/verifier/effect/plan/Native-IR parity. The installed `semx` promotion remains `/17` until a newer APK is actually installed and proved. Builder also enforces the current RiftOS runtime-boundary regression: ARM32 must emit and canonically verify a source program with more than 256 functions, proving the retired 256-function bootstrap policy cap has not returned. Real artifact/runtime bounds remain mandatory. Local Semnexis work beyond the promoted fixtures is not claimed by Builder until it is deliberately promoted into RiftOS.

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


