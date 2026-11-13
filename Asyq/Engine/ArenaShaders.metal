#include <metal_stdlib>
using namespace metal;

// The arena: a felt carpet fading into a warm studio haze, stitched markings, and bones lit
// like a product shot. Everything is shaded in linear light into an sRGB target.
// Structs mirror ArenaRenderer.swift.

struct FrameUniforms {
    float4x4 viewProjection;
    float4x4 inverseViewProjection;
    float4x4 lightViewProjection;
    float4 cameraPosition;   // xyz; w: time in seconds
    float4 lightDirection;   // xyz toward the light; w: intensity
    float4 lightColor;       // rgb
    float4 sky;              // rgb ambient from above; w: ambient strength
    float4 bounce;           // rgb ambient from below
    float4 haze;             // rgb horizon and fog; w: fog density
    float4 zenith;           // rgb
    float4 stage;            // xy: stage center (x, z); z, w: fade start and end radius
    float4 shadow;           // x: texel size; y: depth bias; z: strength
};

struct FieldUniforms {
    float4 felt;             // rgb
    float4 threadColor;      // rgb; a: opacity
    float4 circle;           // x: radius; y: line width; z: kon half length; w: parallel offset
    float4 throwLines;       // x: near line z; y: far line z; z: half width; w: thickness
    float4 aim;              // xy: from (x, z); zw: to (x, z)
    float4 aimStyle;         // x: visibility; y: landing ring radius
    float4 ripples[4];       // xy: center (x, z); z: age 0…1, below 0 unused; w: strength
    float4 contacts[24];     // xyz: bone center; w: footprint radius
    float4 counts;           // x: contacts in use
};

struct BoneVertex {
    float4 position;
    float4 normal;
};

struct BoneInstance {
    float4x4 model;
    float4 color;            // rgb albedo (linear); a: gloss 0…1
    float4 params;           // x: painted 0…1; y: glow 0…1
};

struct DotInstance {
    float4 position;         // xyz; w: radius in pixels
    float4 color;            // premultiplied
};

constexpr sampler shadowSampler(coord::normalized, filter::linear, address::clamp_to_edge, compare_func::less_equal);

// MARK: - Helpers

static float hash21(float2 p) {
    p = fract(p * float2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}

static float hash31(float3 p) {
    p = fract(p * float3(0.1031, 0.1030, 0.0973));
    p += dot(p, p.yzx + 33.33);
    return fract((p.x + p.y) * p.z);
}

static float noise2(float2 p) {
    float2 i = floor(p);
    float2 f = fract(p);
    float2 u = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash21(i), hash21(i + float2(1, 0)), u.x),
               mix(hash21(i + float2(0, 1)), hash21(i + float2(1, 1)), u.x), u.y);
}

static float noise3(float3 p) {
    float3 i = floor(p);
    float3 f = fract(p);
    float3 u = f * f * (3.0 - 2.0 * f);
    float a = mix(mix(hash31(i), hash31(i + float3(1, 0, 0)), u.x),
                  mix(hash31(i + float3(0, 1, 0)), hash31(i + float3(1, 1, 0)), u.x), u.y);
    float b = mix(mix(hash31(i + float3(0, 0, 1)), hash31(i + float3(1, 0, 1)), u.x),
                  mix(hash31(i + float3(0, 1, 1)), hash31(i + float3(1, 1, 1)), u.x), u.y);
    return mix(a, b, u.z);
}

static float fbm2(float2 p) {
    float sum = 0.0;
    float amplitude = 0.5;
    for (int octave = 0; octave < 3; octave++) {
        sum += noise2(p) * amplitude;
        p = p * 2.03 + 17.1;
        amplitude *= 0.5;
    }
    return sum / 0.875;
}

static float fbm3(float3 p) {
    float sum = 0.0;
    float amplitude = 0.5;
    for (int octave = 0; octave < 3; octave++) {
        sum += noise3(p) * amplitude;
        p = p * 2.07 + 11.3;
        amplitude *= 0.5;
    }
    return sum / 0.875;
}

/// A gentle shoulder instead of a hard clip, so bright highlights roll off.
static float3 tonemap(float3 color) {
    float3 x = max(color, 0.0);
    float3 shoulder = 0.82 + 0.18 * (1.0 - exp(-(x - 0.82) / 0.18));
    return select(x, shoulder, x > 0.82);
}

/// 3×3 hardware-filtered taps: a soft 4×4 texel penumbra.
static float sampleShadow(float3 worldPosition, constant FrameUniforms &frame, depth2d<float> shadowMap) {
    float4 light = frame.lightViewProjection * float4(worldPosition, 1.0);
    float3 ndc = light.xyz / light.w;
    float2 uv = ndc.xy * float2(0.5, -0.5) + 0.5;
    if (any(uv < 0.0) || any(uv > 1.0) || ndc.z > 1.0) { return 1.0; }
    float depth = ndc.z - frame.shadow.y;
    float texel = frame.shadow.x;
    float sum = 0.0;
    for (int y = -1; y <= 1; y++) {
        for (int x = -1; x <= 1; x++) {
            sum += shadowMap.sample_compare(shadowSampler, uv + float2(x, y) * texel * 1.3, depth);
        }
    }
    return mix(1.0, sum / 9.0, frame.shadow.z);
}

static float3 applyFog(float3 color, float3 worldPosition, constant FrameUniforms &frame) {
    float stageFade = smoothstep(frame.stage.z, frame.stage.w, distance(worldPosition.xz, frame.stage.xy));
    float distanceFog = 1.0 - exp(-distance(frame.cameraPosition.xyz, worldPosition) * frame.haze.w);
    return mix(color, frame.haze.rgb, max(stageFade, distanceFog));
}

static float segmentDistance(float2 p, float2 a, float2 b) {
    float2 pa = p - a;
    float2 ba = b - a;
    float h = clamp(dot(pa, ba) / max(dot(ba, ba), 1e-6), 0.0, 1.0);
    return length(pa - ba * h);
}

/// Coverage of a band of half width `halfWidth` at signed distance `d`, antialiased over `aa`.
static float band(float d, float halfWidth, float aa) {
    return 1.0 - smoothstep(halfWidth - aa, halfWidth + aa, d);
}

// MARK: - Background

struct BackgroundOut {
    float4 position [[position]];
    float2 ndc;
};

vertex BackgroundOut backgroundVertex(uint vid [[vertex_id]]) {
    float2 corner = float2((vid << 1) & 2, vid & 2) * 2.0 - 1.0;
    BackgroundOut out;
    out.position = float4(corner, 1.0, 1.0);
    out.ndc = corner;
    return out;
}

fragment float4 backgroundFragment(BackgroundOut in [[stage_in]], constant FrameUniforms &frame [[buffer(1)]]) {
    float4 far = frame.inverseViewProjection * float4(in.ndc, 1.0, 1.0);
    float3 direction = normalize(far.xyz / far.w - frame.cameraPosition.xyz);
    float rise = smoothstep(0.0, 0.45, direction.y);
    return float4(tonemap(mix(frame.haze.rgb, frame.zenith.rgb, rise)), 1.0);
}

// MARK: - Carpet

struct GroundOut {
    float4 position [[position]];
    float3 worldPosition;
};

vertex GroundOut groundVertex(uint vid [[vertex_id]], constant FrameUniforms &frame [[buffer(1)]]) {
    float2 corner = float2(vid & 1, (vid >> 1) & 1) * 2.0 - 1.0;
    float3 world = float3(frame.stage.x + corner.x * 40.0, 0.0, frame.stage.y + corner.y * 40.0);
    GroundOut out;
    out.position = frame.viewProjection * float4(world, 1.0);
    out.worldPosition = world;
    return out;
}

/// How much thread covers this point of the carpet: the circle, the kon and its parallels,
/// both throw lines. `pixel` is the world size of one pixel, for antialiasing.
static float markings(float2 p, float pixel, constant FieldUniforms &field) {
    float aa = max(pixel, 1e-4);
    float radius = field.circle.x;
    float lineHalf = field.circle.y * 0.5;

    // The circle, stitched: dashes along its length that blur into a solid line far away.
    float ringDistance = abs(length(p) - radius);
    float arc = atan2(p.y, p.x) * radius;
    float stitch = fract(arc / 0.07);
    float stitchMask = smoothstep(0.0, 0.1, stitch) * (1.0 - smoothstep(0.76, 0.86, stitch));
    float stitchFade = smoothstep(0.004, 0.012, pixel);
    float circle = band(ringDistance, lineHalf, aa) * mix(0.55 + 0.45 * stitchMask, 0.85, stitchFade);

    float konHalf = field.circle.z;
    float kon = band(segmentDistance(p, float2(-konHalf, 0.0), float2(konHalf, 0.0)), 0.006, aa) * 0.45;

    float offset = field.circle.w;
    float dash = smoothstep(0.0, 0.08, fract(p.x / 0.05)) * (1.0 - smoothstep(0.55, 0.65, fract(p.x / 0.05)));
    dash = mix(dash, 0.6, stitchFade);
    float parallels = max(
        band(segmentDistance(p, float2(-konHalf, offset), float2(konHalf, offset)), 0.0035, aa),
        band(segmentDistance(p, float2(-konHalf, -offset), float2(konHalf, -offset)), 0.0035, aa)
    ) * dash * 0.6;

    float throwHalf = field.throwLines.z;
    float thickness = field.throwLines.w * 0.5;
    float throws = max(
        band(segmentDistance(p, float2(-throwHalf, field.throwLines.x), float2(throwHalf, field.throwLines.x)), thickness, aa),
        band(segmentDistance(p, float2(-throwHalf, field.throwLines.y), float2(throwHalf, field.throwLines.y)), thickness, aa)
    ) * 0.9;

    return max(max(circle, kon), max(parallels, throws));
}

/// The aim guide: dots flowing from the spot toward where the saqa will land, and a pulsing
/// ring there.
static float aimGuide(float2 p, float pixel, float time, constant FieldUniforms &field) {
    float visibility = field.aimStyle.x;
    if (visibility <= 0.0) { return 0.0; }
    float aa = max(pixel, 1e-4);
    float2 from = field.aim.xy;
    float2 to = field.aim.zw;
    float2 along = to - from;
    float length2 = max(length(along), 1e-4);
    float2 direction = along / length2;
    float2 local = p - from;
    float t = dot(local, direction);
    float side = dot(local, float2(-direction.y, direction.x));
    float spacing = 0.16;
    float cell = (fract((t - time * 0.35) / spacing) - 0.5) * spacing;
    float dotMask = band(length(float2(cell, side)), 0.013, aa);
    float span = smoothstep(0.0, 0.5, t) * (1.0 - smoothstep(length2 - 0.25, length2 - 0.12, t));
    float guide = dotMask * span * 0.55;

    float ringRadius = field.aimStyle.y * (1.0 + 0.08 * sin(time * 5.0));
    float toTarget = distance(p, to);
    float ring = band(abs(toTarget - ringRadius), 0.006, aa);
    float fill = (1.0 - smoothstep(0.0, ringRadius, toTarget)) * 0.14;
    return max(guide, max(ring, fill)) * visibility;
}

static float ripples(float2 p, float pixel, constant FieldUniforms &field) {
    float aa = max(pixel, 1e-4);
    float sum = 0.0;
    for (int index = 0; index < 4; index++) {
        float4 ripple = field.ripples[index];
        if (ripple.z < 0.0) { continue; }
        float age = ripple.z;
        float radius = 0.02 + age * 0.15;
        float ring = band(abs(distance(p, ripple.xy) - radius), 0.002 + age * 0.002, aa);
        sum = max(sum, ring * (1.0 - age) * (1.0 - age) * ripple.w);
    }
    return sum;
}

/// Soft darkening under and around each bone: the contact shadow a shadow map is too coarse for.
static float contactOcclusion(float2 p, constant FieldUniforms &field) {
    float occlusion = 1.0;
    int count = int(field.counts.x);
    for (int index = 0; index < count; index++) {
        float4 contact = field.contacts[index];
        float radius = contact.w;
        float lift = saturate(1.0 - max(contact.y - radius * 0.7, 0.0) / 0.06);
        float d = distance(p, contact.xz);
        float shade = (1.0 - smoothstep(radius * 0.35, radius * 2.0, d)) * lift;
        occlusion *= 1.0 - 0.6 * shade;
    }
    return occlusion;
}

fragment float4 groundFragment(GroundOut in [[stage_in]],
                               constant FrameUniforms &frame [[buffer(1)]],
                               constant FieldUniforms &field [[buffer(2)]],
                               depth2d<float> shadowMap [[texture(0)]]) {
    float3 p = in.worldPosition;
    float2 xz = p.xz;
    float pixel = length(fwidth(xz));
    float time = frame.cameraPosition.w;

    // Felt: broad blotches plus fibers that fade before they can shimmer.
    float fiberFade = 1.0 - smoothstep(0.0015, 0.006, pixel);
    float coarse = fbm2(xz * 2.2);
    float fibers = fiberFade > 0.0 ? fbm2(xz * 260.0) : 0.5;
    float3 felt = field.felt.rgb * (1.0 + (coarse - 0.5) * 0.12 + (fibers - 0.5) * 0.22 * fiberFade);

    float3 n = float3(0.0, 1.0, 0.0);
    float3 toLight = frame.lightDirection.xyz;
    float3 toEye = normalize(frame.cameraPosition.xyz - p);
    float shadow = sampleShadow(p, frame, shadowMap);
    float occlusion = contactOcclusion(xz, field);
    float3 direct = frame.lightColor.rgb * frame.lightDirection.w * saturate(dot(n, toLight)) * shadow * occlusion;
    float3 ambient = frame.sky.rgb * frame.sky.w * occlusion;

    float stitching = markings(xz, pixel, field) * field.threadColor.a;
    float3 albedo = mix(felt, field.threadColor.rgb, stitching);
    float3 color = albedo * (direct + ambient);

    // Felt catches light at grazing angles.
    color += pow(1.0 - saturate(dot(n, toEye)), 4.0) * 0.14 * frame.haze.rgb * (0.4 + 0.6 * shadow);

    float glow = max(aimGuide(xz, pixel, time, field), ripples(xz, pixel, field));
    color = mix(color, field.threadColor.rgb * (0.9 + 0.25 * shadow), glow * 0.85);

    return float4(tonemap(applyFog(color, p, frame)), 1.0);
}

// MARK: - Bones

struct BoneOut {
    float4 position [[position]];
    float3 worldPosition;
    float3 normal;
    float3 objectPosition;
    float3 objectNormal;
    float4 color [[flat]];
    float4 params [[flat]];
};

vertex BoneOut boneVertex(uint vid [[vertex_id]],
                          uint iid [[instance_id]],
                          const device BoneVertex *vertices [[buffer(0)]],
                          constant FrameUniforms &frame [[buffer(1)]],
                          const device BoneInstance *instances [[buffer(2)]]) {
    BoneInstance instance = instances[iid];
    BoneVertex vertex_ = vertices[vid];
    float4 world = instance.model * float4(vertex_.position.xyz, 1.0);
    BoneOut out;
    out.position = frame.viewProjection * world;
    out.worldPosition = world.xyz;
    out.normal = (instance.model * float4(vertex_.normal.xyz, 0.0)).xyz;
    out.objectPosition = vertex_.position.xyz;
    out.objectNormal = vertex_.normal.xyz;
    out.color = instance.color;
    out.params = instance.params;
    return out;
}

vertex float4 boneShadowVertex(uint vid [[vertex_id]],
                               uint iid [[instance_id]],
                               const device BoneVertex *vertices [[buffer(0)]],
                               constant FrameUniforms &frame [[buffer(1)]],
                               const device BoneInstance *instances [[buffer(2)]]) {
    return frame.lightViewProjection * (instances[iid].model * float4(vertices[vid].position.xyz, 1.0));
}

fragment float4 boneFragment(BoneOut in [[stage_in]],
                             constant FrameUniforms &frame [[buffer(1)]],
                             constant float4 &extents [[buffer(3)]],
                             depth2d<float> shadowMap [[texture(0)]]) {
    float3 n = normalize(in.normal);
    float3 toEye = normalize(frame.cameraPosition.xyz - in.worldPosition);
    float3 toLight = frame.lightDirection.xyz;
    float3 object = in.objectPosition;
    float painted = in.params.x;
    float gloss = in.color.a;

    // Bone: fine grain and faint striations along the length, fixed to the bone.
    float grain = fbm3(object * 300.0);
    float striation = 0.5 + 0.5 * sin(object.x * 700.0 + fbm3(object * 140.0) * 5.0);
    float3 albedo = in.color.rgb * (1.0 + (grain - 0.5) * mix(0.12, 0.05, painted) + (striation - 0.5) * 0.04 * (1.0 - painted));

    // The shik side's hollow: a shallow dimple in the middle of the −Y face.
    float onShikFace = saturate((-in.objectNormal.y - 0.8) * 5.0);
    float2 dimple = object.xz / (extents.xz * float2(0.6, 0.5));
    float hollow = onShikFace * (1.0 - smoothstep(0.3, 1.0, length(dimple)));

    float shadow = sampleShadow(in.worldPosition + n * 0.003, frame, shadowMap);
    float facing = dot(n, toLight);
    float lambert = saturate(facing);
    // Wrapped light, tinted warm in the terminator: light scattering inside the bone.
    float wrap = saturate((facing + 0.5) / 1.5);
    float3 scatter = albedo * float3(1.0, 0.58, 0.40) * (wrap - lambert) * mix(0.85, 0.25, painted);

    float hemisphere = n.y * 0.5 + 0.5;
    float3 ambient = mix(frame.bounce.rgb, frame.sky.rgb, hemisphere) * frame.sky.w;
    float nearCarpet = saturate(in.worldPosition.y / 0.025 + hemisphere * 0.7);
    float occlusion = mix(0.42, 1.0, nearCarpet) * (1.0 - hollow * 0.5);

    float3 halfway = normalize(toLight + toEye);
    float shininess = mix(16.0, 220.0, gloss);
    float fresnel = 0.04 + 0.96 * pow(1.0 - saturate(dot(halfway, toEye)), 5.0);
    float specular = pow(saturate(dot(n, halfway)), shininess) * (shininess + 8.0) / 25.0 * fresnel * lambert;

    float3 light = frame.lightColor.rgb * frame.lightDirection.w;
    float3 color = albedo * (light * lambert * shadow + ambient * occlusion)
        + scatter * light * (0.35 + 0.65 * shadow)
        + specular * light * shadow * mix(0.5, 1.0, gloss);

    // A soft rim lifts the silhouette off the carpet.
    float rim = pow(1.0 - saturate(dot(n, toEye)), 3.5);
    color += rim * 0.10 * frame.sky.rgb * occlusion;
    color += in.params.y * float3(1.0, 0.82, 0.55) * (0.18 + rim * 0.9);

    return float4(tonemap(applyFog(color, in.worldPosition, frame)), 1.0);
}

// MARK: - Dots

struct DotOut {
    float4 position [[position]];
    float2 corner;
    float4 color [[flat]];
};

vertex DotOut dotVertex(uint vid [[vertex_id]],
                        uint iid [[instance_id]],
                        constant FrameUniforms &frame [[buffer(1)]],
                        const device DotInstance *dots [[buffer(2)]],
                        constant float2 &viewport [[buffer(3)]]) {
    DotInstance dot_ = dots[iid];
    float2 corner = float2(vid & 1, (vid >> 1) & 1) * 2.0 - 1.0;
    float4 clip = frame.viewProjection * float4(dot_.position.xyz, 1.0);
    clip.xy += corner * dot_.position.w * 2.0 / viewport * clip.w;
    DotOut out;
    out.position = clip;
    out.corner = corner;
    out.color = dot_.color;
    return out;
}

fragment float4 dotFragment(DotOut in [[stage_in]]) {
    float radius = length(in.corner);
    float alpha = 1.0 - smoothstep(0.6, 1.0, radius);
    return in.color * alpha;
}
