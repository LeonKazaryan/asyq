# AsyqPhysics

Jolt Physics for Asyq, behind a small C facade and a Swift API in meters (ADR-002).

```
Sources/CJolt/Jolt/            Jolt v5.6.0, vendored unmodified (commit e77f175)
Sources/CJolt/LICENSE-Jolt.txt MIT; show it in the app's "About" screen
Sources/CJolt/include/         asyq_physics.h — the only header Swift sees
Sources/CJolt/asyq_physics.cpp the facade
Sources/AsyqPhysics/           PhysicsWorld, PhysicsShape, DeterministicMath
Tests/AsyqPhysicsTests/        Swift Testing
```

## Use

- Lengths in meters, speeds in m/s. Inside, everything is scaled by `lengthScale` (10): Jolt is tuned for 0.1–10 unit objects, and a 3 cm bone at 1:1 sits outside that.
- Step with a fixed `1/240` s. A world is single-threaded and not `Sendable`: keep it on one actor. The bot gets its own world plus `snapshot()`/`restore(_:)`.
- **Inputs must be deterministic too.** Build anything that goes into the simulation (throw velocity, spin, start rotations) with plain Swift arithmetic and `DeterministicMath`. libm `sin`/`cos` may change between OS versions, and simd's C helpers (`simd_quatf(angle:axis:)`, `simd_normalize`, `act`) round differently in Debug and Release because clang fuses multiply-adds in the caller. Rendering can use anything.
- Contact events: drain once per frame. Dynamic body first; the normal points from `bodyA` to `bodyB`; `approachSpeed` is the closing speed at first touch.

## Build flags (Package.swift) and why

| Flag | Why |
|---|---|
| `JPH_CROSS_PLATFORM_DETERMINISTIC` | Same bits on every device and compiler |
| `-ffp-contract=off` | FMA contraction breaks determinism; Jolt's CMake sets it with the define above |
| `JPH_NO_DEBUG` | No Jolt asserts in the app's Debug build: many times slower, and they trap |
| `-O3` (all configs) | Jolt at -O0 is too slow to play; it comes after Xcode's `-O0` and wins |
| excludes | Other platforms' compute back ends (DX12, Metal `.mm`, Vulkan), HLSL shaders, CMake files |

The flags are `unsafeFlags`. Xcode accepts them because the package is local (path reference).

## Tests

```bash
swift test                      # macOS, ~1 s after a ~25 s first build
swift test -c release
xcodebuild -scheme AsyqPhysics -destination 'platform=iOS Simulator,name=iPhone 16 Pro,OS=18.6' test
```

`sameThrowGivesBitIdenticalResults` checks a fingerprint of a fixed throw recorded on macOS. Passing on the simulator and devices means the simulation is identical across platforms.

## Updating Jolt

1. Shallow-clone the new tag into an empty scratch folder.
2. Replace `Sources/CJolt/Jolt` with its `Jolt/` folder and update `LICENSE-Jolt.txt`.
3. Reconcile `joltExcludes` with files that aren't `.h/.cpp/.inl`, and check `Jolt/Jolt.cmake` for new determinism-related flags.
4. Run the tests. The fingerprint will most likely change: a new Jolt is a new physics version, so replays from older app versions won't match. Re-record it deliberately and note it in ADR-002.
