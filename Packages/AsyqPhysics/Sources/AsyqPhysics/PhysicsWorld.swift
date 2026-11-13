import CJolt
import simd

/// A collision shape, shared by any number of bodies. Bodies keep their own reference, so
/// the shape may go away after they are created.
public final class PhysicsShape {
    let pointer: OpaquePointer

    init(pointer: OpaquePointer) {
        self.pointer = pointer
    }

    deinit {
        ap_shape_release(pointer)
    }
}

/// A Jolt physics world in meters, kilograms and seconds.
///
/// Deterministic: the same bodies and calls in the same order give bit-identical results
/// on every device (ADR-002). Single-threaded on purpose, which also keeps contact events
/// in a fixed order. Not thread-safe: keep each world on one actor.
public final class PhysicsWorld {
    public let config: PhysicsWorldConfig
    private let world: OpaquePointer
    private let scale: Float

    public init(config: PhysicsWorldConfig = .init()) {
        self.config = config
        scale = config.lengthScale
        var settings = APWorldSettings()
        ap_world_settings_default(&settings)
        settings.gravity = APVec3(config.gravity * scale)
        settings.maxBodies = UInt32(config.maxBodies)
        settings.velocitySteps = UInt32(config.velocitySteps)
        settings.positionSteps = UInt32(config.positionSteps)
        settings.penetrationSlop = config.penetrationSlop * scale
        settings.speculativeContactDistance = config.speculativeContactDistance * scale
        settings.minVelocityForRestitution = config.minVelocityForRestitution * scale
        settings.pointVelocitySleepThreshold = config.sleepVelocityThreshold * scale
        settings.timeBeforeSleep = config.timeBeforeSleep
        settings.maxAngularVelocity = config.maxAngularVelocity
        guard let world = ap_world_create(&settings) else {
            fatalError("Jolt failed to create a physics world")
        }
        self.world = world
    }

    deinit {
        ap_world_destroy(world)
    }

    // MARK: Materials and shapes

    public func setSurfacePair(_ a: UInt8, _ b: UInt8, _ pair: SurfacePair) {
        ap_world_set_surface_pair(world, a, b, pair.friction, pair.restitution)
    }

    /// A box with every edge and corner rounded by `cornerRadius` (at most the smallest
    /// half extent). Exact for physics: Jolt rounds the box by its convex radius.
    public func makeRoundedBoxShape(halfExtents: SIMD3<Float>, cornerRadius: Float, centerOfMassOffset: SIMD3<Float> = .zero) -> PhysicsShape {
        guard let shape = ap_shape_create_rounded_box(APVec3(halfExtents * scale), cornerRadius * scale, APVec3(centerOfMassOffset * scale)) else {
            fatalError("Jolt rejected a rounded box with half extents \(halfExtents)")
        }
        return PhysicsShape(pointer: shape)
    }

    /// Nil when the points don't span a volume.
    public func makeConvexHullShape(points: [SIMD3<Float>], convexRadius: Float, centerOfMassOffset: SIMD3<Float> = .zero) -> PhysicsShape? {
        let scaled = points.map { APVec3($0 * scale) }
        let shape = scaled.withUnsafeBufferPointer { buffer in
            ap_shape_create_convex_hull(buffer.baseAddress, UInt32(buffer.count), convexRadius * scale, APVec3(centerOfMassOffset * scale))
        }
        return shape.map(PhysicsShape.init(pointer:))
    }

    // MARK: Bodies

    @discardableResult
    public func addStaticBox(halfExtents: SIMD3<Float>, position: SIMD3<Float>, material: UInt8) -> BodyID {
        checked(ap_world_add_static_box(world, APVec3(halfExtents * scale), APVec3(position * scale), material))
    }

    public func addBody(shape: PhysicsShape, description: BodyDescription) -> BodyID {
        var settings = APBodySettings(
            mass: description.mass,
            material: description.material,
            position: APVec3(description.position * scale),
            rotation: APQuat(description.rotation),
            linearDamping: description.linearDamping,
            angularDamping: description.angularDamping,
            linearCast: description.continuousCollision,
            startsAsleep: description.startsAsleep
        )
        return checked(ap_world_add_body(world, shape.pointer, &settings))
    }

    public func removeBody(_ id: BodyID) {
        ap_world_remove_body(world, id.rawValue)
    }

    public var bodyCount: Int {
        Int(ap_world_body_count(world))
    }

    // MARK: Simulation

    /// Advances by `deltaTime` seconds. Call with a fixed step (1/240) for determinism.
    public func step(deltaTime: Float) {
        ap_world_step(world, deltaTime)
    }

    public func position(of id: BodyID) -> SIMD3<Float> {
        transform(of: id).position
    }

    public func rotation(of id: BodyID) -> simd_quatf {
        transform(of: id).rotation
    }

    /// Both at once: one lookup instead of two when drawing every body each frame.
    public func transform(of id: BodyID) -> (position: SIMD3<Float>, rotation: simd_quatf) {
        var position = APVec3()
        var rotation = APQuat()
        ap_body_get_transform(world, id.rawValue, &position, &rotation)
        return (SIMD3(position) / scale, simd_quatf(rotation))
    }

    public func setTransform(_ id: BodyID, position: SIMD3<Float>, rotation: simd_quatf, activate: Bool) {
        ap_body_set_transform(world, id.rawValue, APVec3(position * scale), APQuat(rotation), activate)
    }

    public func linearVelocity(of id: BodyID) -> SIMD3<Float> {
        velocity(of: id).linear
    }

    public func angularVelocity(of id: BodyID) -> SIMD3<Float> {
        velocity(of: id).angular
    }

    /// Wakes the body.
    public func setVelocity(_ id: BodyID, linear: SIMD3<Float>, angular: SIMD3<Float>) {
        ap_body_set_velocity(world, id.rawValue, APVec3(linear * scale), APVec3(angular))
    }

    public func isAwake(_ id: BodyID) -> Bool {
        ap_body_is_active(world, id.rawValue)
    }

    public var hasAwakeBodies: Bool {
        ap_world_has_active_bodies(world)
    }

    public func putToSleep(_ id: BodyID) {
        ap_body_deactivate(world, id.rawValue)
    }

    public func wake(_ id: BodyID) {
        ap_body_activate(world, id.rawValue)
    }

    // MARK: Contacts

    /// Impacts lost since the last drain because more than 512 piled up.
    public var droppedContactEvents: Int {
        Int(ap_world_dropped_contact_events(world))
    }

    /// Every contact that started since the last drain, oldest first, and clears them.
    public func drainContactEvents() -> [ContactEvent] {
        let count = Int(ap_world_contact_event_count(world))
        guard count > 0 else {
            ap_world_clear_contact_events(world)
            return []
        }
        let raw = [APContactEvent](unsafeUninitializedCapacity: count) { buffer, initialized in
            initialized = Int(ap_world_copy_contact_events(world, buffer.baseAddress, UInt32(count)))
        }
        ap_world_clear_contact_events(world)
        return raw.map { event in
            ContactEvent(
                bodyA: BodyID(rawValue: event.bodyA),
                bodyB: BodyID(rawValue: event.bodyB),
                point: SIMD3(event.point) / scale,
                normal: SIMD3(event.normal),
                approachSpeed: event.approachSpeed / scale
            )
        }
    }

    // MARK: Snapshots

    public func snapshot() -> PhysicsSnapshot {
        let size = ap_world_save_state(world, nil, 0)
        let bytes = [UInt8](unsafeUninitializedCapacity: size) { buffer, initialized in
            initialized = ap_world_save_state(world, buffer.baseAddress, size) == size ? size : 0
        }
        return PhysicsSnapshot(bytes: bytes)
    }

    /// False if the snapshot is from a world with different bodies. Pending contact
    /// events are dropped: they belong to the abandoned timeline.
    @discardableResult
    public func restore(_ snapshot: PhysicsSnapshot) -> Bool {
        snapshot.bytes.withUnsafeBytes { buffer in
            ap_world_restore_state(world, buffer.baseAddress, buffer.count)
        }
    }

    // MARK: Helpers

    private func velocity(of id: BodyID) -> (linear: SIMD3<Float>, angular: SIMD3<Float>) {
        var linear = APVec3()
        var angular = APVec3()
        ap_body_get_velocity(world, id.rawValue, &linear, &angular)
        return (SIMD3(linear) / scale, SIMD3(angular))
    }

    private func checked(_ raw: APBodyID) -> BodyID {
        precondition(raw != AP_INVALID_BODY, "Physics world is full: raise PhysicsWorldConfig.maxBodies")
        return BodyID(rawValue: raw)
    }
}

// MARK: - Conversions

private extension APVec3 {
    init(_ v: SIMD3<Float>) {
        self.init(x: v.x, y: v.y, z: v.z)
    }
}

private extension SIMD3 where Scalar == Float {
    init(_ v: APVec3) {
        self.init(v.x, v.y, v.z)
    }
}

private extension APQuat {
    init(_ q: simd_quatf) {
        self.init(x: q.imag.x, y: q.imag.y, z: q.imag.z, w: q.real)
    }
}

private extension simd_quatf {
    init(_ q: APQuat) {
        self.init(ix: q.x, iy: q.y, iz: q.z, r: q.w)
    }
}
