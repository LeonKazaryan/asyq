// A small C facade over Jolt Physics: only what Asyq needs. Swift sees this header and
// nothing of Jolt's C++, so the app target builds without C++ interop.
//
// All values are in raw Jolt units. The Swift wrapper converts from meters (lengthScale).
// A world is not thread-safe: use it from one thread at a time.

#ifndef ASYQ_PHYSICS_H
#define ASYQ_PHYSICS_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct APWorld APWorld;
typedef struct APShape APShape;
typedef uint32_t APBodyID;

/// Returned when a body couldn't be created (the world is full).
#define AP_INVALID_BODY 0xffffffffu
/// Surface materials index an AP_MAX_MATERIALS × AP_MAX_MATERIALS pair table.
#define AP_MAX_MATERIALS 8
/// Contact events kept between drains; extras are counted and dropped.
#define AP_MAX_CONTACT_EVENTS 512

typedef struct { float x, y, z; } APVec3;
typedef struct { float x, y, z, w; } APQuat;

typedef struct {
    APVec3 gravity;
    uint32_t maxBodies;
    uint32_t velocitySteps;
    uint32_t positionSteps;
    float penetrationSlop;
    float speculativeContactDistance;
    float minVelocityForRestitution;
    float pointVelocitySleepThreshold;
    float timeBeforeSleep;
    /// Fraction of a body's inner radius it may move in one step before linear casting kicks in.
    float linearCastThreshold;
    /// Applied to every dynamic body. Jolt's default assumes 60 Hz steps.
    float maxAngularVelocity;
} APWorldSettings;

typedef struct {
    float mass;
    uint8_t material;
    APVec3 position;
    APQuat rotation;
    float linearDamping;
    float angularDamping;
    /// Continuous collision detection (Jolt's LinearCast motion quality).
    bool linearCast;
    bool startsAsleep;
} APBodySettings;

typedef struct {
    APBodyID bodyA;
    APBodyID bodyB;
    APVec3 point;
    /// From bodyA towards bodyB.
    APVec3 normal;
    /// Closing speed along the normal when the contact appeared, never negative.
    float approachSpeed;
} APContactEvent;

/// Jolt's own defaults (tuned for 1 m objects at 60 Hz).
void ap_world_settings_default(APWorldSettings *outSettings);

APWorld *ap_world_create(const APWorldSettings *settings);
void ap_world_destroy(APWorld *world);

/// Friction and restitution for contacts between two materials, both orders.
/// Pairs never set combine the bodies' defaults the Jolt way.
void ap_world_set_surface_pair(APWorld *world, uint8_t materialA, uint8_t materialB, float friction, float restitution);

/// A box whose edges and corners are rounded by exactly `convexRadius` (clamped to the
/// smallest half extent). `centerOfMassOffset` moves the center of mass, not the shape.
APShape *ap_shape_create_rounded_box(APVec3 halfExtents, float convexRadius, APVec3 centerOfMassOffset);
/// NULL if the points don't form a hull.
APShape *ap_shape_create_convex_hull(const APVec3 *points, uint32_t count, float maxConvexRadius, APVec3 centerOfMassOffset);
void ap_shape_release(APShape *shape);

APBodyID ap_world_add_static_box(APWorld *world, APVec3 halfExtents, APVec3 position, uint8_t material);
APBodyID ap_world_add_body(APWorld *world, const APShape *shape, const APBodySettings *settings);
void ap_world_remove_body(APWorld *world, APBodyID body);
uint32_t ap_world_body_count(const APWorld *world);

/// One step with one collision step.
void ap_world_step(APWorld *world, float deltaTime);

void ap_body_get_transform(const APWorld *world, APBodyID body, APVec3 *outPosition, APQuat *outRotation);
void ap_body_set_transform(APWorld *world, APBodyID body, APVec3 position, APQuat rotation, bool activate);
void ap_body_get_velocity(const APWorld *world, APBodyID body, APVec3 *outLinear, APVec3 *outAngular);
/// Wakes the body.
void ap_body_set_velocity(APWorld *world, APBodyID body, APVec3 linear, APVec3 angular);
bool ap_body_is_active(const APWorld *world, APBodyID body);
void ap_body_activate(APWorld *world, APBodyID body);
void ap_body_deactivate(APWorld *world, APBodyID body);
bool ap_world_has_active_bodies(const APWorld *world);

uint32_t ap_world_contact_event_count(const APWorld *world);
/// Copies up to `capacity` events in the order they happened; returns how many.
uint32_t ap_world_copy_contact_events(const APWorld *world, APContactEvent *outEvents, uint32_t capacity);
void ap_world_clear_contact_events(APWorld *world);
/// Events lost because the buffer was full since the last clear.
uint32_t ap_world_dropped_contact_events(const APWorld *world);

/// Serializes bodies, contacts and global state. Returns the size needed; writes only if
/// `capacity` is enough. Call with NULL/0 first to size the buffer.
size_t ap_world_save_state(const APWorld *world, void *outBuffer, size_t capacity);
/// Restores a state saved from a world with the same bodies. False if the data doesn't fit.
bool ap_world_restore_state(APWorld *world, const void *data, size_t size);

/// Sine and cosine with the same bits on every device: Jolt's own polynomial, unlike libm,
/// which may change between OS versions. Use for anything that feeds the simulation.
void ap_sin_cos(float angle, float *outSin, float *outCos);

#ifdef __cplusplus
}
#endif

#endif
