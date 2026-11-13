// swift-tools-version: 6.0
import PackageDescription

// Jolt's library sources are vendored unmodified under Sources/CJolt/Jolt; these are the
// files in that tree that aren't part of the build (other platforms' compute back ends,
// GPU shaders, CMake and debugger files).
let joltExcludes = [
    "Jolt/Jolt.cmake",
    "Jolt/Jolt.natvis",
    "Jolt/Compute/DX12",
    "Jolt/Compute/MTL",
    "Jolt/Compute/VK",
    "Jolt/Physics/Collision/Shape/TaperedCapsuleShape.gliffy",
    "Jolt/Shaders/HairApplyDeltaTransform.hlsl",
    "Jolt/Shaders/HairApplyGlobalPose.hlsl",
    "Jolt/Shaders/HairCalculateCollisionPlanes.hlsl",
    "Jolt/Shaders/HairCalculateRenderPositions.hlsl",
    "Jolt/Shaders/HairGridAccumulate.hlsl",
    "Jolt/Shaders/HairGridClear.hlsl",
    "Jolt/Shaders/HairGridNormalize.hlsl",
    "Jolt/Shaders/HairIntegrate.hlsl",
    "Jolt/Shaders/HairSkinRoots.hlsl",
    "Jolt/Shaders/HairSkinVertices.hlsl",
    "Jolt/Shaders/HairTeleport.hlsl",
    "Jolt/Shaders/HairUpdateRoots.hlsl",
    "Jolt/Shaders/HairUpdateStrands.hlsl",
    "Jolt/Shaders/HairUpdateVelocity.hlsl",
    "Jolt/Shaders/HairUpdateVelocityIntegrate.hlsl",
    "Jolt/Shaders/TestCompute.hlsl",
    "Jolt/Shaders/TestCompute2.hlsl",
    "LICENSE-Jolt.txt",
]

let package = Package(
    name: "AsyqPhysics",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "AsyqPhysics", targets: ["AsyqPhysics"]),
    ],
    targets: [
        .target(
            name: "CJolt",
            exclude: joltExcludes,
            publicHeadersPath: "include",
            cxxSettings: [
                // So `#include <Jolt/Jolt.h>` resolves inside the vendored tree.
                .headerSearchPath("."),
                // Same results on every device and compiler (ADR-002): Jolt avoids
                // platform-specific math paths, and FMA contraction is off below.
                .define("JPH_CROSS_PLATFORM_DETERMINISTIC"),
                // No Jolt asserts or debug-only checks even in the app's Debug build: they
                // make the physics many times slower and trap on recoverable issues.
                .define("JPH_NO_DEBUG"),
                .unsafeFlags([
                    // Fused multiply-add rounds differently from mul + add, which breaks
                    // cross-platform determinism. Jolt's own CMake sets this too.
                    "-ffp-contract=off",
                    // Physics at -O0 is too slow to play or test; the app's Debug build
                    // would otherwise compile Jolt unoptimized. Comes after Xcode's -O0.
                    "-O3",
                ]),
            ]
        ),
        .target(
            name: "AsyqPhysics",
            dependencies: ["CJolt"]
        ),
        .testTarget(
            name: "AsyqPhysicsTests",
            dependencies: ["AsyqPhysics"]
        ),
    ],
    cxxLanguageStandard: .cxx17
)
