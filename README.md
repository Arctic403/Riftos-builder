# Riftos-builder

Public GitHub Actions worker for building the private `Arctic403/RiftOS` Android source.

The workflow is manual (`workflow_dispatch`). It resolves the requested RiftOS ref to an exact commit SHA, checks out that exact source, runs the source-owned gates, builds the Android release APK, signs the RiftOS APK for distribution, verifies the final signed artifact, and publishes `RiftOS-Android-debug.apk` to the private RiftOS prerelease.

Builder does not own product behavior. RiftOS owns its source tests and platform contracts; Builder adds only checkout, Android build/signing, and final-artifact proof that cannot be performed by source tests alone.

## Frozen build-provider boundary

RiftBuild application semantics are no longer embedded in RiftOS. The device-proven hosted build provider lives outside the RiftOS source tree. RiftOS keeps only generic reusable platform capabilities.

The permanent platform owners are:

- `RiftLocalBuildCapability.kt` — project-confined registered compiler execution for the `build.local` capability. It exposes managed compiler status/run and nothing resembling a build recipe, prepared-tree materializer, APK packer, APK signer, or PackageInstaller.
- `RiftJvmDexService.kt` — bounded JVM class-to-DEX conversion through D8 plus the generic Android/JVM toolchain status consumed by external providers.
- `RiftBuildManagedToolchains.kt` — compiler-id registry for bounded execution engines such as `native-buffer-v1` and isolated `dex-json-v1`.
- `RiftManagedJvmToolService.kt` and `RiftNativeBufferCompilerService.kt` — generic compiler execution engines. They are reusable platform primitives, not language build recipes.
- `RiftBuildPlatformTools.kt` — the narrow platform shell surface: generic compiler status/run, JVM DEX, RAPP pack/install/launch/list, APK verification, and Android install/launch proof.
- `RiftApkV2Verifier.kt` — verification-only APK Signature Scheme v2 parser/verifier. It is keyless and has no signing method.
- `RiftBuildInstaller.kt` — user-confirmed Android PackageInstaller/launch boundary. It accepts a verifier result and does not own APK signing.
- `RiftRappCapabilityBroker.kt` — permission-gated host effects, including `build.local` and `signing.identity`. The private signing key stays in Android Keystore; providers receive only bounded public identity plus generic SHA256withRSA sign/verify operations.

The removed embedded implementations must not return: `RiftBuildLocalExecutor.kt`, `RiftBuildKotlinCompiler.kt`, `RiftBuildNativeToolchain.kt`, `RiftBuildNativeApp.kt`, and `RiftApkV2Signer.kt`. The retired Android-host clang payload generator and its `android-clang-v1.zip`, `libclang_exec.so`, `libld_lld_exec.so`, and `libld_lld_shim.so` payloads are also gone.

The boundary is frozen after device proof. It may be extended only when a real device proof exposes a missing **generic reusable platform capability**. Project-specific convenience routes, compiler-specific RiftOS wrappers, prepared-tree recipes, APK packers, or APK signers do not belong in RiftOS.

## External-provider model

The canonical application pipeline is:

`Compile → Preflight → Pack → Sign → Verify → install/launch proof`

That sequence belongs to the external build provider. RiftOS supplies generic capabilities used by the recipe; it does not own the recipe.

`build.local` is deliberately small: registered compiler execution and JVM DEX conversion. App packaging and signing semantics remain provider-owned. Generic signing is exposed only through `signing.identity`; the provider never receives the Android Keystore private key.

`RiftApkV2Verifier` is retained because Android installation is a platform responsibility and RiftOS must independently verify the signed APK before handing it to PackageInstaller.

Builder signing the **RiftOS release APK itself** is separate from RiftBuild application signing. Release signing in this repository must never be interpreted as permission to restore an embedded app-signing path inside RiftOS.

## RAPP host

RiftOS keeps the language-neutral `riftos-app-abi/1` RAPP boundary. `RiftRappManager` owns package/install/launch state under `/C:/Programs`; immutable installed program data is separated from bounded mutable `state.bin`, which is reloaded as the effective program/state on launch.

`RiftRappHost` owns disposable graphical rendering and UI callbacks. `RiftCoreAppExecutor` owns generic interpreter execution, event-effect chaining and the 1024-effect ceiling; application-context-only `RiftRappCapabilityBroker` enforces Core capability permissions. `RiftCoreShellCapabilityRequests` and `RiftRappShellCapabilityClient` handle only ticketed consent and UI effects. `riftpp-generic-v1` is the forward Rift++ RAPP adapter. Existing RPA/RWS adapters remain compatibility lanes only; new platform behavior must stay language-neutral.

The generic host supports the external provider without containing the provider itself. Provider-specific runtime/manifests/tests belong to the external provider repository.

## Managed compiler lane

Compiler authority remains external to RiftOS recipes. The generic registry can resolve project-owned compiler payloads or validated bundled seeds. The default managed Kotlin compiler is still built as the separate `:rift-managed-kotlin-tool` APK and staged as a compiler seed; RiftOS does not embed the desktop Kotlin compiler implementation.

`.github/workflows/managed-compiler-worker.yml` is the independent compiler-payload lane. The managed compiler worker intentionally uses `actions/upload-artifact@v4` to return compiler payload artifacts. The main RiftOS APK worker does not use `actions/upload-artifact`; the finished RiftOS APK is published through the release path.

Long generic compiler operations use persistent RiftShell jobs. `rift_shell_exec` auto-submits supported long operations such as `compiler-run` and `jvm-dex`, with bounded submit/status/result/cancel/list lifecycle. Retired `kotlin-compile`, native clang compile/prep, embedded `pack`, and embedded `sign` commands are not part of the live shell surface.

**B2-B live-device follow-up, 2026-10-08:** RiftOS source `174f0144` compiled, installed and passed real RAPP UI-effect window title plus fs.read/fs.write Allow with Core results and independently read written data; denying fs.read and fs.write also returned denied Core results, and update revoked the previous grants. Android Back unexpectedly detached the test app during an attempted Cancel, making that specific in-session edge unproven. The next source change adds a visible neutral Cancel button to the generic RiftShell consent dialog; Builder source checks now enforce both explicit Cancel and the existing dialog cancellation listener. The user's **manual** Builder and device Cancel test remain mandatory before promoting that edge. No shell-process isolation/headless assertion is implied.

## C1.2-B2-B1 Core focus lease (new source gate)

The prior B2-A user-installed RiftOS source `e13c5bfe`, run #639, accepted ACTION node 10 and TEXT_INPUT node 20 (`B2A_TEST`), persisted both through subsequent actions and cleanly uninstalled the disposable RAPP (three original apps intact, zero sessions/surfaces). This new source-only slice adds `RiftCoreInputFocus.kt`: Core-verified attached-app focus identity/generation, monotonic revision, revocation on attach/detach/close/update/uninstall. RiftNativeDesktop reports foreground changes via a callback; MainActivity relays focus requests to Core without Core importing desktop UI. The Builder checks mandatory Kotlin source, focus/lease schema, shell notifier/CLI, and final signed DEX marker. No automatic build. The user must manually build and prove `core focus` registration, switching to system/native window, refocus, and cleanup on a disposable RAPP. Input enforcement is explicitly FALSE in this slice and requires a separate gate; C1.3 shell process isolation remains future work.

## C1.2-B2-A — Generic typed input authorization (source gate)

User's installed RiftOS source `9cf4b46c` (Builder run 638) passed C1.2-B1 Core-snapshot graphical rendering: initial five-node probe window, updated denied `fs.read` token 43 after Cancel with Core revision increment and persisted state, then clean probe uninstall and 3 original apps intact. Next source-only B2-A makes Core validate `ACTION`/`TEXT_INPUT` target IDs against the current typed, generation-matched Core frame, rejects shell-forged internal effect-result events and unsupported runtime-adapter event kinds, and preserves untargeted canvas pointer/global keyboard input. The shell must handle Core input rejection without a View callback crash. Builder preflight/selftests enforce these generic source markers. User must manually run the Builder, then prove RAPP ACTION and text input on a disposable app before B2-A promotion; this is not yet window-focus policy, alternate-shell, headless execution or C1.3 process isolation.

## C1.2-B1 — Graphical renderer as a Core surface client (source gate)

C1.2-A was validated on the user's installed RiftOS source `0dc4c277`, Builder run 637: a disposable RAPP surface appeared with revision 3, advanced to 6 after an actual consent response, disappeared on package replacement, reappeared at revision 9 on relaunch, and disappeared on uninstall. Final Core session/surface count 0, three original apps intact. For C1.2-B1, the existing generic graphical host must fetch immutable `RiftCoreAppSurfaces.snapshot(appId)` after Core execution and reject mismatched attachment generations instead of rendering the direct callback frame. Builder validates the source boundary; next signed APK and device regression are user-manual. This is **not** a shell-independent app execution, focus/input authority or separate shell APK gate.

## C1.2-A Core application surface registry — next manual source gate

Source candidate after C1.1-B2-B user-device PASS. `RiftCoreAppSurfaces.kt` defines generic `riftos.core.app-surfaces/1` immutable frame snapshots, monotonic revisions and bounded in-process subscribers. Core session generation checks control publication; closing, replacing or uninstalling a RAPP clears its surface. Shell CLI `core surfaces` and Core status expose metadata only, not Android Views. Builder requires the Kotlin source in Gradle's exact mandatory list, verifies lifecycle, and requires schema in the final signed DEX.

The user must manually dispatch the next Builder and prove Core surfaces appear/update/disappear with a disposable RAPP before promoting **C1.2-A**. This is not full C1.2: no independent app input/focus authority, shell-less launch, alternate shell client or C1.3 process isolation is claimed. The prior RiftOS `60fb0e7`/Builder `88b4c10` manual build and on-device Cancel test passed, and the original three RAPPs were restored; the new source is not yet installed.

## C1.1-B2-B Core capability and shell consent contracts

Source candidate only until the user runs the manual Builder and proves it on-device. The signed RiftOS APK must contain the versioned `riftos.core.capability-consent/1` and `riftos.core.ui-effect/1` protocols, as well as `RiftCoreShellCapabilityRequests.kt` and `RiftRappShellCapabilityClient.kt` in the exact Kotlin source snapshot. The broker must not import Android Activity/desktop classes; the shell cannot persist grants. Core effect chaining uses bounded tickets and checks the attached app generation. Consent dialogues must reject late/closed/detached replies. Current Core and desktop remain in the same process; headless execution and shell crash survival are not yet proven.

**2026-10-08 failed-worker fix:** The first C1.1-B2-B manual Builder compiled Kotlin, assembled the release APK and verified APK Signature Scheme v2 successfully, but failed final `verify-riftos-apk.sh` DEX smoke because it still looked for the retired desktop-owned `RAPP host effect chain exceeded bound` literal. The active Core-owned interpreter emits `RAPP Core effect chain exceeded bound` in `RiftCoreAppExecutor.kt`. Both the signed DEX required marker and `test-builder-contracts.py` must use the Core literal. Do not reintroduce old desktop host code to satisfy a stale APK check; verify the exact current source string and keep the user-only manual workflow.

## C1.1-P Core RAPP installation and uninstallation

C1.1-B2-A is user-confirmed green and installed; read-only live Core diagnostics report five installed RAPPs and the Core event queue. This checkpoint completes the managed `.rapp` lifecycle surface: staged install/update (existing), Core-managed confined uninstall, synchronous grant revocation, session invalidation, versioned package change events and a native graphical Installed Apps client with confirmed deletion. `RiftRappManager` must not depend on `RiftRappHost` for either package changes or launch; it now emits generic `riftos.core.packages.change/1` events and dispatches `riftos.core.app-launch/1` requests, with GUI clients subscribing only for their lifetime. Subscribers may update launcher/windows but cannot own packages. `riftbuild uninstall-rapp <id>` works through generic Core platform APIs even if no desktop window is open. Build preflight checks exact Core files/operations/GUI and signed APK requires schemas/command identifiers.

Uninstall removes package-local program state and revokes grants by default. It refuses non-managed packages and reports cleanup failures explicitly. **No live apps should be uninstalled as part of Builder tests.** C1.1-P awaits a manual green Builder plus user-device proof with a disposable test RAPP. This is not Android APK management, not cross-process shell isolation, and does not claim app survival when Android kills the RiftOS process.

## C1.1-B2-A Core event tickets and FIFO scheduling

C1.1-B1 green installed according to the user and verified through live `core status`/`core sessions`; `eventExecutorOwner=riftos-core`, no active app session. B2-A is the next source checkpoint: `RiftCoreAppSessions` now owns bounded FIFO event state, monotonic tickets and limits (64 pending/1 MiB per session) with attachment generation checks. `RiftRappHost` stores only UI callbacks keyed by Core ticket; shell detach discards outstanding events without deleting installed RAPP opaque program state. Builder rejects UI event queue ownership and signed APK checks `eventQueueOwner`. Consent, effect chaining and UI rendering are not yet headless; the user must manually run Builder and device proof before B2-B.

## C1.1-B1 Core RAPP event execution service

The user confirms the C1.1-A APK build is green and installed; live Core reports five RAPPs and a correctly empty session registry prior to opening apps. C1.1-B1 moves generic interpreter/event/adapter execution, timeouts and persistent state commits from the Activity host into application-scoped `RiftCoreAppExecutor`. Builder now requires this Kotlin source, enforces language-runtime dispatch and Core persistence within it, rejects runtime execution in `RiftRappHost`, and verifies signed DEX markers. The capability broker/UI effects still require the desktop Activity, so no headless application execution is claimed. The next Builder is manually initiated by the user; don't automate it.

## C1.1-A Core RAPP session-state registry

C1.0 manual Builder is reported green/device-installed by user and independently checked on-device (`core status`, `riftbuild runtime-status`, installed app listing). The next source gate introduces `RiftCoreAppSessions.kt`, a process-owned registry with app identity, bounded opaque program state, monotonic event sequence, and generation-checked UI attachments. `RiftRappHost` now delegates those responsibilities to Core, and desktop Activity destruction only detaches the UI client while explicit window close removes the Core session. `core sessions` is a read-only diagnostic; `core status` includes `appSessions`. Builder checks the exact Kotlin source list and signed DEX `riftos.core.sessions/1` schema.

**No over-promotion:** RAPP event execution, effect broker and UI still live in the Activity; detached records do not execute headlessly. `headlessExecution=false` and `appExecutionIndependentOfDesktop=false` are deliberate. This C1.1-A source is awaiting the user's next manual Builder + actual Android install/device proof. Next C1.1-B separates the executor/effects themselves.

## C1.0 RiftOS Core / replaceable RiftShell boundary

**Baseline:** User confirmed C0.2.5 Builder green and installed on actual Android device, 2026-10-08.

This source gate makes `RiftCoreApplication` bootstrap application-scoped Core authority before the desktop. `RiftCoreRuntime` owns the shared RAPP package manager, external runtime-provider registry and generic RiftBuild service; `RiftNativeShell` and the Activity-owned RAPP UI host become Core clients for those functions. The signed APK must retain the Core Application entry and `riftos.core.status/1`. The `core status` shell command is an Activity-independent diagnostic.

**Do not over-promote:** Core and desktop still share the same Android process, and RAPP execution/rendering sessions remain Activity-owned. Shell crash/process isolation and replaceable shell package are later C1 gates. The user's NEXT manual Builder + device installation must verify this gate; Builder must never be triggered automatically. Architecture owned by `RiftOS-main/docs/systems/core-shell/README.md`.

## C0.2.5 external runtime-provider migration

RiftOS now sources the generic `RiftExternalRuntimeProviders` registry and signer-pinned Binder execution boundary; the external installed package advertises `com.riftos.runtime.EXECUTE_V1`. Builder requires source, Gradle reachability, manifest query visibility and final signed-DEX proof. Runtime provider registration is a separate platform installation gate, not language-specific Builder logic. `riftbuild runtime-status` is the read-only diagnostic.

**Important:** This is migration gate A only. Standalone QuickJS provider APK/installation, external shell runtime migration and deleting `quickjs-kt` from the OS APK have NOT been promoted. The existing RAPP fallback and compiler tooling remain for the next manual device build. No independent provider is marked ready without a pinned signer certificate.

## Rift++ editor boundary

**C0.2:** RiftOS no longer compiles or packages mirrored Rift++ and Codynex editor classes or their native JNI bridges. Builder enforces absence of those project-specific Kotlin sources, Gradle SHA-lock tasks, DEX descriptors and libraries. The standalone Rift++ editor remains independently maintained and owns its canonical compile → preflight → pack/sign pipeline; this cleanup does not modify that editor.

Fixed project editor Binder package visibility was removed from the RiftOS manifest. Generic RiftBuild APK install/launch derives the target package from verified artifacts; no hardcoded external editor package identity is allowed. Source/Gradle/DEX/ABI absence checks were added without dropping generic platform compilation, signing or app-host verification.

The compatibility/reference `riftpp` developer shell remains a headless QuickJS surface and is source-gated by `test-riftpp-shell.mjs`. It is separate from the promoted external build-provider boundary.

## Build gates

A RiftOS publication must pass, in order:

1. Resolve the requested RiftOS ref to an exact SHA and verify the checkout is byte-clean.
2. Syntax-check Builder shell/Python gates and run `scripts/test-builder-contracts.py`.
3. Syntax-check critical RiftOS source-gate entrypoints and run RiftOS `npm run check`.
4. Preflight the Gradle source contract. The promoted generic build-provider owners above must be mandatory sources, and the retired embedded build files must be absent.
5. Run the dedicated Gradle validation tasks before release compilation, including `verifyRiftOsAndroidSources`, editor payload validation, and browser ownership validation.
6. Remove stale native/CMake intermediates so native libraries are rebuilt from the resolved source.
7. Compile/package the RiftOS Android release APK.
8. Align and sign the RiftOS release APK with the release identity supplied to the worker.
9. Verify alignment plus APK signature/certificate.
10. Run `scripts/verify-riftos-apk.sh` against the final signed APK.
11. Publish only after every source and artifact gate is green.

There is no pre-Gradle RiftBuild clang-toolchain generation stage anymore.

## Final signed-APK proof

The final verifier derives mandatory Kotlin owners from RiftOS's Gradle source contract and proves they survived compilation. For the promoted build-provider boundary it requires markers for:

- managed compiler execution (`riftbuild-managed-compiler-run/1`);
- generic JVM toolchain/D8 (`riftbuild-kotlin-toolchain-status/2`, `rift-jvm-dex/1`);
- surviving platform commands (`compiler-status`, `compiler-run`, `jvm-status`, `jvm-dex`, `pack-rapp`, `install-rapp`, `launch-rapp`, `rapp-list`);
- generic RAPP ABI/capabilities, durable `state.bin`, permission state, `build.local`, and `signing.identity`;
- APK-v2 verification behavior;
- persistent RiftShell jobs;
- the current single Rift++ editor and retained headless QuickJS compatibility surface.

The verifier rejects the removed clang ZIP/JNI payloads and retired embedded native compile, native app preparation, runtime-profile, project-toolchain, and app-signing markers. It also keeps the existing security checks for unsafe/duplicate ZIP entries, leaked source/VCS/keystore material, package/minSdk/targetSdk/debuggable state, required native libraries, and exact runtime asset provenance.

The generic managed-compiler lane still requires the Android/JVM toolchain assets, validated compiler seed, `RiftNativeBufferCompilerService`, and ARM native-buffer compiler hosts. Those are generic execution capabilities and are not the retired Android-host clang toolchain.

## Failure policy

Builder is stop-on-error. A failed source gate, Gradle validation, compilation, signing step, or final APK proof blocks publication. Sparse worker failure bundles are diagnostic pointers only; the private detailed Builder logs are the source of truth for the actual failure.

Do not weaken a gate merely to make a build green. If a real device proof exposes a missing generic boundary, extend the reusable platform capability, prove it, update the source/final-APK contracts, and keep provider semantics external.
