#include "asyq_physics.h"

#include <Jolt/Jolt.h>

#include <Jolt/Core/Factory.h>
#include <Jolt/Core/JobSystemSingleThreaded.h>
#include <Jolt/Core/TempAllocator.h>
#include <Jolt/Physics/Body/BodyCreationSettings.h>
#include <Jolt/Physics/Collision/Shape/BoxShape.h>
#include <Jolt/Physics/Collision/Shape/ConvexHullShape.h>
#include <Jolt/Physics/Collision/Shape/OffsetCenterOfMassShape.h>
#include <Jolt/Physics/PhysicsSettings.h>
#include <Jolt/Physics/PhysicsSystem.h>
#include <Jolt/Physics/StateRecorderImpl.h>
#include <Jolt/RegisterTypes.h>

#include <algorithm>
#include <cstring>
#include <mutex>
#include <vector>

using namespace JPH;

namespace {

namespace Layers {
constexpr ObjectLayer staticLayer = 0;
constexpr ObjectLayer movingLayer = 1;
} // namespace Layers

namespace BroadPhaseLayers {
constexpr BroadPhaseLayer staticLayer(0);
constexpr BroadPhaseLayer movingLayer(1);
constexpr uint count = 2;
} // namespace BroadPhaseLayers

class ObjectLayerPairFilterImpl final : public ObjectLayerPairFilter {
public:
    bool ShouldCollide(ObjectLayer a, ObjectLayer b) const override {
        // Static against static never needs testing.
        return a == Layers::movingLayer || b == Layers::movingLayer;
    }
};

class BroadPhaseLayerInterfaceImpl final : public BroadPhaseLayerInterface {
public:
    uint GetNumBroadPhaseLayers() const override { return BroadPhaseLayers::count; }

    BroadPhaseLayer GetBroadPhaseLayer(ObjectLayer layer) const override {
        return layer == Layers::staticLayer ? BroadPhaseLayers::staticLayer : BroadPhaseLayers::movingLayer;
    }

#if defined(JPH_EXTERNAL_PROFILE) || defined(JPH_PROFILE_ENABLED)
    const char *GetBroadPhaseLayerName(BroadPhaseLayer layer) const override {
        return layer == BroadPhaseLayers::staticLayer ? "static" : "moving";
    }
#endif
};

class ObjectVsBroadPhaseLayerFilterImpl final : public ObjectVsBroadPhaseLayerFilter {
public:
    bool ShouldCollide(ObjectLayer layer, BroadPhaseLayer broadPhaseLayer) const override {
        return layer == Layers::movingLayer || broadPhaseLayer == BroadPhaseLayers::movingLayer;
    }
};

struct SurfacePair {
    float friction = 0;
    float restitution = 0;
    bool isSet = false;
};

/// Materials live in the low byte of a body's user data.
uint8_t materialOf(const Body &body) {
    return uint8_t(body.GetUserData() & 0xff) % AP_MAX_MATERIALS;
}

/// Applies the material pair table and records impacts. Jolt calls it from inside
/// `Update`; with the single-threaded job system that's always the caller's thread, so
/// events arrive in a deterministic order and need no lock.
class WorldContactListener final : public ContactListener {
public:
    SurfacePair pairs[AP_MAX_MATERIALS][AP_MAX_MATERIALS];
    std::vector<APContactEvent> events;
    uint32_t droppedEvents = 0;

    WorldContactListener() { events.reserve(AP_MAX_CONTACT_EVENTS); }

    void OnContactAdded(const Body &body1, const Body &body2, const ContactManifold &manifold, ContactSettings &settings) override {
        applySurface(body1, body2, settings);
        record(body1, body2, manifold);
    }

    void OnContactPersisted(const Body &body1, const Body &body2, const ContactManifold &, ContactSettings &settings) override {
        // Jolt recomputes the combined values for persisted contacts too.
        applySurface(body1, body2, settings);
    }

private:
    void applySurface(const Body &body1, const Body &body2, ContactSettings &settings) const {
        const SurfacePair &pair = pairs[materialOf(body1)][materialOf(body2)];
        if (!pair.isSet) return;
        settings.mCombinedFriction = pair.friction;
        settings.mCombinedRestitution = pair.restitution;
    }

    void record(const Body &body1, const Body &body2, const ContactManifold &manifold) {
        if (events.size() >= AP_MAX_CONTACT_EVENTS) {
            droppedEvents += 1;
            return;
        }
        // Jolt hands a static body first; callers want the moving one as bodyA.
        const bool swap = body1.IsStatic() && !body2.IsStatic();
        const Body &first = swap ? body2 : body1;
        const Body &second = swap ? body1 : body2;
        // The middle of the contact patch: steadier than any single manifold point.
        Vec3 sum = Vec3::sZero();
        const uint pointCount = std::max<uint>(manifold.mRelativeContactPointsOn1.size(), 1);
        for (uint i = 0; i < manifold.mRelativeContactPointsOn1.size(); ++i) {
            sum += manifold.mRelativeContactPointsOn1[i];
        }
        const RVec3 point = manifold.mBaseOffset + sum / float(pointCount);
        // Jolt's normal pushes body 2 out of body 1; keep it pointing from first to second.
        const Vec3 normal = swap ? -manifold.mWorldSpaceNormal : manifold.mWorldSpaceNormal;
        // They close when the first outruns the second along the normal. Velocities here are
        // from before the solver: the speed of the impact.
        const Vec3 relative = first.GetPointVelocity(point) - second.GetPointVelocity(point);
        const float approach = std::max(relative.Dot(normal), 0.0f);

        APContactEvent event;
        event.bodyA = first.GetID().GetIndexAndSequenceNumber();
        event.bodyB = second.GetID().GetIndexAndSequenceNumber();
        event.point = {float(point.GetX()), float(point.GetY()), float(point.GetZ())};
        event.normal = {normal.GetX(), normal.GetY(), normal.GetZ()};
        event.approachSpeed = approach;
        events.push_back(event);
    }
};

void registerJoltOnce() {
    static std::once_flag flag;
    std::call_once(flag, [] {
        RegisterDefaultAllocator();
        Factory::sInstance = new Factory();
        RegisterTypes();
    });
}

Vec3 vec(APVec3 v) { return Vec3(v.x, v.y, v.z); }
APVec3 vec(Vec3Arg v) { return {v.GetX(), v.GetY(), v.GetZ()}; }
// Normalized, since a slightly off quaternion from Swift trips Jolt's asserts and skews rotation.
Quat quat(APQuat q) { return Quat(q.x, q.y, q.z, q.w).Normalized(); }
APQuat quat(QuatArg q) { return {q.GetX(), q.GetY(), q.GetZ(), q.GetW()}; }
BodyID bodyID(APBodyID id) { return BodyID(id); }

} // namespace

struct APShape {
    RefConst<Shape> shape;
};

struct APWorld {
    // Order matters: the allocator and layer tables must outlive the physics system.
    TempAllocatorImpl tempAllocator{4 * 1024 * 1024};
    JobSystemSingleThreaded jobSystem{cMaxPhysicsJobs};
    BroadPhaseLayerInterfaceImpl broadPhaseLayers;
    ObjectVsBroadPhaseLayerFilterImpl objectVsBroadPhase;
    ObjectLayerPairFilterImpl objectPairs;
    WorldContactListener listener;
    PhysicsSystem system;
    float maxAngularVelocity = 0;

    BodyInterface &bodies() { return system.GetBodyInterfaceNoLock(); }
    const BodyInterface &bodies() const { return system.GetBodyInterfaceNoLock(); }
};

extern "C" {

void ap_world_settings_default(APWorldSettings *outSettings) {
    const PhysicsSettings defaults;
    outSettings->gravity = {0, -9.81f, 0};
    outSettings->maxBodies = 1024;
    outSettings->velocitySteps = defaults.mNumVelocitySteps;
    outSettings->positionSteps = defaults.mNumPositionSteps;
    outSettings->penetrationSlop = defaults.mPenetrationSlop;
    outSettings->speculativeContactDistance = defaults.mSpeculativeContactDistance;
    outSettings->minVelocityForRestitution = defaults.mMinVelocityForRestitution;
    outSettings->pointVelocitySleepThreshold = defaults.mPointVelocitySleepThreshold;
    outSettings->timeBeforeSleep = defaults.mTimeBeforeSleep;
    outSettings->linearCastThreshold = defaults.mLinearCastThreshold;
    outSettings->maxAngularVelocity = BodyCreationSettings().mMaxAngularVelocity;
}

APWorld *ap_world_create(const APWorldSettings *settings) {
    registerJoltOnce();
    auto *world = new APWorld();
    const uint maxBodies = std::max<uint>(settings->maxBodies, 2);
    // Pairs and contacts grow with crowding, not just body count; a pile of 20 bones has
    // far fewer than these.
    const uint maxPairs = std::max<uint>(maxBodies * 16, 256);
    world->system.Init(maxBodies, 0, maxPairs, maxPairs, world->broadPhaseLayers, world->objectVsBroadPhase, world->objectPairs);
    world->system.SetContactListener(&world->listener);
    world->system.SetGravity(vec(settings->gravity));

    PhysicsSettings physics;
    physics.mNumVelocitySteps = settings->velocitySteps;
    physics.mNumPositionSteps = settings->positionSteps;
    physics.mPenetrationSlop = settings->penetrationSlop;
    physics.mSpeculativeContactDistance = settings->speculativeContactDistance;
    physics.mMinVelocityForRestitution = settings->minVelocityForRestitution;
    physics.mPointVelocitySleepThreshold = settings->pointVelocitySleepThreshold;
    physics.mTimeBeforeSleep = settings->timeBeforeSleep;
    physics.mLinearCastThreshold = settings->linearCastThreshold;
    physics.mDeterministicSimulation = true;
    world->system.SetPhysicsSettings(physics);
    world->maxAngularVelocity = settings->maxAngularVelocity;
    return world;
}

void ap_world_destroy(APWorld *world) {
    delete world;
}

void ap_world_set_surface_pair(APWorld *world, uint8_t materialA, uint8_t materialB, float friction, float restitution) {
    const SurfacePair pair{friction, restitution, true};
    const uint8_t a = materialA % AP_MAX_MATERIALS;
    const uint8_t b = materialB % AP_MAX_MATERIALS;
    world->listener.pairs[a][b] = pair;
    world->listener.pairs[b][a] = pair;
}

static APShape *finishShape(const ShapeSettings &settings, APVec3 centerOfMassOffset) {
    ShapeSettings::ShapeResult result = settings.Create();
    if (result.HasError()) return nullptr;
    RefConst<Shape> shape = result.Get();
    if (centerOfMassOffset.x != 0 || centerOfMassOffset.y != 0 || centerOfMassOffset.z != 0) {
        ShapeSettings::ShapeResult offset = OffsetCenterOfMassShapeSettings(vec(centerOfMassOffset), shape.GetPtr()).Create();
        if (offset.HasError()) return nullptr;
        shape = offset.Get();
    }
    return new APShape{shape};
}

APShape *ap_shape_create_rounded_box(APVec3 halfExtents, float convexRadius, APVec3 centerOfMassOffset) {
    const float smallest = std::min({halfExtents.x, halfExtents.y, halfExtents.z});
    const float radius = std::clamp(convexRadius, 0.0f, smallest);
    return finishShape(BoxShapeSettings(vec(halfExtents), radius), centerOfMassOffset);
}

APShape *ap_shape_create_convex_hull(const APVec3 *points, uint32_t count, float maxConvexRadius, APVec3 centerOfMassOffset) {
    if (points == nullptr || count < 4) return nullptr;
    Array<Vec3> hull;
    hull.reserve(count);
    for (uint32_t i = 0; i < count; ++i) hull.push_back(vec(points[i]));
    return finishShape(ConvexHullShapeSettings(hull, maxConvexRadius), centerOfMassOffset);
}

void ap_shape_release(APShape *shape) {
    delete shape;
}

APBodyID ap_world_add_static_box(APWorld *world, APVec3 halfExtents, APVec3 position, uint8_t material) {
    // Sharp corners: a floor or wall has no reason to be rounded.
    BodyCreationSettings settings(new BoxShape(vec(halfExtents), 0.0f), RVec3(vec(position)), Quat::sIdentity(), EMotionType::Static, Layers::staticLayer);
    settings.mUserData = material;
    const BodyID id = world->bodies().CreateAndAddBody(settings, EActivation::DontActivate);
    return id.IsInvalid() ? AP_INVALID_BODY : id.GetIndexAndSequenceNumber();
}

APBodyID ap_world_add_body(APWorld *world, const APShape *shape, const APBodySettings *description) {
    BodyCreationSettings settings(shape->shape, RVec3(vec(description->position)), quat(description->rotation), EMotionType::Dynamic, Layers::movingLayer);
    // Mass from the caller, inertia from the shape's geometry scaled to that mass.
    settings.mOverrideMassProperties = EOverrideMassProperties::CalculateInertia;
    settings.mMassPropertiesOverride.mMass = description->mass;
    settings.mLinearDamping = description->linearDamping;
    settings.mAngularDamping = description->angularDamping;
    settings.mMotionQuality = description->linearCast ? EMotionQuality::LinearCast : EMotionQuality::Discrete;
    settings.mMaxAngularVelocity = world->maxAngularVelocity;
    settings.mUserData = description->material;
    const EActivation activation = description->startsAsleep ? EActivation::DontActivate : EActivation::Activate;
    const BodyID id = world->bodies().CreateAndAddBody(settings, activation);
    return id.IsInvalid() ? AP_INVALID_BODY : id.GetIndexAndSequenceNumber();
}

void ap_world_remove_body(APWorld *world, APBodyID body) {
    world->bodies().RemoveBody(bodyID(body));
    world->bodies().DestroyBody(bodyID(body));
}

uint32_t ap_world_body_count(const APWorld *world) {
    return world->system.GetNumBodies();
}

void ap_world_step(APWorld *world, float deltaTime) {
    world->system.Update(deltaTime, 1, &world->tempAllocator, &world->jobSystem);
}

void ap_body_get_transform(const APWorld *world, APBodyID body, APVec3 *outPosition, APQuat *outRotation) {
    RVec3 position;
    Quat rotation;
    world->bodies().GetPositionAndRotation(bodyID(body), position, rotation);
    *outPosition = vec(position);
    *outRotation = quat(rotation);
}

void ap_body_set_transform(APWorld *world, APBodyID body, APVec3 position, APQuat rotation, bool activate) {
    world->bodies().SetPositionAndRotation(bodyID(body), RVec3(vec(position)), quat(rotation), activate ? EActivation::Activate : EActivation::DontActivate);
}

void ap_body_get_velocity(const APWorld *world, APBodyID body, APVec3 *outLinear, APVec3 *outAngular) {
    *outLinear = vec(world->bodies().GetLinearVelocity(bodyID(body)));
    *outAngular = vec(world->bodies().GetAngularVelocity(bodyID(body)));
}

void ap_body_set_velocity(APWorld *world, APBodyID body, APVec3 linear, APVec3 angular) {
    // Jolt ignores velocities on a sleeping body, so wake it first.
    world->bodies().ActivateBody(bodyID(body));
    world->bodies().SetLinearAndAngularVelocity(bodyID(body), vec(linear), vec(angular));
}

bool ap_body_is_active(const APWorld *world, APBodyID body) {
    return world->bodies().IsActive(bodyID(body));
}

void ap_body_activate(APWorld *world, APBodyID body) {
    world->bodies().ActivateBody(bodyID(body));
}

void ap_body_deactivate(APWorld *world, APBodyID body) {
    world->bodies().DeactivateBody(bodyID(body));
}

bool ap_world_has_active_bodies(const APWorld *world) {
    return world->system.GetNumActiveBodies(EBodyType::RigidBody) > 0;
}

uint32_t ap_world_contact_event_count(const APWorld *world) {
    return uint32_t(world->listener.events.size());
}

uint32_t ap_world_copy_contact_events(const APWorld *world, APContactEvent *outEvents, uint32_t capacity) {
    const uint32_t count = std::min<uint32_t>(capacity, uint32_t(world->listener.events.size()));
    if (count > 0) std::memcpy(outEvents, world->listener.events.data(), count * sizeof(APContactEvent));
    return count;
}

void ap_world_clear_contact_events(APWorld *world) {
    world->listener.events.clear();
    world->listener.droppedEvents = 0;
}

uint32_t ap_world_dropped_contact_events(const APWorld *world) {
    return world->listener.droppedEvents;
}

size_t ap_world_save_state(const APWorld *world, void *outBuffer, size_t capacity) {
    StateRecorderImpl recorder;
    world->system.SaveState(recorder);
    const std::string data = recorder.GetData();
    if (outBuffer != nullptr && capacity >= data.size()) std::memcpy(outBuffer, data.data(), data.size());
    return data.size();
}

bool ap_world_restore_state(APWorld *world, const void *data, size_t size) {
    if (data == nullptr || size == 0) return false;
    StateRecorderImpl recorder;
    recorder.WriteBytes(data, size);
    recorder.Rewind();
    const bool restored = world->system.RestoreState(recorder);
    // Events from before the snapshot don't belong to the restored timeline.
    world->listener.events.clear();
    world->listener.droppedEvents = 0;
    return restored;
}

void ap_sin_cos(float angle, float *outSin, float *outCos) {
    Vec4 sine, cosine;
    Vec4::sReplicate(angle).SinCos(sine, cosine);
    *outSin = sine.GetX();
    *outCos = cosine.GetX();
}

} // extern "C"
