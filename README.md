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
2. Syntax-check both Builder shell scripts with `bash -n`, verify RiftOS `HEAD` matches the resolved SHA, and require the checked-out source tree to remain byte-clean (no tracked drift or untracked files).
3. Before source-owned tests execute, independently require `observer/phase-authority.json`, cap it at 64 KiB, parse it as JSON and require schema `rift-observer-phase-authority-v1`. Also independently require and cap `riftmemory/n2-contract-v1.json` plus `riftmemory/n2-phase-authority.json`, then verify N2.0-N2.2 promoted with N2.1 + N2.2 carrying source `694c1e31a6c3f4bd4317edd121208be894be2586` / run 346 promotion evidence under promoted N2-M1, plus N2.3 + N2.4 promoted under N2-M2 on installed source `18f1156075e08cb94573a9392031ac64552313f2` / run 350, N2.5 + N2.6 promoted under N2-M3 on installed source `62382a94f50dd6052e1754c1496da2a0f794c0af` / run 355, plus N2.7 + N2.8 / N2-M4 `source-implemented` with null promoted source/run, N2.9-N2.12 pending and canonical runtime still inactive; immutable N2.0 freeze-contract hashes, six-macro execution grouping, per-subphase evidence rule and global benchmark-deferral rule. Then run `node --check` on the critical RiftOS source-gate entrypoints before invoking them, including `scripts/test-rift-integrity-v1.mjs`, `scripts/test-rift-propagation-v1.mjs`, `scripts/test-rift-cross-boundary-contracts-v1.mjs`, `scripts/test-rift-documentation-claims-v1.mjs`, `scripts/test-rift-proof-obligations-v1.mjs`, `scripts/test-rift-observer-adversarial-v1.mjs`, `scripts/test-rift-semantic-impact-v1.mjs`, `scripts/test-rift-memory-n2-contract-v1.mjs`, `scripts/test-rift-memory-n2-m1-v1.mjs`, `scripts/test-rift-memory-n2-m2-v1.mjs`, `scripts/test-rift-memory-n2-m3-v1.mjs`, `scripts/test-rift-memory-n2-m4-v1.mjs`, and `scripts/test-riftllm-training-v2.mjs`. The Builder also requires `package.json` to keep the wiring, transport, docs, RiftCLI push, Batch V2, DebugHub, N1.8.1 integrity, N1.8.2 propagation, N1.8.3 cross-boundary contracts, N1.8.4 documentation claims, N1.8.5 proof obligations, N1.8.6 adversarial correctness, semantic-impact reference hardening, N2.0 contract freeze, N2-M1 canonical-memory foundation, N2-M2 reconciliation/temporal-truth checks, N2-M3 cognitive-memory checks, N2-M4 procedural/retrieval-memory checks and RiftLLM training-V2 checks reachable from `npm run check`, with those focused regressions specifically present in `check:transport`. This catches a malformed validator even when that validator cannot parse far enough to inspect itself.
4. Preflight Builder assumptions against RiftOS Gradle: root KGP `2.4.10` paired with `quickjs-kt 1.0.14`, namespace/application ID `com.riftos.app`, compile/target Android 36, minSdk 26, Java 17, release minification disabled, `kotlinx-coroutines-android 1.11.0`, pinned NDK `28.2.13676358`, CMake `3.22.1`, ARM64 + ARM32 ABI filters, and every mandatory Kotlin filename declaring a matching top-level class/object/interface. Any drift fails explicitly as a stale Builder contract before source tests/Gradle.
5. Run RiftOS `npm run check` so its wiring, transport, docs, protocol, native/live and explicitly retained-reference regressions gate the APK.
6. Run the dedicated Gradle validation tasks (`verifyRiftOsAndroidSources` and `validateRiftBrowserWebViewOwnership`) and capture them separately in `gradle-validation.log`.
7. Compile/package the Android release APK with Gradle.
8. Align and sign the APK.
9. Verify zip alignment and the APK signature/certificate.
10. Run `scripts/verify-riftos-apk.sh` against the **final signed APK**. The final smoke reads package identity with AAPT2 `packagename`, reads minSdk/targetSdk from the compiled `AndroidManifest.xml` via AAPT2 `xmltree` while accepting AAPT2's decimal or typed-hex rendering of the same numeric value, verifies non-debuggable release state, rejects duplicate/unsafe ZIP entries, leaked source/VCS/keystore material, retired native class descriptors, stale OS web assets, missing mandatory native classes/provenance, and byte-mismatched runtime assets. Builder preflight also requires the native CMake targets `riftcli`, `codynex_mc0_host`, `codynex_mc1a_host`, and `codynex_mc1b_host` plus their source files before source tests or Gradle compilation begin. Native RiftCLI Bootstrap-0 additionally requires the exact ZIP entries `lib/arm64-v8a/libriftcli.so` and `lib/armeabi-v7a/libriftcli.so` and forbids x86/x86_64 copies. The verifier's `require_entry` helper is literal/exact (not regex). The final APK must also contain the ARM32 proof hosts `lib/armeabi-v7a/libcodynex_mc0_host.so`, `lib/armeabi-v7a/libcodynex_mc1a_host.so`, and `lib/armeabi-v7a/libcodynex_mc1b_host.so`, because native RiftBuild reads those disposable hosts from RiftOS's own APK when preparing the corresponding Codynex machine-proof packages.

The APK smoke gate verifies the Android payload exists and that the only OS-execution files under `assets/www/` are the exact byte-for-byte `src/riftpp-core.js`, `src/riftvm.js`, and `src/semnexis-bootstrap.js` headless assets. Any returned `index.html`, `styles.css`, `workspace-live/`, PWA/service-worker file, or other unexpected `assets/www/` content is a failure. Explicit runtime assets under `android/app/src/main/assets/` (including RiftBrowser adapters) are verified separately byte-for-byte.

Because important RiftOS fixes can live entirely in Kotlin or C++, the final signed-APK gate derives
its required top-level Kotlin class descriptors from RiftOS's own
`android/app/build.gradle.kts` `verifyRiftOsAndroidSources` contract and requires every one in
the packaged DEX files. That now automatically covers current native surfaces such as
`MainActivity`, `RiftBrowserAppHost`, `RiftVolumePaths` and every other file in the current mandatory native snapshot without a second Builder list drifting behind the source contract. The private top-level
`RiftDevLabLocalAgent` object remains an explicit extra provenance assertion because it lives
inside `RiftVortexLocalAgent.kt`. The exact `SOURCE_SHA` compiled into runtime diagnostics must
also survive into DEX. N1.8.2 propagation additionally requires the signed DEX to retain `rift-semantic-propagation-v1` and `ignoredNameMatches`, proving the false-reference hardening survived compilation rather than merely proving `RiftToolSandbox` exists. N1.8.3 cross-boundary contracts additionally requires `rift-cross-boundary-contracts-v1`, `async-timeout-order-mismatch`, `jni-managed-declaration-missing`, and `partialFindingsSuppressed`, proving the contract oracle, fail-closed rule set, and Patch 10.58 partial-scan semantics survived compilation. N1.8.4 documentation claims additionally requires `rift-documentation-claims-v1`, `source-build-runtime-over-documentation`, `documentation-authority-policy-missing`, `documentation-promotion-run-stale`, `freeFormProseInference`, `observer/phase-authority.json`, `rift-observer-phase-authority-v1`, `claims-phase-authority-missing`, and `claims-phase-authority-invalid`, proving the directional source-of-truth oracle plus its fail-closed machine-readable phase-authority loader survived into the signed DEX. N1.8.5 proof obligations additionally requires `rift-proof-obligations-v1`, `generalSuiteCanSubstituteForAffectedTest`, `heuristicTestsCanSatisfyAffectedTest`, `affected-test-evidence-missing`, `proofsSha256`, `executesVerification`, and `project-local-plan-v1`, proving the evidence-only focused-verification planner, anti-substitution policy, and project-local proof-hash scope survived compilation. The N1.8.5 Workspace Records hardening additionally requires `tracking-policy-v2`, `trackingPolicyVersion`, `candidateSessionsByPath`, `candidateSessionEvidenceComplete`, `workspace semantic impact`, `candidate-projects`, `no-candidate-changes`, `candidateStateSha256`, and `evidenceManifestSha256`, proving the compact tracking-policy migration, separately persisted active-candidate provenance, zero-change no-index fast path, candidate-project-scoped indexing, stable candidate-state identity, and separately returned full evidence-manifest identity survived into DEX; exact 256-record, 60-second and 75/90/100/110/120 timeout constants remain locked by RiftOS source regressions before compilation. RiftLLM training V2 additionally requires the signed DEX to retain `rift.train-data-v2-status/1`, `rift-b2-bottomk-v1`, `rift-b2-bottomk-threshold-qualification-v1` and `train-v2-adversarial-lab`, proving the candidate build/qualification routes survived compilation in addition to the automatically derived class descriptors. RiftCLI N1.5 additionally requires the final signed DEX to retain the
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


