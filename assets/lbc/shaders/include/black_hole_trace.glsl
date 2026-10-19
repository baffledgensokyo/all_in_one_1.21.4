#ifndef LBC_BH_TRACE_COUNT
#define LBC_BH_TRACE_COUNT 16
#endif

#include <minecraft:globals.glsl>
#include <lbc:black_hole_data.glsl>
#include <lbc:black_hole_disk.glsl>
#include <lbc:black_hole_sampling.glsl>

uniform sampler2D SceneSampler;
uniform sampler2D SceneDepthSampler;
uniform sampler2D CoarseSampler;
#ifdef LBC_BH_CACHED_GEOMETRY
uniform sampler2D GeometrySampler;
#endif
layout(std140) uniform BlackHoleConfig {
    float ResolutionScale;
};
layout(location = 0) in vec2 texCoord;
layout(location = 1) flat in mat4 holeInverseVP;
layout(location = 5) flat in mat4 holeVP;
layout(location = 9) flat in vec4 holeObjects[LBC_BH_TRACE_COUNT];
layout(location = 25) flat in uvec4 holeStyles[(LBC_BH_TRACE_COUNT + 3) / 4];
layout(location = 29) flat in uint holeMask;
layout(location = 30) flat in vec4 holePeripheral;
layout(location = 0) out vec4 fragColor;

const float BH_REACH = 14.0;
const int BH_STEPS = 192;
float bhSegmentFraction = 0.0;
// Resolve metadata: 0=untouched, 0.5=missing/sky, 0.75=capture/opaque disk,
// 1=an actual reconstructed surface. Scene alpha is restored by resolve.
float bhTraceKind = 0.0;
bool bhEmptyVoxelValid = false;
ivec3 bhEmptyVoxel;
bool bhVisibleSurfacesOnly = false;
bool bhTraceWarp = false;
vec2 bhTraceUV;

vec3 bhUnproject(vec2 uv, float depth) {
    vec4 point = holeInverseVP * vec4(uv * 2.0 - 1.0, depth, 1.0);
    return point.xyz / point.w;
}

vec3 bhDirection(vec2 uv) {
    vec3 a = bhUnproject(uv, 0.25);
    vec3 b = bhUnproject(uv, 0.75);
    return normalize(dot(a, a) < dot(b, b) ? b - a : a - b);
}

bool bhProject(vec3 position, out vec2 uv) {
    vec4 clip = holeVP * vec4(position, 1.0);
    uv = clip.xy / max(clip.w, 1e-8) * 0.5 + 0.5;
    return clip.w > 0.00001;
}

vec2 bhMirrorUV(vec2 uv) {
    // ... mirrored | original | mirrored ... on BOTH axes. Clamp only a
    // half texel after folding, so filtering never wraps across a tile edge.
    vec2 mirrored = 1.0 - abs(mod(uv, 2.0) - 1.0);
    vec2 halfTexel = 0.5 / vec2(textureSize(SceneSampler, 0));
    return clamp(mirrored, halfTexel, vec2(1.0) - halfTexel);
}

vec3 bhSampleBackground(vec2 uv) {
    vec2 source = bhMirrorUV(uv);
    vec2 size = vec2(textureSize(SceneSampler, 0));
    // The nexus control texels are not scenery. Preserve them at their
    // original location, but do not lens copies of them into the world.
    if (all(lessThan(source * size, vec2(4.5))) &&
        all(lessThanEqual(abs(ivec3(round(texelFetch(SceneSampler, ivec2(0), 0).rgb * 255.0)) -
                             ivec3(72, 82, 25)), ivec3(1)))) {
        source = max(source, vec2(4.5) / size);
    }
    return textureLod(SceneSampler, source, 0.0).rgb;
}

bool bhSkyDepth(float depth) {
    return depth <= 0.0000001 || depth >= 0.9999999;
}

vec3 bhScenePosition(vec2 uv) {
    ivec2 size = textureSize(SceneDepthSampler, 0);
    float depth = texelFetch(SceneDepthSampler, ivec2(bhMirrorUV(uv) * vec2(size)), 0).r;
    // Cleared depth is sky, including finite-far and reverse-Z projections.
    // Treating it as a solid far plane creates bogus background intersections.
    if (bhSkyDepth(depth)) return vec3(1e20);
    #ifndef RENDERPEARL_DEPTH_IS_ZERO_TO_ONE
    depth = depth * 2.0 - 1.0;
    #endif
    // Keep the UNFOLDED ray coordinates here. The mirrored depth represents
    // virtual geometry in that tile, not geometry back in the central image.
    vec4 point = holeInverseVP * vec4(uv * 2.0 - 1.0, depth, 1.0);
    return abs(point.w) < 1e-7 ? vec3(1e20) : point.xyz / point.w;
}

float bhViewDepth(vec2 uv) {
    ivec2 size = textureSize(SceneDepthSampler, 0);
    float depth = texelFetch(SceneDepthSampler, ivec2(bhMirrorUV(uv) * vec2(size)), 0).r;
    if (bhSkyDepth(depth)) return 1e20;
    #ifndef RENDERPEARL_DEPTH_IS_ZERO_TO_ONE
    depth = depth * 2.0 - 1.0;
    #endif
    // Clip w is camera depth, independent of camera yaw/pitch. World z is
    // unsuitable for DDA intervals when the player turns the camera.
    return 1.0 / (holeInverseVP[2][3] * depth + holeInverseVP[3][3]);
}

vec3 bhObservedPosition(vec2 uv) {
    // An observation belongs to the centre of its depth texel. Unprojecting
    // a continuous face-probe UV with that texel's depth moves an oblique
    // terrain sample off its actual world-grid plane, rejecting solid cubes.
    vec2 size = vec2(textureSize(SceneDepthSampler, 0));
    return bhScenePosition((floor(uv * size) + 0.5) / size);
}

vec3 bhSampleSurface(vec2 uv) {
    vec2 source = bhMirrorUV(uv);
    ivec2 size = textureSize(SceneDepthSampler, 0);
    ivec2 pixel = ivec2(source * vec2(size));
    float reference = texelFetch(SceneDepthSampler, pixel, 0).r;
    float clipDepth = reference;
    #ifndef RENDERPEARL_DEPTH_IS_ZERO_TO_ONE
    clipDepth = clipDepth * 2.0 - 1.0;
    #endif
    float derivative = abs(holeInverseVP[2][3]);
    #ifndef RENDERPEARL_DEPTH_IS_ZERO_TO_ONE
    derivative *= 2.0;
    #endif
    float tolerance = abs(holeInverseVP[2][3] * clipDepth + holeInverseVP[3][3]) * 0.01 / max(derivative, 1e-12);
    ivec2 base = ivec2(floor(source * vec2(size) - 0.5));
    // Keep ordinary bilinear filtering on continuous surfaces; at a depth
    // edge take the actual hit texel, never the neighbouring sky or glass.
    for (int y = 0; y < 2; y++) {
        for (int x = 0; x < 2; x++) {
            float depth = texelFetch(SceneDepthSampler, clamp(base + ivec2(x,y), ivec2(0), size - 1), 0).r;
            if (bhSkyDepth(depth) || abs(depth - reference) > tolerance)
                return texelFetch(SceneSampler, pixel, 0).rgb;
        }
    }
    return textureLod(SceneSampler, source, 0.0).rgb;
}

bool bhCrossingHit(vec3 start, vec3 end, float pixelAngle, out vec2 hitUV, out float confidence) {
    confidence = 0.0;
    if (!bhProject(end, hitUV)) return false;
    vec3 surface = bhScenePosition(hitUV);
    float endGap = length(end) - length(surface);
    if (endGap < 0.0) return false;
    vec2 startUV;
    if (!bhProject(start, startUV)) return false;
    float startGap = length(start) - length(bhScenePosition(startUV));
    // Being somewhere behind a depth layer is not evidence of having hit it.
    if (startGap > 0.02 + length(start) * pixelAngle) return false;
    vec3 lo = start;
    vec3 hi = end;
    for (int iteration = 0; iteration < 8; iteration++) {
        vec3 middle = (lo + hi) * 0.5;
        vec2 uv;
        if (!bhProject(middle, uv)) return false;
        float gap = length(middle) - length(bhScenePosition(uv));
        if (gap >= 0.0) hi = middle;
        else lo = middle;
    }
    vec3 hit = (lo + hi) * 0.5;
    if (!bhProject(hit, hitUV)) return false;
    surface = bhScenePosition(hitUV);
    float tolerance = max(0.025, length(hit) * pixelAngle * 0.75);
    float residual = length(hit - surface);
    // Neighbouring depths need not be continuous: leaves, fences, glass and
    // voxel silhouettes all have legitimate discontinuities. Validate the
    // hit itself, rather than turning those pixels into transparent cutouts.
    confidence = 1.0 - smoothstep(tolerance, 3.0 * tolerance, residual);
    bhSegmentFraction = clamp(dot(hit - start, end - start) / max(dot(end - start, end - start), 1e-12), 0.0, 1.0);
    // Invalid crossings must not stop the ray. A false hit at a silhouette
    // used to return the unwarped picture, creating one stripe per march step.
    return confidence > 0.001;
}

float bhDepthSlope(float center, float positive, float negative) {
    float a = positive > 1e-19 ? positive - center : 1e20;
    float b = negative > 1e-19 ? center - negative : 1e20;
    float slope = abs(a) < abs(b) ? a : b;
    // Use the neighbour on the same surface. Never span a sky/fence/terrain
    // depth discontinuity with an invented connecting polygon.
    return abs(slope) < center * 0.15 ? slope : 0.0;
}

bool bhBlockFaceValid(vec2 sourceUV, int axis, vec3 lower) {
    if (any(lessThan(sourceUV, vec2(0.0))) || any(greaterThanEqual(sourceUV, vec2(1.0)))) return false;
    vec3 surface = bhObservedPosition(sourceUV);
    if (any(greaterThan(abs(surface), vec3(1e19)))) return false;
    // Vanilla terrain uses world - CameraBlockPos + CameraOffset. The offset
    // is ALREADY the negative camera fraction: undo it here, do not add it.
    vec3 world = surface - CameraOffset;
    vec3 planeDistance = abs(world - round(world));
    // A plane through the camera has zero projected area. A one-pixel strip
    // on x=0 must not masquerade as an entire edge-on cube face.
    if (abs(surface.x) < 0.01) planeDistance.x = 1e20;
    if (abs(surface.y) < 0.01) planeDistance.y = 1e20;
    if (abs(surface.z) < 0.01) planeDistance.z = 1e20;
    float tolerance = max(0.004, length(surface) * 0.000002);
    if (planeDistance[axis] > tolerance) return false;
    // Infer the unit voxel BEHIND an observed axis-aligned full block face.
    // CameraBlockPos is integral, so only CameraOffset is needed for the grid.
    vec3 interior = world;
    interior[axis] += surface[axis] < 0.0 ? -0.01 : 0.01;
    vec3 inferredLower = floor(interior) + CameraOffset;
    // Keep the voxel/face that the caller actually tested. A depth texel at
    // a shared edge can be close to two integer planes; choosing the nearest
    // plane again may infer the adjacent (empty) voxel instead.
    if (any(greaterThan(abs(inferredLower - lower), vec3(0.01)))) return false;
#ifdef LBC_BH_CACHED_GEOMETRY
    return texelFetch(GeometrySampler,ivec2(sourceUV * vec2(textureSize(GeometrySampler,0))),0)[axis] > 0.5;
#else
    // A grid-aligned point alone is not proof of a solid cube (a fence, leaf
    // fragment or thin display may happen to touch that plane). Require four
    // separated covered samples before filling its volume. They must belong
    // to this face or to an already closer occluder, never sky/background.
    int tangentA = (axis + 1) % 3;
    int tangentB = (axis + 2) % 3;
    vec3 center = lower + 0.5;
    center[axis] = round(world[axis]) + CameraOffset[axis];
    for (int corner = 0; corner < 4; corner++) {
        vec3 probe = center;
        probe[tangentA] += (corner & 1) == 0 ? -0.24 : 0.24;
        probe[tangentB] += (corner & 2) == 0 ? -0.24 : 0.24;
        vec2 uv;
        if (!bhProject(probe, uv) || any(lessThan(uv, vec2(0.0))) || any(greaterThanEqual(uv, vec2(1.0)))) return false;
        vec3 observed = bhObservedPosition(uv);
        // A neighbour may hide part of this face. Existing closer geometry
        // still supports a covered voxel; sky or a farther surface does not.
        float probeDepth = (holeVP * vec4(probe, 1.0)).w;
        if (bhViewDepth(uv) < probeDepth - tolerance) continue;
        if (abs(observed[axis] - center[axis]) > tolerance ||
            any(lessThan(observed, lower - tolerance)) || any(greaterThan(observed, lower + 1.0 + tolerance))) return false;
    }
    return true;
#endif
}

bool bhObservedBlockFace(vec3 lower, int axis, out vec2 uv) {
    vec3 center = lower + 0.5;
    vec3 face = center;
    face[axis] += center[axis] < 0.0 ? 0.5 : -0.5;
    if (!bhProject(face, uv) || any(lessThan(uv, vec2(0.0))) || any(greaterThanEqual(uv, vec2(1.0)))) return false;
#ifdef LBC_BH_CACHED_GEOMETRY
    if (texelFetch(GeometrySampler,ivec2(uv * vec2(textureSize(GeometrySampler,0))),0)[axis] < 0.5) return false;
#endif
    vec3 observed = bhObservedPosition(uv);
    float tolerance = max(0.004, length(face) * 0.000002);
    return abs(observed[axis] - face[axis]) <= tolerance &&
           all(lessThanEqual(abs(observed - center), vec3(0.501))) &&
           bhBlockFaceValid(uv, axis, lower);
}

bool bhSegmentHit(vec3 start, vec3 end, float pixelAngle, out vec2 hitUV, out float confidence) {
    confidence = 0.0;
    vec4 ca = holeVP * vec4(start, 1.0);
    vec4 cb = holeVP * vec4(end, 1.0);
    if (ca.w <= 0.00001 || cb.w <= 0.00001) return false;
    vec2 a = (ca.xy / ca.w * 0.5 + 0.5) * ScreenSize;
    vec2 b = (cb.xy / cb.w * 0.5 + 0.5) * ScreenSize;
    vec2 delta = b - a;
    // Traverse pixel CELLS, not uniformly spaced world positions. Perspective
    // makes world-space subdivision skip pixels at oblique viewing angles.
    // Interpolate homogeneous depth via 1 / w (perspective-correct DDA,
    // McGuire & Mara). Every cell has its own finite depth interval; never
    // connect two unrelated silhouettes with a fictitious depth ramp.
    float ka = 1.0 / ca.w;
    float kb = 1.0 / cb.w;
    vec2 stepDirection = sign(delta);
    vec2 cell = floor(a);
    vec2 inverseDelta = 1.0 / max(abs(delta), vec2(1e-12));
    vec2 boundary = cell + vec2(stepDirection.x > 0.0 ? 1.0 : 0.0,
                                stepDirection.y > 0.0 ? 1.0 : 0.0);
    vec2 crossing = abs(boundary - a) * inverseDelta;
    if (abs(delta.x) < 1e-7) crossing.x = 1e30;
    if (abs(delta.y) < 1e-7) crossing.y = 1e30;
    float previous = 0.0;
    for (int cellIndex = 0; cellIndex < 64; cellIndex++) {
        float next = min(1.0, min(crossing.x, crossing.y));
        float middle = (previous + next) * 0.5;
        vec2 uv = (a + delta * middle) / ScreenSize;
        float surface = bhViewDepth(uv);
        if (surface < 1e19) {
            float p = 1.0 / mix(ka, kb, previous);
            float q = 1.0 / mix(ka, kb, next);
            // A pixel represents a small surface patch, not a mathematical
            // point. Include its footprint to close subpixel voxel cracks.
            float thickness = max(0.002, surface * pixelAngle * 0.7);
            float nearZ = min(p, q);
            float farZ = max(p, q);
            bool hit = farZ >= surface - thickness && nearZ <= surface + thickness;
            float cellT = abs(q - p) > 1e-8 ? clamp((surface - p) / (q - p), 0.0, 1.0) : 0.5;
            // A constant-depth texel is a tiny camera-facing step, not the
            // underlying sloped block face. Refine nearby misses against a
            // local perspective plane to seal cracks at grazing angles.
            if (!hit && min(abs(p - surface), abs(q - surface)) < max(0.04, surface * pixelAngle * 8.0)) {
                vec2 centerUV = (cell + 0.5) / ScreenSize;
                float reciprocal = 1.0 / surface;
                vec2 slope = vec2(
                    bhDepthSlope(reciprocal, 1.0 / bhViewDepth(centerUV + vec2(1.0 / ScreenSize.x, 0.0)),
                                            1.0 / bhViewDepth(centerUV - vec2(1.0 / ScreenSize.x, 0.0))),
                    bhDepthSlope(reciprocal, 1.0 / bhViewDepth(centerUV + vec2(0.0, 1.0 / ScreenSize.y)),
                                            1.0 / bhViewDepth(centerUV - vec2(0.0, 1.0 / ScreenSize.y))));
                float ga = mix(ka, kb, previous) - reciprocal - dot(slope, a + delta * previous - cell - 0.5);
                float gb = mix(ka, kb, next) - reciprocal - dot(slope, a + delta * next - cell - 0.5);
                hit = (ga >= 0.0 && gb <= 0.0) || (ga <= 0.0 && gb >= 0.0);
                if (hit) cellT = abs(ga - gb) > 1e-12 ? clamp(ga / (ga - gb), 0.0, 1.0) : 0.5;
            }
            if (hit) {
                vec2 candidate = (a + delta * mix(previous, next, cellT)) / ScreenSize;
                // Keep the sample inside this cell even for a grazing hit.
                // Sampling a neighbour's sky here produces bright edge slits.
                hitUV = clamp(candidate, (cell + 0.001) / ScreenSize,
                                        (cell + 0.999) / ScreenSize);
                float projectedT = mix(previous, next, cellT);
                bhSegmentFraction = projectedT * kb / mix(ka, kb, projectedT);
                confidence = 1.0;
                return true;
            }
        }
        if (next >= 1.0) return false;
        if (crossing.x <= crossing.y) {
            cell.x += stepDirection.x;
            previous = crossing.x;
            crossing.x += inverseDelta.x;
        } else {
            cell.y += stepDirection.y;
            previous = crossing.y;
            crossing.y += inverseDelta.y;
        }
    }
    // Very long free-space segments can exceed the cell budget. Refine their
    // remaining interval rather than dropping its endpoint intersection.
    float remaining = previous * kb / mix(ka, kb, previous);
    bool hit = bhCrossingHit(mix(start, end, remaining), end, pixelAngle, hitUV, confidence);
    bhSegmentFraction = remaining + (1.0 - remaining) * bhSegmentFraction;
    return hit;
}

bool bhKnownBlockSourceHit(vec3 start, vec3 end, out vec2 hitUV) {
    // The midpoint's depth pixel cannot reject a whole 3D segment. A ray
    // may enter an observed block from a hidden side which projects to sky
    // at that midpoint. Traverse the finite world-grid cells instead.
    vec3 origin = start - CameraOffset;
    vec3 direction = end - start;
    vec3 cell = floor(origin);
    // A failed voxel classification depends only on this frame's geometry.
    // A short segment entirely inside that same empty cell needs no DDA,
    // reciprocal directions or repeated face proofs.
    if (bhEmptyVoxelValid && all(equal(ivec3(cell), bhEmptyVoxel)) &&
        all(equal(floor(end - CameraOffset), cell))) return false;
    vec3 inverse = 1.0 / max(abs(direction), vec3(1e-12));
    vec3 boundary = cell + vec3(direction.x >= 0.0 ? 1.0 : 0.0,
                                direction.y >= 0.0 ? 1.0 : 0.0,
                                direction.z >= 0.0 ? 1.0 : 0.0);
    vec3 crossing = abs(boundary - origin) * inverse;
    if (abs(direction.x) < 1e-12) crossing.x = 1e30;
    if (abs(direction.y) < 1e-12) crossing.y = 1e30;
    if (abs(direction.z) < 1e-12) crossing.z = 1e30;
    float voxelEntry = 0.0;
    for (int voxelIndex = 0; voxelIndex < 8; voxelIndex++) {
        // The depth image and voxel grid are fixed for the whole ray. Reuse
        // the last failed classification instead of proving the same empty
        // voxel again on every tiny integration step. Never cache a depth
        // gate or a ray-dependent intersection result as empty geometry.
        bool cachedEmpty = bhEmptyVoxelValid && all(equal(ivec3(cell), bhEmptyVoxel));
        for (int axis = 0; axis < 3 && !cachedEmpty; axis++) {
            vec2 uv;
            if (bhObservedBlockFace(cell + CameraOffset, axis, uv)) {
                // This DDA has already clipped the segment to this voxel.
                bhSegmentFraction = voxelEntry;
                hitUV = uv;
                return true;
            }
        }
        bhEmptyVoxel = ivec3(cell);
        bhEmptyVoxelValid = true;
        int axis = crossing.x < crossing.y ? 0 : 1;
        if (crossing.z < crossing[axis]) axis = 2;
        if (crossing[axis] > 1.0) break;
        voxelEntry = crossing[axis];
        cell[axis] += sign(direction[axis]);
        crossing[axis] += inverse[axis];
    }
    return false;
}

#ifdef LBC_BH_MIRRORED_VOLUMES
vec3 bhFoldWorld(vec3 point, vec2 tile) {
    vec4 clip = holeVP * vec4(point, 1.0);
    vec2 direction = vec2(1.0) - 2.0 * mod(tile, 2.0);
    vec2 offset = mix(-tile, tile + 1.0, mod(tile, 2.0));
    clip.xy = direction * clip.xy + (direction + 2.0 * offset - 1.0) * clip.w;
    vec4 folded = holeInverseVP * clip;
    return folded.xyz / folded.w;
}

bool bhKnownBlockHit(vec3 start, vec3 end, out vec2 hitUV) {
    vec4 ca = holeVP * vec4(start, 1.0);
    vec4 cb = holeVP * vec4(end, 1.0);
    if (ca.w <= 0.00001 || cb.w <= 0.00001) return false;
    vec2 a = ca.xy / ca.w * 0.5 + 0.5;
    vec2 b = cb.xy / cb.w * 0.5 + 0.5;
    vec2 delta = b - a;
    vec2 cell = floor(a);
    vec2 stepDirection = sign(delta);
    vec2 inverseDelta = 1.0 / max(abs(delta), vec2(1e-12));
    vec2 boundary = cell + vec2(stepDirection.x > 0.0 ? 1.0 : 0.0,
                                stepDirection.y > 0.0 ? 1.0 : 0.0);
    vec2 crossing = abs(boundary - a) * inverseDelta;
    if (abs(delta.x) < 1e-7) crossing.x = 1e30;
    if (abs(delta.y) < 1e-7) crossing.y = 1e30;
    float ka = 1.0 / ca.w, kb = 1.0 / cb.w;
    float previous = 0.0;
    int tileCount = min(8, 1 + int(abs(floor(b.x) - cell.x) + abs(floor(b.y) - cell.y)));
    for (int tileIndex = 0; tileIndex < tileCount; tileIndex++) {
        float next = min(1.0, min(crossing.x, crossing.y));
        float lo = previous * kb / mix(ka, kb, previous);
        float hi = next * kb / mix(ka, kb, next);
        vec3 first = mix(start, end, lo), last = mix(start, end, hi);
        if (any(notEqual(cell, vec2(0.0)))) {
            // Mirror the ray into the observed world's grid BEFORE proving
            // cube volumes. A virtual screen tile has a reflected/sheared
            // grid; using the original world grid left its hidden faces open.
            first = bhFoldWorld(first, cell);
            last = bhFoldWorld(last, cell);
        }
        if (bhKnownBlockSourceHit(first, last, hitUV)) {
            bhSegmentFraction = mix(lo, hi, bhSegmentFraction);
            return true;
        }
        if (next >= 1.0) break;
        if (crossing.x <= crossing.y) {
            cell.x += stepDirection.x;
            previous = crossing.x;
            crossing.x += inverseDelta.x;
        } else {
            cell.y += stepDirection.y;
            previous = crossing.y;
            crossing.y += inverseDelta.y;
        }
    }
    return false;
}

#else
bool bhKnownBlockHit(vec3 start, vec3 end, out vec2 hitUV) {
    return bhKnownBlockSourceHit(start,end,hitUV);
}
#endif

bool bhSurfaceHit(vec3 start, vec3 end, float pixelAngle,
                 out vec2 hitUV, out float confidence, out vec3 hitPosition) {
    if (!bhSegmentHit(start, end, pixelAngle, hitUV, confidence)) {
        if (!bhVisibleSurfacesOnly && bhKnownBlockHit(start, end, hitUV)) confidence = 1.0;
        else return false;
    }
    hitPosition = mix(start, end, clamp(bhSegmentFraction, 0.0, 1.0));
    return true;
}

float bhHorizonSegment(vec3 start, vec3 end) {
    vec3 direction = end - start;
    float dd = dot(direction, direction);
    float first = 2.0;
    for (int i = 0; i < LBC_BH_TRACE_COUNT && (holeMask >> uint(i)) != 0u; i++) {
        if ((holeMask & (1u << uint(i))) == 0u) continue;
        vec3 p = start - holeObjects[i].xyz;
        float b = dot(p, direction);
        float c = dot(p, p) - holeObjects[i].w * holeObjects[i].w;
        if (c < 0.0) return 0.0;
        float discriminant = b * b - dd * c;
        if (discriminant < 0.0 || b >= 0.0 || dd < 1e-12) continue;
        float t = (-b - sqrt(discriminant)) / dd;
        if (t >= 0.0 && t <= 1.0) first = min(first, t);
    }
    return first;
}

vec3 bhNormal(int slot) {
    uint bits = holeStyles[slot / 4][slot % 4];
    vec3 normal = vec3(float(bits & 1023u), float((bits >> 10u) & 1023u),
                       float((bits >> 20u) & 1023u)) / 1023.0 * 2.0 - 1.0;
    return normalize(normal);
}

bool bhDisk(int slot) {
    return (holeStyles[slot / 4][slot % 4] & (1u << 30u)) != 0u;
}

float bhErf(float x) {
    // Smooth Gaussian column integral: disk opacity must not jump whenever
    // the midplane happens to cross a ray-march step boundary.
    float a = abs(x);
    float t = 1.0 / (1.0 + 0.3275911 * a);
    float value = 1.0 - (((((1.061405429 * t - 1.453152027) * t) + 1.421413741) * t -
                           0.284496736) * t + 0.254829592) * t * exp(-a * a);
    return x < 0.0 ? -value : value;
}

float bhEntry(vec3 origin, vec3 direction) {
    float nearest = 1e30;
    for (int i = 0; i < LBC_BH_TRACE_COUNT && (holeMask >> uint(i)) != 0u; i++) {
        if ((holeMask & (1u << uint(i))) == 0u) continue;
        vec3 offset = origin - holeObjects[i].xyz;
        float radius = holeObjects[i].w * BH_REACH;
        float middle = -dot(offset, direction);
        vec3 closest = offset + direction * middle;
        float remainder = radius * radius - dot(closest, closest);
        if (remainder < 0.0) continue;
        float halfDistance = sqrt(remainder);
        if (middle + halfDistance <= 0.0) continue;
        nearest = min(nearest, max(middle - halfDistance, 0.0) + holeObjects[i].w * 0.0005);
    }
    return nearest;
}

vec3 bhField(vec3 position, vec3 velocity, out float stepSize, out bool captured,
             out bool nearHorizon) {
    vec3 acceleration = vec3(0.0);
    stepSize = 1e30;
    captured = false;
    nearHorizon = false;
    for (int i = 0; i < LBC_BH_TRACE_COUNT && (holeMask >> uint(i)) != 0u; i++) {
        if ((holeMask & (1u << uint(i))) == 0u) continue;
        float radius = holeObjects[i].w;
        vec3 p = (position - holeObjects[i].xyz) / radius;
        float r2 = dot(p, p);
        float r = sqrt(r2);
        // Exact horizon clipping is only needed near a horizon.
        nearHorizon = nearHorizon || r < 1.5;
        captured = captured || r < 1.0;
        if (r >= BH_REACH || r < 0.5) continue;
        // Spatial null-ray equation in Schwarzschild units (event horizon=1).
        // Central force preserves angular momentum for an isolated hole. For
        // several holes this is a visual weak-field superposition, not an
        // exact dynamical multi-body solution of Einstein's field equations.
        vec3 momentum = cross(p, velocity);
        float angularMomentum2 = dot(momentum, momentum);
        float taper = 1.0 - smoothstep(10.0, BH_REACH, r);
        acceleration -= 1.5 * angularMomentum2 * p * taper /
                        (radius * max(r2 * r2 * r, 0.001));
        stepSize = min(stepSize, radius * r * mix(0.045, 0.16, smoothstep(1.5, 5.0, r)) /
                                max(length(velocity), 0.25));
    }
    return acceleration;
}

void bhAccretion(int slot, vec3 start, vec3 end, vec3 direction,
                 float pixelAngle, inout vec3 emission, inout float transmission) {
    vec4 object = holeObjects[slot];
    vec3 a = (start - object.xyz) / object.w;
    vec3 b = (end - object.xyz) / object.w;
    // Reject most steps before unpacking the disk normal or evaluating noise.
    if (min(dot(a, a), dot(b, b)) > 81.0) return;
    vec3 normal = bhNormal(slot);
    float ha = dot(a, normal);
    float hb = dot(b, normal);
    bool crossing = (ha <= 0.0 && hb > 0.0) || (ha >= 0.0 && hb < 0.0);
    float normalVelocity = abs(dot(normal, direction));
    // Resolve a thin surface at its exact crossing, as in the Noita mod.
    // A narrow volume is needed only for the nearly coplanar, edge-on view.
    if (!crossing && normalVelocity > 0.08) return;
    float t = abs(ha - hb) > 1e-8 ? clamp(ha / (ha - hb), 0.0, 1.0) : 0.5;
    vec3 p = mix(a, b, t);
    float height = dot(p, normal);
    vec3 radial = p - normal * height;
    float r = length(radial);
    if (r < 2.8 || r > 8.2) return;
    float edge = smoothstep(2.8, 3.15, r) * (1.0 - smoothstep(6.8, 8.2, r));
    float thickness = r * 0.013;
    if (!crossing && min(abs(ha), abs(hb)) > thickness * 4.0) return;
    float deltaHeight = hb - ha;
    float path;
    if (crossing && normalVelocity > 0.08) {
        path = 1.0 / normalVelocity;
    } else if (abs(deltaHeight) > thickness * 0.001) {
        path = 0.5 * (bhErf(hb / (1.41421356 * thickness)) -
                      bhErf(ha / (1.41421356 * thickness))) * length(b - a) / deltaHeight;
    } else {
        float midpoint = (ha + hb) * 0.5 / thickness;
        path = exp(-0.5 * midpoint * midpoint) * length(b - a) / (2.50662827 * thickness);
    }
    path = max(path, 0.0);
    // The nearly coplanar view used to evaluate all noise octaves even for
    // zero-density steps many scale heights away from the emitting layer.
    if (edge * path < 0.00001) return;
    vec3 tangent = normalize(cross(normal, radial));
    vec3 reference = normalize(cross(abs(normal.y) < 0.9 ? vec3(0, 1, 0) : vec3(1, 0, 0), normal));
    float angle = atan(dot(radial, cross(normal, reference)), dot(radial, reference));
    float seconds = GameTime * 1200.0;
    // Project the pixel cone onto the disk plane: radial stretching is 1/cos,
    // not 1/sqrt(cos). At grazing incidence unresolved radial filaments must
    // converge to their average instead of becoming concentric dotted bands.
    float incidence = max(abs(dot(normal, direction)), 0.025);
    float footprint = pixelAngle * length(start) / object.w / incidence;
    float density = bhDiskDensity(r, angle, seconds, footprint);
    float opticalDepth = edge * path * density * 0.9;
    float opacity = 1.0 - exp(-opticalDepth);
    float temperature = pow(3.0 / max(r, 3.0), 0.8);
    float approach = -dot(tangent, direction) / sqrt(r);
    float heat = clamp(pow(3.0 / r, 0.65) + approach * 0.12, 0.0, 1.0);
    vec3 color = mix(vec3(1.0, 0.12, 0.008), vec3(1.0, 0.97, 0.88), heat * heat);
    float doppler = pow(clamp(1.0 + approach * 0.65, 0.6, 1.5), 3.0);
    float redshift = sqrt(max(1.0 - 1.0 / r, 0.0));
    emission += transmission * color * opacity * (4.0 * temperature * doppler * redshift);
    transmission *= 1.0 - opacity;
    // Low-energy scattering around the bright surface, without the former
    // thick orange fog bar across the horizon.
    float haloThickness = r * 0.04;
    float corona = exp2(-height * height / (haloThickness * haloThickness));
    emission += transmission * vec3(1.0, 0.42, 0.12) * corona * edge * length(b - a) * 0.0015;
}

bool bhSkyPixel(ivec2 pixel) {
    if (!bhSkyDepth(texelFetch(SceneDepthSampler, pixel, 0).r)) return false;
    if (all(lessThan(pixel, ivec2(4))) &&
        all(lessThanEqual(abs(ivec3(round(texelFetch(SceneSampler, pixel, 0).rgb * 255.0)) -
                             ivec3(72, 82, 25)), ivec3(1)))) return false;
    return true;
}

vec3 bhSkyBackground(vec2 uv) {
    vec2 folded = bhMirrorUV(uv);
    ivec2 size = textureSize(SceneDepthSampler, 0);
    vec2 p = folded * vec2(size) - 0.5;
    ivec2 base = ivec2(floor(p));
    vec2 f = fract(p);
    vec3 color = vec3(0.0);
    float weight = 0.0;
    // Filter only cleared-depth texels. A bilinear color sample on a sky
    // pixel can otherwise leak the neighbouring wall back into the lens.
    for (int y = 0; y < 2; y++) {
        for (int x = 0; x < 2; x++) {
            ivec2 pixel = clamp(base + ivec2(x, y), ivec2(0), size - 1);
            if (!bhSkyPixel(pixel)) continue;
            float w = (x == 0 ? 1.0 - f.x : f.x) * (y == 0 ? 1.0 - f.y : f.y);
            color += texelFetch(SceneSampler, pixel, 0).rgb * w;
            weight += w;
        }
    }
    if (weight > 0.0001) return color / weight;
    // The actual finite geometry was already tested along the ray. Using
    // its color AGAIN as an image at infinity creates a second projection
    // of the same island. Fill the disoccluded environment from visible sky.
    const vec2 offsets[8] = vec2[8](
        vec2(1, 0), vec2(-1, 0), vec2(0, 1), vec2(0, -1),
        vec2(0.70710678, 0.70710678), vec2(-0.70710678, 0.70710678),
        vec2(0.70710678, -0.70710678), vec2(-0.70710678, -0.70710678));
    float radius = 2.0;
    for (int ring = 0; ring < 11; ring++) {
        color = vec3(0.0);
        weight = 0.0;
        for (int i = 0; i < 8; i++) {
            ivec2 pixel = ivec2(bhMirrorUV(folded + offsets[i] * radius / vec2(size)) * vec2(size));
            if (!bhSkyPixel(pixel)) continue;
            color += texelFetch(SceneSampler, pixel, 0).rgb;
            weight += 1.0;
        }
        if (weight > 0.0) return color / weight;
        if (radius > float(max(size.x, size.y))) break;
        radius *= 2.0;
    }
    // No visible sky exists (e.g. an enclosed room). Only an unresolved
    // ambient color can be estimated; never reproduce wall silhouettes.
    color = vec3(0.0);
    for (int y = 0; y < 4; y++) {
        for (int x = 0; x < 4; x++) {
            color += textureLod(SceneSampler, (vec2(x, y) + 0.5) * 0.25, 0.0).rgb;
        }
    }
    return color * 0.0625;
}

vec3 bhEmissionColor(vec3 emission) {
    // Compress radiance with ONE shared exposure factor. Per-channel
    // exponential clipping bleached orange filaments to a uniform white
    // plastic surface and erased their density/temperature variation.
    float peak = max(emission.r, max(emission.g, emission.b));
    return emission / (1.0 + peak);
}

vec3 bhBackground(vec3 origin, vec3 direction, float pixelAngle) {
    vec4 infinity = holeVP * vec4(direction, 0.0);
    float safeW = (infinity.w < 0.0 ? -1.0 : 1.0) * max(abs(infinity.w), 0.002);
    vec2 continuationUV = infinity.xy / safeW * 0.5 + 0.5;
    // Continue the same ray through flat space. An opaque surface ends the
    // ray here too, including gaps between disjoint gravitational volumes.
    vec3 position = origin;
    float stride = max(0.05, length(origin) * pixelAngle * 2.0);
    for (int step = 0; step < 32; step++) {
        vec3 nextPosition = position + direction * stride;
        vec2 uv;
        float confidence;
        vec3 hitPosition;
        if (bhSurfaceHit(position, nextPosition, pixelAngle, uv, confidence, hitPosition)) {
            bhTraceKind = 1.0;
            bhTraceWarp = true;
            bhTraceUV = bhMirrorUV(uv);
            return bhSampleSurface(uv);
        }
        position = nextPosition;
        stride *= 1.4;
    }
    return bhSkyBackground(continuationUV);
}

vec3 bhTrace(vec2 uv, float pixelAngle) {
    bhTraceWarp = false;
    bhEmptyVoxelValid = false;
    bhVisibleSurfacesOnly = false;
    bhTraceKind = 0.0;
    vec3 original = textureLod(SceneSampler, uv, 0.0).rgb;
    vec3 direction = bhDirection(uv);
    // Reconstruct visible and mirrored block volumes at every distance.
    float entry = bhEntry(vec3(0.0), direction);
    if (entry > 1e25) return original;
    // Stop BEFORE entering the field if the camera already sees a nearer
    // surface. Never change the gravitational field based on this depth.
    if (length(bhScenePosition(uv)) < entry) return original;
    bhTraceKind = 0.5;
    vec3 position = direction * entry;
    vec3 velocity = direction;
    vec3 emission = vec3(0.0);
    float transmission = 1.0;
    bool changed = false;
    bool escaped = false;
    for (int step = 0; step < BH_STEPS; step++) {
        float dt;
        bool captured;
        bool nearHorizon;
        vec3 acceleration = bhField(position, velocity, dt, captured, nearHorizon);
        if (captured) {
            bhTraceKind = 0.75;
            return bhEmissionColor(emission);
        }
        if (dt > 1e25) {
            float nextEntry = bhEntry(position, normalize(velocity));
            if (nextEntry > 1e25) {
                escaped = true;
                break;
            }
            vec3 nextPosition = position + normalize(velocity) * nextEntry;
            vec2 sceneUV;
            float confidence;
            vec3 hitPosition;
            if (bhSurfaceHit(position, nextPosition, pixelAngle, sceneUV, confidence, hitPosition)) {
                bhTraceKind = 1.0;
                bhTraceWarp = max(emission.r,max(emission.g,emission.b)) < 0.001 && transmission > 0.999;
                bhTraceUV = bhMirrorUV(sceneUV);
                return bhEmissionColor(emission) + transmission * bhSampleSurface(sceneUV);
            }
            position = nextPosition;
            continue;
        }
        vec3 halfVelocity = velocity + acceleration * (0.5 * dt);
        vec3 nextPosition = position + halfVelocity * dt;
        float horizon = nearHorizon ? bhHorizonSegment(position, nextPosition) : 2.0;
        if (horizon <= 1.0) nextPosition = mix(position, nextPosition, horizon);
        vec2 sceneUV;
        float confidence;
        vec3 hitPosition;
        bool surfaceHit = bhSurfaceHit(position, nextPosition, pixelAngle, sceneUV, confidence, hitPosition);
        if (surfaceHit) {
            // Integrate emission only in front of the opaque hit. The ray
            // must not continue behind a wall merely to obtain a background.
            nextPosition = hitPosition;
        }
        for (int i = 0; i < LBC_BH_TRACE_COUNT && (holeMask >> uint(i)) != 0u; i++) {
            if ((holeMask & (1u << uint(i))) != 0u && bhDisk(i)) {
                bhAccretion(i, position, nextPosition, normalize(halfVelocity), pixelAngle, emission, transmission);
            }
        }
        if (surfaceHit) {
            bhTraceKind = 1.0;
            bhTraceWarp = max(emission.r,max(emission.g,emission.b)) < 0.001 && transmission > 0.999;
            bhTraceUV = bhMirrorUV(sceneUV);
            return bhEmissionColor(emission) + transmission * bhSampleSurface(sceneUV);
        }
        if (horizon <= 1.0) {
            bhTraceKind = 0.75;
            return bhEmissionColor(emission);
        }
        float ignoredStep;
        bool ignoredCapture;
        bool ignoredHorizon;
        vec3 nextAcceleration = bhField(nextPosition, halfVelocity, ignoredStep, ignoredCapture, ignoredHorizon);
        velocity = halfVelocity + nextAcceleration * (0.5 * dt);
        position = nextPosition;
        changed = true;
        if (transmission < 0.002) break;
    }
    if (!changed) {
        bhTraceKind = 0.0;
        return original;
    }
    // An unresolved photon orbit has not supplied an escaping background ray.
    // Sampling its last arbitrary direction produces noisy copies around the
    // critical ring, especially when the camera is close to a large horizon.
    if (!escaped) {
        float nearest = 1e30;
        for (int i = 0; i < LBC_BH_TRACE_COUNT && (holeMask >> uint(i)) != 0u; i++) {
            if ((holeMask & (1u << uint(i))) == 0u) continue;
            nearest = min(nearest, length(position - holeObjects[i].xyz) / holeObjects[i].w);
        }
        if (nearest < 2.0 || transmission < 0.002) {
            bhTraceKind = 0.75;
            return bhEmissionColor(emission);
        }
    }
    vec3 background = bhBackground(position, normalize(velocity), pixelAngle);
    bhTraceWarp = bhTraceWarp && max(emission.r,max(emission.g,emission.b)) < 0.001 && transmission > 0.999;
    return bhEmissionColor(emission) + transmission * background;
}

#ifndef LBC_BH_GEOMETRY_BUILD
void main() {
    float stride = ResolutionScale > 1.0 ? lbc_bh_stride(holePeripheral) : 1.0;
    vec2 traceSize = vec2(textureSize(SceneSampler, 0)) / stride;
    if (any(greaterThanEqual(gl_FragCoord.xy, ceil(traceSize)))) discard;
    vec2 halfPixel = 0.5 / vec2(textureSize(SceneSampler,0));
    vec2 uv = clamp(gl_FragCoord.xy / traceSize,halfPixel,vec2(1.0)-halfPixel);
    vec4 scene = textureLod(SceneSampler, uv, 0.0);
    // Alpha is coverage of this post effect, not scene material opacity.
    // Unchanged pixels are restored exactly by the full-resolution resolve.
    fragColor = vec4(scene.rgb, 0.0);
    if (holeMask == 0u) return;
    ivec2 pixel = ivec2(uv * ScreenSize);
    if (all(lessThan(pixel, ivec2(4))) &&
        all(lessThanEqual(abs(ivec3(round(scene.rgb * 255.0)) - ivec3(72, 82, 25)), ivec3(1)))) return;
    if (ResolutionScale > 1.0 && holePeripheral.w <= 0.0) discard;
    // Near views reconstruct source coordinates from the separate lens map.
    // Do not launch a sparse set of expensive full-size rays at every edge:
    // scattered surviving lanes kept nearly every GPU warp running.
#ifndef LBC_BH_FULL_RESOLUTION
    if (ResolutionScale <= 1.0 && holePeripheral.w > 0.0) {
        fragColor = vec4(0.0,0.0,0.0,0.125);
        return;
    }
#endif
    vec3 direction = bhDirection(uv);
    float entry = bhEntry(vec3(0.0), direction);
    if (entry > 1e25 || length(bhScenePosition(uv)) < entry) return;
    float pixelAngle = max(length(bhDirection(uv + vec2(1.0 / traceSize.x, 0.0)) - direction),
                           length(bhDirection(uv + vec2(0.0, 1.0 / traceSize.y)) - direction));
    // Supersample only the narrow critical-impact band. Large untouched areas
    // still cost one trace (usually just a bounding-sphere rejection).
    bool edge = false;
    for (int i = 0; i < LBC_BH_TRACE_COUNT && (holeMask >> uint(i)) != 0u; i++) {
        if ((holeMask & (1u << uint(i))) == 0u || dot(holeObjects[i].xyz, direction) <= 0.0) continue;
        float impact = length(cross(holeObjects[i].xyz, direction));
        float footprint = pixelAngle * length(holeObjects[i].xyz);
        edge = edge || abs(impact - holeObjects[i].w * 2.58) < footprint;
    }
    vec3 sum = vec3(0.0);
    float kindSum = 0.0;
    int samples = edge ? 2 : 1;
    // One call site avoids duplicating the integrator and spilling registers
    // when many different slots are active in neighbouring GPU lanes.
    for (int sampleIndex = 0; sampleIndex < samples; sampleIndex++) {
        vec2 offset = edge ? vec2(sampleIndex == 0 ? -0.25 : 0.25) / traceSize : vec2(0.0);
        sum += bhTrace(uv + offset, pixelAngle);
        kindSum += bhTraceKind;
    }
    fragColor.rgb = sum / float(samples);
    fragColor.a = kindSum / float(samples);
#ifndef LBC_BH_FULL_RESOLUTION
    if (ResolutionScale > 1.0 && samples == 1 && bhTraceWarp && fragColor.a > 0.95) {
        uvec2 uvBits = uvec2(round(clamp(bhTraceUV,vec2(0.0),vec2(1.0)) * 16383.0));
        // Quantization must retain the hit's depth texel, especially next to
        // sky. Rounding across that texel edge would create new bright slits.
        vec2 size = vec2(textureSize(SceneSampler,0));
        ivec2 wanted = ivec2(bhTraceUV * size);
        ivec2 actual = ivec2(vec2(uvBits) / 16383.0 * size);
        for (int axis=0;axis<2;axis++) {
            if (actual[axis] < wanted[axis]) uvBits[axis]++;
            if (actual[axis] > wanted[axis]) uvBits[axis]--;
        }
        uint bits = uvBits.x | (uvBits.y << 14u);
        fragColor = vec4(uvec4(bits & 255u,(bits >> 8u) & 255u,(bits >> 16u) & 255u,240u | (bits >> 24u))) / 255.0;
    } else if (ResolutionScale > 1.0 && fragColor.a > 0.95) fragColor.a = 0.875;
#endif
}

#endif
