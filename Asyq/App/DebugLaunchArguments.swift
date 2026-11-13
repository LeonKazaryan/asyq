import Foundation

/// Launch arguments for checking scenes in the simulator without touching it (Debug only).
/// Pass them as `-AsyqDebugThrow 2,0.62,0` after the bundle id in `simctl launch`.
enum DebugLaunchArguments {
    /// `-AsyqDebugThrow angleDegrees,power[,spin]`: throws by itself 1.2 s after launch.
    static var throwInput: ThrowInput? {
        guard let values = numbers("AsyqDebugThrow"), values.count >= 2 else { return nil }
        return ThrowInput(angle: Float(values[0]) * .pi / 180, power: Float(values[1]), spin: values.count > 2 ? Float(values[2]) : 0)
    }

    /// `-AsyqDebugPull power,aim`: holds the slingshot drawn, with the aim preview showing.
    static var pull: (power: Double, aim: Double)? {
        guard let values = numbers("AsyqDebugPull"), values.count >= 2 else { return nil }
        return (values[0], values[1])
    }

    /// `-AsyqDebugFromEdge YES`: start the series from the circle's edge.
    static var fromEdge: Bool {
        #if DEBUG
        UserDefaults.standard.bool(forKey: "AsyqDebugFromEdge")
        #else
        false
        #endif
    }

    /// `-AsyqDebugSeed N`: the rival's dice, for a match that plays the same every time.
    static var seed: UInt64? {
        numbers("AsyqDebugSeed").map { UInt64($0[0]) }
    }

    /// `-AsyqDebugScreen practice|match`: skip the menu.
    static var screen: String? {
        #if DEBUG
        UserDefaults.standard.string(forKey: "AsyqDebugScreen")
        #else
        nil
        #endif
    }

    /// `-AsyqDebugSpin strength,tilt`: in a match, spins the iiru by itself.
    static var spin: (strength: Float, tilt: Float)? {
        guard let values = numbers("AsyqDebugSpin"), values.count >= 2 else { return nil }
        return (Float(values[0]), Float(values[1]))
    }

    /// `-AsyqDebugAutoplay YES`: in a match, a bot plays for you too — watch a whole match.
    static var autoplay: Bool {
        #if DEBUG
        UserDefaults.standard.bool(forKey: "AsyqDebugAutoplay")
        #else
        false
        #endif
    }

    /// `-AsyqDebugCategory bala|jasospirim|jigit|eresek`.
    static var category: AgeCategory? {
        #if DEBUG
        UserDefaults.standard.string(forKey: "AsyqDebugCategory").flatMap(AgeCategory.init(rawValue:))
        #else
        nil
        #endif
    }

    private static func numbers(_ key: String) -> [Double]? {
        #if DEBUG
        guard let raw = UserDefaults.standard.string(forKey: key) else { return nil }
        let values = raw.split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
        return values.isEmpty ? nil : values
        #else
        nil
        #endif
    }
}
