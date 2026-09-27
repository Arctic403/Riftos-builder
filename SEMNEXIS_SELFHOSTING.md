# Semnexis self-hosting build contract

Updated: 2026-09-27

## Purpose

Riftos-builder does not own Semnexis compiler semantics. RiftOS owns the compiler, the source regressions, and the installed `semx` shell surface.

Builder owns two things:

1. proving that the exact RiftOS commit still exposes and runs its Semnexis source gates before Android packaging; and
2. proving that the final signed APK contains the exact packaged `src/semnexis-bootstrap.js` bytes from that source commit.

Builder must not silently drift behind a promoted Semnexis self-hosting fixture.

## Current RiftOS Semnexis authority

Current bootstrap source identity:

- compiler: `0.7.0-quickjs-bootstrap`;
- packaged authority: `src/semnexis-bootstrap.js`;
- installed shell promotion remains `semnexis-bootstrap-self-test/17` until a newer APK is actually built, installed, and proved;
- frozen binary compatibility remains `SNIRV0` through additive `SNIRV7`.

The source/machine self-hosting regression is owned by:

- `scripts/test-semnexis-bootstrap.mjs`;
- `scripts/test-semnexis-arm32-exec.mjs`;
- `scripts/test-semnexis-shell.mjs`.

All three must remain reachable from RiftOS `npm run check`.

## Promoted self-host fixtures currently inside RiftOS

Builder explicitly requires these source fixtures to exist because `test-semnexis-arm32-exec.mjs` consumes them:

- `scripts/fixtures/semnexis-selfhost-frontend-v18.snx`
- `scripts/fixtures/semnexis-selfhost-semantic-v19.snx`
- `scripts/fixtures/semnexis-selfhost-native-ir-v25.snx`

### v18 frontend

The v18 fixture proves generated ARM32 can consume real Semnexis source and produce the deterministic Arena AST for:

```snx
fn main() -> i32 { let x = 12 + 3 * (4 + 1); return x; }
```

The source gate covers multi-digit literals, identifiers/keywords, precedence, grouping, function syntax, `let`, `return`, recursion classification, SNIR round-trip, and canonical ARM32 verification.

### v19 semantic graph

The v19 fixture continues from the real-source parser into Semnexis-written semantic graph construction.

The source gate proves:

- the same real source parses successfully;
- a deterministic 22-fact semantic graph is produced;
- Function, Local, literal, binary, NameRef, Return, containment, initialization, and return-value facts are present;
- the return `x` NameRef resolves to the declared local `x`;
- SNIR round-trip and canonical ARM32 verification remain intact.

### v25 promoted full compiler slice

The current RiftOS regression frontier is the v25 fixture.

For two independent programs, generated ARM32 performs the Semnexis-written compiler pipeline and differentially checks it against the QuickJS bootstrap:

```snx
fn twice(n: i32) -> i32 {
  let x = n + n;
  return x;
}

fn main() -> i32 {
  let a = 12;
  let b = 3;
  return twice(a + b);
}
```

and:

```snx
fn sample() -> i32 {
  return clock();
}

fn main() -> i32 with time {
  let x = sample();
  return x;
}
```

The v25 source gate proves:

- real source parsing;
- canonical Program Graph node-kind and edge-topology parity;
- Semnexis-written canonical graph verifier acceptance;
- effect/capability and `with time` graph semantics;
- exact Execution Plan parity against the bootstrap;
- Semnexis-written Native IR function metadata parity;
- parameter metadata parity;
- instruction/op/operand/graph-provenance parity;
- pure fixture: 26 graph nodes, 59 graph edges, 15 plan steps, 19 IR instructions;
- effect/capability fixture: 16 graph nodes, 31 graph edges, 15 plan steps, 10 IR instructions;
- bounded recursive depth remains 256;
- source-produced Native IR still passes the existing SNIR round-trip and canonical ARM32 artifact verifier.

This is a source/machine self-hosting gate. It does **not** by itself promote the installed `semx` shell above `/17`.

## v26 is not yet a RiftOS/Builder promotion

The Semnexis workspace has progressed beyond v25 with a modular IR-to-SNIR serializer pressure stage.

That work is intentionally **not part of this Builder contract yet** because it has not been promoted into the RiftOS source tree/regression fixtures.

Builder must not claim v26 byte-serializer promotion until RiftOS deliberately adds the corresponding source fixture/regression and updates this contract.

This distinction prevents local Semnexis research state from being mistaken for an APK/source promotion.

## Builder preflight contract

Before `npm run check`, Builder must:

- syntax-check `scripts/test-semnexis-bootstrap.mjs`;
- syntax-check `scripts/test-semnexis-arm32-exec.mjs`;
- syntax-check `scripts/test-semnexis-shell.mjs`;
- require all three scripts to remain in RiftOS `check:transport`;
- require the v18, v19, and v25 fixture files above;
- require `test-semnexis-arm32-exec.mjs` to reference all three promoted fixtures.

Builder does not duplicate the Semnexis machine interpreter or semantic assertions. The authoritative regression executes as part of the exact checked-out RiftOS commit's `npm run check`.

## Final signed APK contract

The source-only self-host fixtures and test scripts are not Android runtime payload.

The final signed APK gate therefore does not require those fixture files inside the APK. Instead it requires:

- `assets/www/src/semnexis-bootstrap.js` exists;
- that asset is byte-for-byte identical to the checked-out RiftOS `src/semnexis-bootstrap.js`;
- no unexpected retired/broad `assets/www` tree returns.

Installed-device promotion remains separate from source verification.

## Update discipline

Whenever RiftOS promotes a new Semnexis self-hosting fixture or changes the Semnexis regression boundary:

1. update the RiftOS Semnexis docs/roadmap/checkpoint;
2. keep the new fixture wired into the authoritative RiftOS source regression;
3. update this Builder contract;
4. update Builder preflight if a new promoted fixture/script becomes mandatory;
5. run Builder shell syntax validation and source-contract preflight;
6. only then push/dispatch a build.

Do not raise runtime/compiler safety bounds solely to make a larger self-host compiler fixture fit. The v26 pressure work already demonstrated the preferred response: split independently bounded native stages rather than weakening the existing 256-function ARM32 runtime limit.
