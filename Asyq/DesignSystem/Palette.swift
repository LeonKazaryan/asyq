import SwiftUI
import simd

/// One palette color, usable both in SwiftUI and in the Metal scene (as linear RGB).
struct PaletteColor: Sendable {
    /// sRGB, 0xRRGGBB.
    let hex: UInt32

    var color: Color {
        Color(.sRGB, red: Double(channel(16)), green: Double(channel(8)), blue: Double(channel(0)))
    }

    /// Linear RGB for shaders, which light in linear space.
    var linear: SIMD3<Float> {
        SIMD3(Self.toLinear(channel(16)), Self.toLinear(channel(8)), Self.toLinear(channel(0)))
    }

    private func channel(_ shift: UInt32) -> Float {
        Float((hex >> shift) & 0xFF) / 255
    }

    private static func toLinear(_ value: Float) -> Float {
        value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
    }
}

/// Warm, quiet base with bones as the only "material" thing on screen (docs/02-design.md,
/// ADR-004). Draft until M2 settles it.
enum Palette {
    // The stage.
    /// The felt (киіз) carpet: a muted terracotta, so ivory bones stand out.
    static let felt = PaletteColor(hex: 0xB0654A)
    /// The haze the carpet fades into: the studio cyclorama.
    static let haze = PaletteColor(hex: 0xEADBCB)
    static let zenith = PaletteColor(hex: 0xDCC6B0)
    /// Stitched field markings.
    static let thread = PaletteColor(hex: 0xF7EBDC)

    // The bones.
    static let bone = PaletteColor(hex: 0xEEE3D0)
    /// The player's painted saqa: көк, deep sky blue.
    static let saqa = PaletteColor(hex: 0x1E5C78)

    // Interface.
    static let ink = PaletteColor(hex: 0x2A1F19)
    static let paper = PaletteColor(hex: 0xFBF6EF)
    static let accent = PaletteColor(hex: 0xE89E3C)
    static let miss = PaletteColor(hex: 0x8A7B6E)
}
