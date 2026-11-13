/// A small seeded generator (SplitMix64): the same seed always gives the same numbers, so a
/// bot's match can be replayed and tested.
struct SeededRandom: Sendable {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// 0…1.
    mutating func fraction() -> Float {
        Float(next() >> 40) / Float(1 << 24)
    }

    /// −1…1.
    mutating func unit() -> Float {
        fraction() * 2 - 1
    }

    /// −1…1, bunched toward 0 like a human's misses: the mean of three draws.
    mutating func spread() -> Float {
        (unit() + unit() + unit()) / 3
    }
}
