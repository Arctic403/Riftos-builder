# RiftOS Builder — manually triggered signed Android host APK

This project is the **standalone RiftOS Android host APK Builder**, not the independent Core/Shell Component Builder RAPP. It builds the checked-out `Arctic403/RiftOS` Android host, validates its host-only source and the final signed artifact, and publishes build output only when the user triggers the private workflow.

## Ownership and frozen Core/Shell boundary

- **RiftOS host repo**: `/D:/Workspace/RiftOS-main` — Android manifest/processes, host ABI, external DEX component loading, protected install/Recovery, Android binder/security, MCP relay client, Local Agent/Accessibility, RiftFS/workspace, generic RAPP/platform services and browser/tool support.
- **Independent Core/Shell and their TODOs/tests**: `/D:/Workspace/RiftComponents` — separate source, independent DEX/manifest recipes, separate Core & Shell Builder RAPP, user-controlled stage/install/select.
- **This Builder**: `/D:/Workspace/Riftos-builder-main` — workflow, exact-source verification, Gradle host source checks, package/sign/artifact verification.

On the 2026-10-15 device checkpoint, external Core v0.6.9 and Shell V10 were selected. **That does not qualify any future host APK build**. The currently checked-out host still packages frozen embedded Core/Shell fallback/compatibility classes. Their E0/E1/C1 historical milestone tests, canaries, UI implementation proofs and old release narratives are retired; no such TODOs are maintained in the RiftOS repo or this Builder.

## Manual user workflow

1. User triggers **RiftOS Private Build Worker** via `workflow_dispatch`, with `source_ref` an exact RiftOS branch/tag/commit (default `main`).
2. Worker checks out the exact private source SHA and refuses dirty tree drift.
3. `scripts/validate-platform-source.py` verifies **APK host ownership only**: mandatory Gradle Kotlin inventory, component ABI/verification/Recovery, Android manifest, MCP, Local Agent, RiftFS/workspace, FileProvider and security boundaries.
4. Gradle runs `:app:verifyRiftOsAndroidSources` and `:app:validateRiftBrowserWebViewOwnership`, then `:app:assembleRelease` with clean native intermediates.
5. The worker aligns the unsigned APK, signs with its private identity, verifies the signature, and runs `scripts/verify-riftos-apk.sh` on the **actual signed APK**.
6. User downloads/installs/tests the APK. Build success does not auto-stage a new independent Core/Shell, change Recovery, or grant new runtime permissions.

## What final APK validation still checks

- Correct package, SDK/security manifest and packaged Android processes/entrypoints.
- DEX presence for every mandatory top-level Android Kotlin owner derived from the current Gradle contract (including currently compiled compatibility/fallback classes **without** executing their old feature-specific test gates).
- Current protected component/Recovery, host IPC/ABI and generic capability classes.
- MCP, Local Agent/Accessibility, RiftFS/workspace, native build services, Android installer/FileProvider and correctly packaged browser assets.
- Android arm64-v8a and armeabi-v7a native assets, exact source SHA where embedded, no unsafe/duplicate ZIP entries, no leaked source/signing material or retired web/CLI payloads.
- Release identity, alignment, signature and source-to-asset correspondence.

Legacy embedded Core/Shell implementation roadmaps, unit/device proofs and component-specific source-string gates are **not** Builder release requirements. Future external Core/Shell requirements and TODOs go to RiftComponents. **Do not delete the host's runtime safety checks or compiled compatibility classes without a separate source/ABI/device qualification.**

## Files

- `.github/workflows/riftos-worker.yml` — user-manual private Android host worker.
- `scripts/riftos-build.sh` — exact source → host validation → Gradle build → sign → signed APK proof.
- `scripts/validate-platform-source.py` — current host-only source contract.
- `scripts/verify-riftos-apk.sh` — final signed APK and mandatory DEX owner inspection.
- `scripts/test-builder-contracts.py` — Builder contract consistency checks.
- `scripts/resolve-apk-xml-resource.py` — checks Android XML resources in actual APK.
- `.github/workflows/managed-compiler-worker.yml` — separate managed compiler task; it does not activate Core/Shell revisions.

**Deployment policy:** You manually trigger the host build; use the Core & Shell Builder RAPP yourself for separate component compile/stage/install/selection. An assistant may edit, audit and push source through RiftOS MCP/native RiftGit but may not operate either deployment without permission.
