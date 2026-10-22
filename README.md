# RiftOS Builder — manually triggered signed Android host APK

## 2026-10-21 — Signed APK metadata digest regression

The first full Gradle release attempt against RiftOS `f80ec1cc4b93fb367bc5f398a1b9e531f27d3fc4` completed **109 Gradle tasks**, including host Kotlin compilation and `:app:testReleaseUnitTest`, and produced an aligned signed APK. The final APK smoke gate rejected `androidJarSha256` due to an escaped shell variable (`\${sha_key}`) in the grep regular expression; this did **not** establish a bad packaged SHA or an Android compilation failure.

The Builder-only verifier now expands `${sha_key}` while retaining full SHA-256 metadata validation against both extracted JAR assets. Builder contract tests execute the extracted verifier digest guard in Bash with four synthetic cases: valid, missing, malformed, and duplicate keys. No signed-APK smoke success, installed-host qualification or device functionality is claimed until the next user-triggered full Builder completes.

---

## AGP 9 release-unit-test task parity

The worker requires `:app:testReleaseUnitTest` to execute 20 JVM archive/classpath/DEX publication tests before signing. Under Android Gradle Plugin 9, only the selected test build type (usually debug) gets a unit-test task by default. The release Gradle invocation explicitly supplies `-Pandroid.onlyEnableUnitTestForTheTestedBuildType=false` to register the release test variant. Do not replace this with `testDebugUnitTest`, an empty placeholder task, or a skipped-test override; the worker validates the real release XML test receipt.

This Builder-only correction follows a user-manual worker failure where source preflight and initial Gradle source validation passed but Gradle could not find `:app:testReleaseUnitTest`. No change to the RiftOS source commit or manual worker/install ownership.

---

## 2026-10-21 — Generic JVM dependency / DEX integrity parity

RiftOS source `main` at **`f80ec1cc4b93fb367bc5f398a1b9e531f27d3fc4`** contains the new generic JVM dependency inputs and the stricter host implementation. This Builder revision expands its source and final signed APK checks to cover:

- `RiftJvmDexService` and its archive normalization, exact compiler classpath and recoverable DEX publication classes, plus host ownership of managed Kotlin/D8.
- Source-pinned **Android SDK 36** and **Kotlin stdlib 2.4.10**, with the **actual packaged** `toolchain.properties` SHA-256 values independently matched to the two signed APK JAR assets.
- A release Gradle `:app:testReleaseUnitTest` execution gate and XML receipt for **at least 20 successful, non-skipped JVM JUnit tests**, before signing and final artifact validation.
- Signed-DEX presence for the generic JVM service, JAR helper, strict classpath policy, DEX publisher, and new versioned dependency response markers.

All checks remain **generic**: no QuickJS, Rift++, or other language/provider implementation is embedded in the host APK or its release requirements. No independent Core/Shell selection or Recovery mutation is performed by the worker. The user manually triggers the worker, installs verified APKs, and conducts runtime tests. These Builder source changes alone are not a successful Android compile or release.

For reproducibility, select `source_ref=main` only when RiftOS main still resolves to the SHA above, or use that exact commit as the requested source ref. On failure, inspect the **first** Builder gate failure and private logs before considering further patches.

---



This project is the **standalone RiftOS Android host APK Builder**, not the independent Core/Shell Component Builder RAPP. It builds the checked-out `Arctic403/RiftOS` Android host, validates its host-only source and the final signed artifact, and publishes build output only when the user triggers the private workflow.

## Ownership and external-only Core/Shell boundary

- **RiftOS host repo**: `/D:/Workspace/RiftOS-main` — Android manifest/processes, host ABI, external DEX component loading, protected install/Recovery, Android binder/security, MCP relay client, Local Agent/Accessibility, RiftFS/workspace, generic RAPP/platform services and browser/tool support.
- **Independent Core/Shell and their TODOs/tests**: `/D:/Workspace/RiftComponents` — separate source, independent DEX/manifest recipes, separate Core & Shell Builder RAPP, user-controlled stage/install/select.
- **This Builder**: `/D:/Workspace/Riftos-builder-main` — workflow, exact-source verification, Gradle host source checks, package/sign/artifact verification.

On the 2026-10-15 device checkpoint, external Core v0.6.9 and Shell V10 were selected. **That does not qualify any future host APK build**. The current unbuilt source candidate removes embedded Core and graphical Shell implementations, MainActivity and alternate graphical proof Activities. Builder rejects these removed classes in source and signed DEX. E0/E1/C1 milestone test narratives remain retired. External component TODOs belong in RiftComponents.

## Manual user workflow

1. User triggers **RiftOS Private Build Worker** via `workflow_dispatch`, with `source_ref` an exact RiftOS branch/tag/commit (default `main`).
2. Worker checks out the exact private source SHA and refuses dirty tree drift.
3. `scripts/validate-platform-source.py` verifies **APK host ownership only**: mandatory Gradle Kotlin inventory, component ABI/verification/Recovery, Android manifest, MCP, Local Agent, RiftFS/workspace, FileProvider and security boundaries.
4. Gradle runs `:app:verifyRiftOsAndroidSources` and `:app:validateRiftBrowserWebViewOwnership`, then `:app:assembleRelease` with clean native intermediates.
5. The worker aligns the unsigned APK, signs with its private identity, verifies the signature, and runs `scripts/verify-riftos-apk.sh` on the **actual signed APK**.
6. User downloads/installs/tests the APK. Build success does not auto-stage a new independent Core/Shell, change Recovery, or grant new runtime permissions.

## What final APK validation still checks

- Correct package, SDK/security manifest and packaged Android processes/entrypoints.
- DEX presence for every mandatory Kotlin owner derived from Gradle, plus verified absence of retired embedded Core and graphical Shell implementations.
- Current protected component/Recovery, host IPC/ABI and generic capability classes.
- MCP, Local Agent/Accessibility, RiftFS/workspace, native build services, Android installer/FileProvider and correctly packaged browser assets.
- Android arm64-v8a and armeabi-v7a native assets, exact source SHA where embedded, no unsafe/duplicate ZIP entries, no leaked source/signing material or retired web/CLI payloads.
- Release identity, alignment, signature and source-to-asset correspondence.

Legacy embedded Core/Shell roadmaps and feature-specific proof strings are retired; absence of the embedded code is now a mandatory signed-APK release gate. Future external Core/Shell requirements and TODOs go to RiftComponents. **Do not delete the host's security checks, external ABI/IPC, MCP command executor or manual Recovery.**

## Files

- `.github/workflows/riftos-worker.yml` — user-manual private Android host worker.
- `scripts/riftos-build.sh` — exact source → host validation → Gradle build → sign → signed APK proof.
- `scripts/validate-platform-source.py` — current host-only source contract.
- `scripts/verify-riftos-apk.sh` — final signed APK and mandatory DEX owner inspection.
- `scripts/test-builder-contracts.py` — Builder contract consistency checks.
- `scripts/resolve-apk-xml-resource.py` — checks Android XML resources in actual APK.
- `.github/workflows/managed-compiler-worker.yml` — separate managed compiler task; it does not activate Core/Shell revisions.

**Deployment policy:** You manually trigger the host build; use the Core & Shell Builder RAPP yourself for separate component compile/stage/install/selection. An assistant may edit, audit and push source through RiftOS MCP/native RiftGit but may not operate either deployment without permission.