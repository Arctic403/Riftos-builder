# Riftos-builder

## 2026-10-09 — C1.3-E bounded real graphical RiftShell recovery SOURCE ONLY; user manual build/device next

Last installed hardware-proven gate **C1.3-D user-manual signed Builder #660**, executable `d43a30e`. New E source requires Core-owned `RiftCoreShellRecovery` default process watchdog, bounded heartbeat/process death verification/retry budget, authenticated `shell.recovery.claim` snapshot before new shell desktop reports, Core no-BOOT original-generation `shell.reattach`, native clamped geometry/window reconstruction, normal Android background suppression, and a guarded **disposable RAPP only** actual production `:riftShell` PID-death QA hook. Builder `scripts/riftos-build.sh` source preflight, `scripts/test-builder-contracts.py` selftests, and `scripts/verify-riftos-apk.sh` signed DEX `riftos.core.shell-recovery/1` are updated, and RiftOS source/Gradle/docs owners synchronized. The **existing manual Builder/pack/sign/verify workflow is unchanged**.

**Not built/device-proven yet.** User alone triggers next Builder; if green, installs and proves actual old/new production `:riftShell` PID after process death, same Core PID and disposable RAPP generation/text/surface, automatic desktop/window restoration without launching RiftOS manually, new interactive ACTION/TEXT_INPUT, and clean disposable uninstall, all four protected RAPPs untouched. Android background Activity launch restrictions may block automatic recovery; a manual reopen, hidden read-only `:riftShellProbe` crash or Android Activity recreation is NOT E proof. If blocked, diagnose and patch before E promotion; preserve C1.3-D's independent device pass.


## 2026-10-09 — C1.3-D DEVICE PASS on signed installed Builder #660; C1.3-E separate later

**User-manual Builder #660**, run `37891844448`, installed RiftOS executable `d43a30e29ae2d98abbcf7a54ccbe9a8841613e55`. Android proved Core PID25396 and actual production graphical `:riftShell` PID25436 distinct. Remote Installed Apps lists four preserved RAPPs, native Files and browser WebView work, disposable Core-owned RAPP gen1 rendered/action+TEXT_INPUT `C13D_660_REMOTE` via remote shell and cleaned through generation-bound GUI close/stop and uninstall. The **final acceptance** was user's manual native graphical RiftShell terminal screenshot showing entered `ps` and real process/task output: protected kernel, protected desktop, protected shell, focused terminal. Post-screenshot native `ps` reports same remote shell PID, clean Core RAPP state confirmed. **C1.3-D fully DEVICE PASS / PROMOTED.** This is a docs-only sign-off; no changes to Builder dispatch/pack/sign, and NO additional build needed for D. Four original RAPPs (`rapp-notepad`, `rift-os-native`, `riftbuild-hosted`, `riftpp-compiler-lab`) untouched.

**C1.3-E NOT STARTED**: independent source gate and separate user-manual signed Builder for actual production shell crash/restart plus automatic graphical reconstruction with Core and Core-running RAPP still alive. Do not claim those properties from #660's D proof.


## 2026-10-09 — manual signed Builder #660 GREEN LIVE: C1.3-D real process split/IPC functional, native terminal smoke pending

User manually built and installed RiftOS executable source `d43a30e29ae2d98abbcf7a54ccbe9a8841613e55` through **Builder #660** run `37891844448`. Real device Core PID25396 and graphical production :riftShell PID25436 distinct; remote Installed Apps read all four protected original RAPPs, Core ps exposed PID/window state. Native Files and RiftBrowser WebView windows rendered. Verified disposable Core-only RAPP gen1 reattached through remote graphical window without duplicate BOOT, real ACTION and TEXT_INPUT `C13D_660_REMOTE` committed, Core surface rev6; Core RAPP stopped on actual remote GUI close, and uninstall cleaned runtime; all four originals preserved. This resolves #659 Core Binder auth failure; **no further build needed for these proven properties**.

C1.3-D held short of full promotion only for manual native RiftShell terminal Core-command execution: window opens but Local Agent could not focus editable command field; user must type `ps` and screenshot result. No automatic Worker, no code changes for an unproven keyboard-agent limitation, no C1.3-E process-kill/auto-recovery.


## 2026-10-09 — signed manual Builder #659 device Core IPC auth failure, source follow-up

User manually compiled/installed #659 run 37889666166 RiftOS bd6e0b13. Actual remote desktop UI exists, but Installed Apps says 'Core IPC caller is not the production RiftShell process'; Core pid 22863, native ps remote shell PID null. D DEVICE FAIL/PARTIAL, though Android signed build is green. Four installed protected RAPPs, including Rift++ Compiler Lab, untouched. Android /proc cross-process cmdline read may be restricted. Core provider now checks Android ActivityManager process registry for exact Binder UID, PID and production ':riftShell' process name; if no record, strict /proc name fallback remains. No UID-only access or riftShellProbe mutation. Builder source guard and selftest updated. USER ONLY next manual compile/pack/sign/install; no automated Worker. C1.3-E untouched.


## 2026-10-09 — C1.3-D manual Builder #3: source-documentation ledger repaired

User-manual Worker run `37888463412` on RiftOS input source `b9b708a1d4fa7de26166deafe2cc76408209e1b3` successfully passed native wiring and transport validation after the prior WebKit fix, then failed **`scripts/validate-rift-docs.mjs`** because eight new C1.3-D source files were missing from `docs/SOURCE_OWNERSHIP.md`. RiftOS now registers all eight separate-process Shell/Core IPC files under their appropriate existing documentation owners; source validator and Builder runtime/build scripts remain unchanged for this failure. Focused check verified eight unique ledger entries. This run stopped before Gradle compile, signing or real installed D device proof. **No changes to the normal user-manual Builder/pack/sign/verify flow.** User manually starts the next Builder after synchronized heads are pushed; C1.3-E remains unstarted.


## C1.3-D second manual Builder RED — RiftBrowser WebKit owner repair (2026-10-09)

User-manual Builder run `37887642001` cleared the prior C1.3-D validator initialization failure, then stopped with `WebKit ownership escaped RiftBrowser: android/app/src/main/java/com/riftos/app/RiftCoreApplication.kt`. The remote Android process needs a dedicated WebView data-directory suffix, but the WebKit API may only be owned by existing `RiftBrowser*` sources. The C1.3-D patch now has Core `Application.onCreate` detect actual `:riftShell` (API 28+) and call `RiftBrowserWindow.prepareRemoteShellWebViewDirectory()`; `RiftBrowserWindow.kt` performs `WebView.setDataDirectorySuffix("riftShell")` before WebView construction. No Core-side `android.webkit` import or expanded ownership allowlist. Builder source guards and self-tests check both halves, alongside the unchanged original Gradle owner gate. Focused 14/14 and JS parse checks passed; the next full build is **USER-MANUAL ONLY**, and C1.3-D remains not installed/device-proven. C1.3-E not started.


## C1.3-D initial source-gate failure and correction (2026-10-09)

User-manual Builder run `37886597455` / source `edb53286a09c90d79493417de2ca8e07df8a46a1` failed in `npm run check:transport` at `validate-rift-wiring.mjs:721`: `ReferenceError: Cannot access 'rappManager' before initialization`. The real source error is in RiftOS validator ordering, which now places `rappManager` and `nativeSystemApps` declarations before C1.3-D checks. Two ancillary Builder preflight `grep -E` patterns also carried double backslashes before literal `(` and emitted `grep: Unmatched (`; those are corrected to one backslash in `scripts/riftos-build.sh`. This failed run never reached Kotlin/Gradle, signing or an installed C1.3-D APK. Do NOT alter the user-manual Builder dispatch flow; next manual run should test corrected source and Builder HEAD together, report any next first failure, and only after green signed install begin D device proof. C1.3-E stays untouched.


## 2026-10-09 — C1.3-D production separate-process RiftShell SOURCE CANDIDATE (not built/device-proven)

Last device-promoted gate is **C1.3-C**, user-manual signed Builder #655/RiftOS source `8d7608f`. RiftOS C1.3-D source replaces the actual Android launcher with `RiftShellActivity` in `:riftShell`, hosting `RiftNativeDesktop` taskbar/window manager and browser/native app/RAPP rendering. Generic RAPP BOOT, session generation, state, events, Core capability grants and execution remain in the default Android Core process; `RiftCoreSurfaceIpcProvider` authenticates exact same-UID named shell PID and exposes bounded versioned Binder operations. Remote shell consumes immutable frames, offers generation-bound input and shows Core-issued, single-use permission/effect UI tickets. The source includes native terminal/install delegation, a bounded Core-first app-launch queue, Core read-only remote window state for MCP `ps` and typed `open/kill/browser` commands, Core-owned MCP relay bootstrap, a separate WebView process data directory, and native workspace watcher. The remote `:riftShellProbe` is still read-only and **not** the actual desktop.

Builder `scripts/riftos-build.sh` enforces these manifest/Gradle/source boundaries before build and `scripts/verify-riftos-apk.sh` requires four C1.3-D IPC schema strings in signed APK DEX. **Nothing in this entry indicates a green or installed C1.3-D build yet.** User alone triggers the normal Builder, installs and verifies source SHA, then separately device-proves real distinct Core/production shell PIDs, graphical desktop/system tools, disposable Core RAPP same-gen ACTION/TEXT_INPUT and cleanup with original three preserved. **C1.3-E real shell crash/restart and auto reconstruction is NOT part of D.** Existing Builder/manual signing/packaging must remain unchanged.


## 2026-10-09 — C1.3-C DEVICE PASS (#655), C1.3-D next independent manual build

The user manually built and installed RiftOS source `8d7608f67e1551a0c774b12d4d89edec61fb6629` via existing Builder **#655**, run `37882347339`. Installed source SHA matched. Disposable RAPP Core-only BOOT gen1/surface rev1, same-gen GUI attach, guarded Android `MainActivity.recreate()` preserved Core PID7528, Core session/gen1 and frame rev3. User manual screenshot demonstrated ACTION count2 and `C13C_MANUAL_655` typed input after recreation; independent Core subscriber later confirmed persisted input/action and surface revision50 on the same gen1. Stable background Core input focus became null; Core stop + uninstall cleaned all RAPP state, original three applications intact. **C1.3-C DEVICE PASS**. Builder's manual workflow and signing/packaging remain unchanged. **C1.3-D NEXT**, but requires its own source/Builder/desktop-process IPC ownership contract and separate user-built APK/device proof. C1.3-E later. The previous C1.3-C #654 focus defect, #655 follow-up and source-only candidate notes below are history.


## C1.3-C #654 device PARTIAL PASS — pending focus and Activity recreation follow-up

User-manual Builder #654/run 37880614808 signed source 130dea17 installed. Core PID 4542, disposable RAPP Core-booted independently, GUI reused same generation with real ACTION and TEXT_INPUT, and all Core state cleaned after explicit close/uninstall; original three survived. **Not full C1.3-C:** Android Back left GUI subscriber and Core focus lease active while backgrounded, and no actual MainActivity destroy/recreate was proved. Next C1.3-C source gates focus requests on Android foreground, revokes pause/blur leases, safely restores visible focus, and adds guarded QA-only Local Agent Dev Lab `recreate-main-activity-proof` for a live disposable RAPP. Builder source and final DEX contract `riftos.qa.activity-recreate/1` require these. User dispatches next manual Builder and real-device acceptance. C1.3-D/E remain untouched.


## 2026-10-08 — C1.3-C Core RAPP execution independent of desktop (SOURCE CANDIDATE; DEVICE PENDING)

The user superseded the earlier combined C1.3-C/D/E migration with **three separately implemented and device-proven gates**. C1.3-C is the only active implementation; C1.3-D (production RiftShell separate process) and C1.3-E (automatic real-shell restart/reconstruction) are not started. RiftOS baseline: `100d0cde`, Builder baseline: `486e2388`, last physically installed and verified source: `31f4a8d4` from manual Builder #653. Existing pre-change archives in `workspace/AI-Handoffs/Backups/` must be preserved.

C1.3-C source moves both graphical and Core-only RAPP BOOT, bounded queued events, focus revalidation and `executeChained` dispatch into process-owned `RiftCoreAppLifecycle`. Generic `RiftRappManager.launch(id)` must start the installed program in Core even when no graphical host exists and only then optionally dispatch `RiftCoreAppLaunchRequests` for presentation; `core-running` is a valid shell-less launch state. `RiftRappHost` is now an immutable `RiftCoreAppSurfaces` observer and an input requester carrying the current Core generation, not an execution/session/effect owner. `MainActivity` does not forward RAPP resume/pause or close Core sessions on ordinary Activity teardown; only the focus lease is revoked. Explicit window close/stop/uninstall still removes the correct Core session and surface. Source guards and final signed APK DEX markers check Core event-dispatch ownership; Builder tests must reject old host-owned `pendingUiCompletions`, `dispatchCoreEvent`, and GUI `executeChained`.

**Only the user dispatches the existing manual Android Builder.** Before that, source and Builder tests/checks plus coherent local RiftGit commits must pass, and all touched canonical docs/handoff must be synchronized. Device acceptance uses **only a disposable RAPP**: Core-only boot, GUI reattach without duplicate BOOT, typed input/actions and persistent state, Activity destruction/recreation with unchanged Core PID/session/generation, focus revocation/reacquisition, explicit Core stop while a window exists, cleanup/uninstall, and exactly the original `rapp-notepad`, `rift-os-native` and `riftbuild-hosted` intact. Mark C1.3-C DEVICE PASS only after actual signed APK installation and manual device proof. Nothing here claims real RiftShell process separation, external authenticated input IPC, automatic recovery, or Core process-death persistence.


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

## C1.3-B — Isolated remote process death/relaunch DEVICE PASS (#653)

User manually signed/installed RiftOS `31f4a8d4` from Builder #653/`37875375661`. With disposable Core-only RAPP generation1/revision1, separate IPC shell process PID20026 reported Core PID19386 and enabled the exact guarded remote-only termination control. Local Agent activated it, then Core PID19386 and attached RAPP/session/frame survived untouched. New explicit `core ipc-view` launched remote shell PID20077 (new) and rendered same READY frame gen1/rev1 from Core19386 via Binder. Normal viewer close and `core app-stop`/disposable uninstall left Core apps/sessions/surfaces/queues zero, original 3 RAPPs intact. **C1.3-B device PASS for guarded manual probe process loss/recovery**. NOT full RiftShell process separation, automatic reconnect or production IPC authority. Remaining C1.3 must migrate actual desktop shell and prove it can die/reconnect with Core/RAPP continuity.

## C1.3-B — Safe isolated remote process termination SOURCE-only

The separate-process `:riftShellProbe` read-only IPC viewer now includes an explicitly user-triggered test button to self-terminate ONLY its own validated remote Android process; its guard requires a valid current IPC snapshot, a distinct positive Core PID, and exact OS process name match. It is disabled on failure, does not call kill on Core or an arbitrary PID, and retains existing `core ipc-view` relaunch. Builder checks the safeguards; no signed new APK/device test yet. After user manual build, use a disposable Core-only RAPP, open IPC viewer, confirm different Core and remote PIDs, activate remote-only terminate, verify Core PID/app session survived, and launch a new remote IPC viewer with new PID and same Core RAPP frame. Cleanup disposable and verify original 3 apps. This is manual remote-process recovery proof, not automated restart nor full RiftShell process migration.

## C1.3-A — User device PASS (#652); C1.3-B remote process-loss candidate

User manual RiftOS Builder run #652/`37871709393`, signed source `e7ceae80`, verified private Binder IPC with distinct Android PIDs (Core13231 / shell probe15670). Remote Activity rendered disposable Core READY frame gen1/rev1 and later `IPC_C13A` after normal GUI action/text changed the persistent state; remote closing did not stop Core RAPP or normal GUI, second ACTION count2; final cleanup Core zero and original three untouched. **C1.3-A cross-process read-only IPC device PASS**. Remote process termination and rebind are not proven yet. C1.3-B source adds guarded termination *only* of remote proof process; user manually builds and proves Core/session survive death then reopens and receives unchanged Core surface. Neither stage is production independent full RiftShell or full automatic reconnect.

## C1.3-A — Bounded private Core Binder IPC / separate shell proof (source-only)

C1.2-D2 was confirmed on user's manually built RiftOS source `4e8ea83f`, Builder #651/`37867594602`: alternate native viewer displayed READY Core generation 1/revision1; close left Core-only RAPP running; original graphical GUI mutated ACTION/TEXT_INPUT `D2_GRAPHIC`; alternate viewer reopened and showed updated Core frame at revision5, close left original GUI interactive (ACTION count2), window close/uninstall cleaned Core and original 3 installed RAPPs intact.

C1.3-A adds `RiftCoreSurfaceIpcProvider.kt` (non-exported, main process, `riftos.core.surface-ipc/1`) and `RiftRemoteShellProbeActivity.kt` (non-exported **separate Android process `:riftShellProbe`**), using bounded read-only `ContentResolver.call` Binder IPC. The Core endpoint returns an immutable generic Core frame with owner PID, appID, generation, revision, layout and nodes; remote viewer shows distinct Core/shell PIDs and current frame, but cannot mutate app/session/input/focus authority. Command `core ipc-view <id>` dispatches diagnostic client only for an existing Core surface. Builder checks process/manifest and Kotlin/DEX markers. **SOURCE ONLY, no new Android build yet**. USER ONLY builds; next device test starts disposable app Core-only, opens IPC client, verifies **Core PID != Shell PID** and same READY frame, then closes client and confirms Core app stays alive; original GUI can update app, IPC client reopened sees updated frame. This is NOT the production independent RiftShell shell process or crash/reconnect proof.

## C1.2-D2 — Alternate native graphical client user-device PASS (#651)

Manual Builder run #651/`37867594602` on RiftOS `4e8ea83f` was green/installed and the native read-only viewer passed real-device testing: Core-only disposable app start generated READY frame generation 1/revision 1; `core alt-graphic-open` opened independent graphical Activity showing READY, text and action nodes; closing left Core session active. Normal GUI launcher attached the same Core generation, persisted ACTION count 1 and TEXT_INPUT D2_GRAPHIC. Reopened alternate viewer reflected the updated Core frame (gen1, revision5), closing viewer left main GUI fully usable (ACTION count2). Window close/uninstall removed Core sessions/surfaces and preserved the three original RAPPs and Core PID. **C1.2-D2 same-process read-only graphical client DEVICE PASS.** No new APK build was triggered by assistant; separate RiftShell process/IPC/crash survival remains C1.3.

## C1.2-D2 — Independent read-only graphical Core viewer (source candidate)

The user's manually built RiftOS `b0b6e9b3`, Builder #650, device-proved C1.2-D1 dual-client sharing: Core-only disposable RAPP initial READY frame; terminal `core alt-attach`/`core alt-render` observed Core generation/revision and all typed nodes; normal GUI adopted same session and ACTION/TEXT_INPUT persisted `actions:1`, `ALT_CLIENT_TEST`; terminal subscriber received three updates and revision 4. Terminal detaching left GUI active (second ACTION counted 2); window close and uninstall yielded zero Core sessions/surfaces and original three RAPPs intact.

D2 SOURCE ONLY: independent non-exported Android `RiftAlternateGraphicalShellActivity` directly subscribes to Core immutable surfaces, displays bounded generic typed native UI nodes without input or session ownership and unsubscribes on stop. `core alt-graphic-open <id>` opens that viewer for an existing Core surface. Builder validates manifest, Kotlin compilation source, surface observer API and DEX marker `riftos.shell.client.graphical/1`. Next **user-only manual Builder and device test**: Core boot disposable; open new graphical viewer and verify READY/typed nodes; close viewer without stopping Core app, attach normal GUI and mutate state, reopen alternate graphical viewer to confirm latest state; close viewer and original GUI, uninstall disposable and verify Core cleanup. Same Android process until later C1.3; no claim of separate-process crash recovery.

## C1.2-D1 — Read-only alternate terminal shell renderer (source candidate)

RiftOS user-built source `71ff8bb5` Builder #648 device-proved C1.2-C2 Core-to-graphical RAPP handoff: starting a disposable app via `core app-start`, then opening it through native launcher preserved Core attachment generation 1, UI rendered READY, accepted ACTION/TEXT_INPUT, persisted `actions:1`/`ADOPTED_C2`, window close and uninstall cleaned Core sessions/surfaces. Surface revisions advanced during graphical window attach; no direct BOOT-count trace was recorded. Three original RAPPs unchanged.

D1 adds independent read-only `RiftAlternateShellClient` (`riftos.shell.client.terminal/1`) consuming immutable Core frames by subscription and rendering terminal/JSON node views without taking session, focus, window or input authority. Commands `core alt-list`, `core alt-attach <id>`, `core alt-render <id>`, `core alt-detach <id>`. Builder checks mandatory Kotlin source, subscription/client command wiring, source validator and DEX marker. **SOURCE ONLY** until next user-manual Builder signed APK and real device dual-client test: start a disposable app in Core, attach terminal client and render READY, open GUI on same session, press ACTION and enter TEXT_INPUT, verify terminal render independently receives latest values/revision, detach terminal without harming GUI, close/uninstall disposable. This proves in-process second **textual** renderer only; a replaceable graphical shell process remains a later goal.

## C1.2-C2 — Core-running RAPP graphical attachment (source candidate)

User green/live RiftOS `2f701e8a`, Builder #644, proved Core-only `core app-start` of a disposable verified installed RAPP: one running Core app, attached session and immutable five-node surface without a RAPP window. `core app-stop` removed both, and test uninstall preserved the original three RAPPs. C1.2-C2 source allows the graphical `RiftRappHost` to claim this Core-running session after Core verifies matching executable and attachment generation and an existing published surface. The graphical client renders the same immutable frame and skips duplicate BOOT. Builder guards validate this boundary. This is SOURCE-ONLY until the next user-manual build and device proof of preserved generation, surface revision and subsequent input. Not a separate shell process or alternate shell client.

## C1.2-C1 — Core-only RAPP BOOT/stop, new source candidate

The user's RiftOS `3dfa391e`, Builder #642, device-proved B2-B2 valid focused ACTION and TEXT_INPUT across focus loss/reacquisition; no failed/queued stale-event injected proof was claimed. New generic `RiftCoreAppLifecycle.kt` lets Core directly validate/load an installed RAPP, attach a session without a graphical View/Activity, execute BOOT and publish a Core frame, then stop/cleanup. `core apps`, `core app-start <id>`, and `core app-stop <id>` are diagnostic/control entrypoints; graphical `riftbuild launch-rapp` remains unchanged. Builder validates source wiring and final signed APK DEX presence of `riftos.core.apps/1`. User alone manually builds; next real-device test verifies `core app-start` creates a session/surface **without a RAPP window**, then `core app-stop` cleans both and leaves the original three RAPPs intact. No claim yet of renderer attachment or standalone shell process independence.

## C1.2-B2-B2 — Core-enforced user-input focus (manual build required)

C1.2-B2-B1 was proven on the user's live source `c06365cc`, Builder run #641: focus revision 0 idle, revision 1 disposable RAPP, revision 2 native Files/no RAPP focus, revision 3 reselected RAPP, revision 4 lease revoked on uninstall; all 3 original RAPPs intact, zero remaining sessions/surfaces. The new B2-B2 source changes focus enforcement from false to **true**, requiring a Core-verified matching app ID and attachment generation before focused user input is queued. Event tickets store the admission focus revision and are reauthorized at delivery; switching away/back invalidates stale pending user input. Boot/lifecycle/resize remain independent of focus. Shell safely settles denied callbacks from current immutable Core snapshot without hiding an app failure. Builder validates these markers; user-only manual Builder, signed APK and focused ACTION/TEXT_INPUT on-device proof still required. Not separate Core/shell processes or headless execution.

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
