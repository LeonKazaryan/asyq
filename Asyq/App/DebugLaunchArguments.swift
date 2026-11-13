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
