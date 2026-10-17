#version 330
#extension GL_ARB_separate_shader_objects : require

#include <minecraft:globals.glsl>
#include <lbc:black_hole_data.glsl>

uniform sampler2D SceneSampler;
uniform sampler2D SceneDepthSampler;
layout(location = 0) in vec2 texCoord;
layout(location = 1) flat in mat4 holeInverseVP;
layout(location = 5) flat in mat4 holeVP;
layout(location = 9) flat in vec4 holeObjects[16];
layout(location = 25) flat in uvec4 holeStyles[4];
layout(location = 29) flat in uint holeMask;
layout(location = 0) out vec4 fragColor;

const float BH_REACH = 14.0;
const int BH_STEPS = 192;

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
    return texture(SceneSampler, source).rgb;
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

bool bhSegmentHit(vec3 start, vec3 end, float pixelAngle, out vec2 hitUV, out float confidence) {
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
    // Invalid crossings must not stop the ray. A false hit at a silhouette
    // used to return the unwarped picture, creating one stripe per march step.
    return confidence > 0.001;
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
    for (int i = 0; i < LBC_BH_COUNT; i++) {
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

vec3 bhField(vec3 position, vec3 velocity, out float stepSize, out bool captured) {
    vec3 acceleration = vec3(0.0);
    stepSize = 1e30;
    captured = false;
    for (int i = 0; i < LBC_BH_COUNT; i++) {
        if ((holeMask & (1u << uint(i))) == 0u) continue;
        float radius = holeObjects[i].w;
        vec3 p = (position - holeObjects[i].xyz) / radius;
        float r2 = dot(p, p);
        float r = sqrt(r2);
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
    float t = abs(ha - hb) > 1e-8 ? clamp(ha / (ha - hb), 0.0, 1.0) : 0.5;
    vec3 p = mix(a, b, t);
    float height = dot(p, normal);
    vec3 radial = p - normal * height;
    float r = length(radial);
    if (r < 2.8 || r > 8.2) return;
    float edge = smoothstep(2.8, 3.15, r) * (1.0 - smoothstep(6.8, 8.2, r));
    vec3 tangent = normalize(cross(normal, radial));
    vec3 reference = normalize(cross(abs(normal.y) < 0.9 ? vec3(0, 1, 0) : vec3(1, 0, 0), normal));
    float angle = atan(dot(radial, cross(normal, reference)), dot(radial, reference));
    float seconds = GameTime * 1200.0;
    float phase = 13.0 * r + 4.0 * sin(angle * 3.0 - seconds * 0.9 / sqrt(r));
    float footprint = max(pixelAngle * length(start) / object.w,
                          abs(length(a - normal * ha) - length(b - normal * hb)) * 0.5);
    float bands = 0.78 + 0.22 * cos(phase) * exp2(-footprint * footprint * 20.0);
    float spirals = 0.88 + 0.12 * sin(2.0 * angle + r * 2.0 - seconds * 0.7);
    float thickness = r * 0.045;
    float deltaHeight = hb - ha;
    float path;
    if (abs(deltaHeight) > thickness * 0.001) {
        path = 0.5 * (bhErf(hb / (1.41421356 * thickness)) -
                      bhErf(ha / (1.41421356 * thickness))) * length(b - a) / deltaHeight;
    } else {
        float midpoint = (ha + hb) * 0.5 / thickness;
        path = exp(-0.5 * midpoint * midpoint) * length(b - a) / (2.50662827 * thickness);
    }
    path = max(path, 0.0);
    float opticalDepth = edge * path * bands * spirals * 0.48;
    float opacity = 1.0 - exp(-opticalDepth);
    float temperature = pow(3.0 / max(r, 3.0), 0.8);
    vec3 color = mix(vec3(1.0, 0.15, 0.018), vec3(1.0, 0.82, 0.43), temperature * temperature);
    float doppler = pow(clamp(1.0 - dot(tangent, direction) * 0.55 / sqrt(r), 0.6, 1.5), 3.0);
    float redshift = sqrt(max(1.0 - 1.0 / r, 0.0));
    emission += transmission * color * opacity * (2.2 * temperature * doppler * redshift);
    transmission *= 1.0 - opacity;
    // A wider, very faint corona keeps an exactly edge-on disk readable.
    float corona = exp2(-height * height / (thickness * thickness * 20.0));
    emission += transmission * vec3(1.0, 0.28, 0.035) * corona * edge * length(b - a) * 0.008;
}

vec3 bhBackground(vec3 direction) {
    vec4 infinity = holeVP * vec4(direction, 0.0);
    float safeW = (infinity.w < 0.0 ? -1.0 : 1.0) * max(abs(infinity.w), 0.002);
    vec2 continuationUV = infinity.xy / safeW * 0.5 + 0.5;
    // One projection for the ENTIRE scene, including near terrain. Mixing
    // finite-depth hits with this directional image gives the same object
    // two different projections. Depth is used only to occlude the hole/disk.
    return bhSampleBackground(continuationUV);
}

vec3 bhTrace(vec2 uv, float pixelAngle) {
    vec3 original = texture(SceneSampler, uv).rgb;
    vec3 direction = bhDirection(uv);
    float entry = bhEntry(vec3(0.0), direction);
    if (entry > 1e25) return original;
    bool blocked = length(bhScenePosition(uv)) < entry;
    vec2 foregroundUV = uv;
    vec3 position = direction * entry;
    vec3 velocity = direction;
    vec3 emission = vec3(0.0);
    float transmission = 1.0;
    bool changed = false;
    bool escaped = false;
    for (int step = 0; step < BH_STEPS; step++) {
        float dt;
        bool captured;
        vec3 acceleration = bhField(position, velocity, dt, captured);
        if (captured) return (vec3(1.0) - exp(-emission)) +
                             (blocked ? transmission * bhSampleBackground(foregroundUV) : vec3(0.0));
        if (dt > 1e25) {
            float nextEntry = bhEntry(position, normalize(velocity));
            if (nextEntry > 1e25) {
                escaped = true;
                break;
            }
            position += normalize(velocity) * nextEntry;
            continue;
        }
        vec3 halfVelocity = velocity + acceleration * (0.5 * dt);
        vec3 nextPosition = position + halfVelocity * dt;
        vec2 sceneUV;
        float confidence;
        if (!blocked && bhSegmentHit(position, nextPosition, pixelAngle, sceneUV, confidence)) {
            // Record visibility, but keep integrating the SAME lens mapping
            // used for the rest of the scene. A near surface must not switch
            // this pixel back to its almost unwarped finite-depth projection.
            blocked = true;
            foregroundUV = sceneUV;
        }
        for (int i = 0; i < LBC_BH_COUNT; i++) {
            if (!blocked && (holeMask & (1u << uint(i))) != 0u && bhDisk(i)) {
                bhAccretion(i, position, nextPosition, normalize(halfVelocity), pixelAngle, emission, transmission);
            }
        }
        float ignoredStep;
        bool ignoredCapture;
        vec3 nextAcceleration = bhField(nextPosition, halfVelocity, ignoredStep, ignoredCapture);
        velocity = halfVelocity + nextAcceleration * (0.5 * dt);
        position = nextPosition;
        changed = true;
        if (transmission < 0.002) break;
    }
    if (!changed) return original;
    // An unresolved photon orbit has not supplied an escaping background ray.
    // Sampling its last arbitrary direction produces noisy copies around the
    // critical ring, especially when the camera is close to a large horizon.
    if (!escaped) {
        float nearest = 1e30;
        for (int i = 0; i < LBC_BH_COUNT; i++) {
            if ((holeMask & (1u << uint(i))) == 0u) continue;
            nearest = min(nearest, length(position - holeObjects[i].xyz) / holeObjects[i].w);
        }
        if (nearest < 2.0 || transmission < 0.002) {
            return (vec3(1.0) - exp(-emission)) +
                   (blocked ? transmission * bhSampleBackground(foregroundUV) : vec3(0.0));
        }
    }
    vec3 background = bhBackground(normalize(velocity));
    return (vec3(1.0) - exp(-emission)) + transmission * background;
}

void main() {
    vec4 scene = texture(SceneSampler, texCoord);
    fragColor = scene;
    if (holeMask == 0u) return;
    ivec2 pixel = ivec2(texCoord * ScreenSize);
    if (all(lessThan(pixel, ivec2(4))) &&
        all(lessThanEqual(abs(ivec3(round(scene.rgb * 255.0)) - ivec3(72, 82, 25)), ivec3(1)))) return;
    vec3 direction = bhDirection(texCoord);
    float entry = bhEntry(vec3(0.0), direction);
    if (entry > 1e25) return;
    float pixelAngle = max(length(bhDirection(texCoord + vec2(1.0 / ScreenSize.x, 0.0)) - direction),
                           length(bhDirection(texCoord + vec2(0.0, 1.0 / ScreenSize.y)) - direction));
    // Supersample only the narrow critical-impact band. Large untouched areas
    // still cost one trace (usually just a bounding-sphere rejection).
    bool edge = false;
    for (int i = 0; i < LBC_BH_COUNT; i++) {
        if ((holeMask & (1u << uint(i))) == 0u || dot(holeObjects[i].xyz, direction) <= 0.0) continue;
        float impact = length(cross(holeObjects[i].xyz, direction));
        float footprint = pixelAngle * length(holeObjects[i].xyz);
        edge = edge || abs(impact - holeObjects[i].w * 2.58) < footprint;
    }
    vec3 sum = vec3(0.0);
    int samples = edge ? 2 : 1;
    // One call site avoids duplicating the integrator and spilling registers
    // when many different slots are active in neighbouring GPU lanes.
    for (int sampleIndex = 0; sampleIndex < samples; sampleIndex++) {
        vec2 offset = edge ? vec2(sampleIndex == 0 ? -0.25 : 0.25) / ScreenSize : vec2(0.0);
        sum += bhTrace(texCoord + offset, pixelAngle);
    }
    fragColor.rgb = sum / float(samples);
}
