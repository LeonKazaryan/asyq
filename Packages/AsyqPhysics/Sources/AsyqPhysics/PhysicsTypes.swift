import simd

/// A body in a `PhysicsWorld`. Stable for the body's life; a removed body's id isn't reused
/// right away (Jolt bumps a sequence number).
public struct BodyID: Hashable, Sendable {
    public let rawValue: UInt32

    public init(rawValue: UInt32) {
        self.rawValue = rawValue
    }
}

/// How two materials behave when they touch.
public struct SurfacePair: Sendable {
    public var friction: Float
    /// 0 = dead stop, 1 = perfectly elastic.
    public var restitution: Float

    public init(friction: Float, restitution: Float) {
        self.friction = friction
        self.restitution = restitution
    }
}

/// World settings in meters and seconds. Defaults suit 3 cm bones stepped at 240 Hz;
/// Jolt's own defaults assume 1 m objects at 60 Hz.
public struct PhysicsWorldConfig: Sendable {
    /// Jolt units per meter. Jolt is tuned for objects of 0.1–10 units, so a 3 cm bone
    /// becomes 0.3. Scaling lengths, speeds and gravity together leaves the motion
    /// unchanged; masses stay as they are.
    public var lengthScale: Float = 10
    public var gravity: SIMD3<Float> = [0, -9.81, 0]
    public var maxBodies: Int = 64
    public var velocitySteps: Int = 10
    public var positionSteps: Int = 2
    /// Overlap allowed before position correction pushes bodies apart. Small against a
    /// 16 mm bone, but not so small that resting contacts fight each other.
    public var penetrationSlop: Float = 0.0005
    /// Contacts start this far before touching, so fast bones meet before they overlap.
    public var speculativeContactDistance: Float = 0.002
    /// Slower impacts don't bounce. Jolt's 1 m/s would kill every small hop of a bone.
    public var minVelocityForRestitution: Float = 0.3
    /// A body sleeps once no point on it moves faster than this for `timeBeforeSleep`.
    public var sleepVelocityThreshold: Float = 0.004
    public var timeBeforeSleep: Float = 0.5
    /// rad/s. Jolt's default (a quarter turn per 60 Hz step) would cap a spun bone at
    /// 47 rad/s; at 240 Hz a quarter turn per step allows ~188.
    public var maxAngularVelocity: Float = 180

    public init() {}
}

public struct BodyDescription: Sendable {
    /// kg. Inertia comes from the shape, scaled to this mass.
    public var mass: Float
    /// Index into the surface pair table, 0..<8.
    public var material: UInt8
    public var position: SIMD3<Float>
    public var rotation: simd_quatf
    public var linearDamping: Float
    public var angularDamping: Float
    /// Continuous collision detection: needed for anything fast enough to cross its own
    /// size in one step, like a thrown saqa.
    public var continuousCollision: Bool
    public var startsAsleep: Bool

    public init(
        mass: Float,
        material: UInt8,
        position: SIMD3<Float>,
        rotation: simd_quatf = .init(ix: 0, iy: 0, iz: 0, r: 1),
        linearDamping: Float = 0.05,
        angularDamping: Float = 0.05,
        continuousCollision: Bool = false,
        startsAsleep: Bool = false
    ) {
        self.mass = mass
        self.material = material
        self.position = position
        self.rotation = rotation
        self.linearDamping = linearDamping
        self.angularDamping = angularDamping
        self.continuousCollision = continuousCollision
        self.startsAsleep = startsAsleep
    }
}

/// Two bodies started touching. In the order they happened during the steps.
public struct ContactEvent: Sendable {
    /// For a dynamic body against a static one, `bodyA` is the dynamic body.
    public var bodyA: BodyID
    public var bodyB: BodyID
    /// Meters.
    public var point: SIMD3<Float>
    /// Unit, from `bodyA` towards `bodyB`.
    public var normal: SIMD3<Float>
    /// m/s along the normal at first touch, never negative: how hard the hit was.
    public var approachSpeed: Float

    public init(bodyA: BodyID, bodyB: BodyID, point: SIMD3<Float>, normal: SIMD3<Float>, approachSpeed: Float) {
        self.bodyA = bodyA
        self.bodyB = bodyB
        self.point = point
        self.normal = normal
        self.approachSpeed = approachSpeed
    }
}

/// The whole simulation at one moment, to rewind a world (the bot tries throws on a copy).
/// Restores only into a world with the same bodies added in the same order.
public struct PhysicsSnapshot: Sendable {
    public let bytes: [UInt8]

    public init(bytes: [UInt8]) {
        self.bytes = bytes
    }
}
