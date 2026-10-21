#include <lbc:black_hole_sampling.glsl>

uniform sampler2D SceneSampler;
uniform sampler2D TraceSampler;
uniform sampler2D CoarseSampler;
uniform sampler2D SceneDepthSampler;
layout(std140) uniform BlackHoleConfig {
    float ResolutionScale;
};
layout(location = 0) in vec2 texCoord;
layout(location = 1) flat in mat4 holeInverseVP;
layout(location = 30) flat in vec4 holePeripheral;
layout(location = 0) out vec4 fragColor;

const bool BH_FILL_GAPS = true;

vec4 bhResolvedTrace(ivec2 pixel) {
    vec4 traced = texelFetch(TraceSampler, pixel, 0);
    if (traced.a > 0.12 && traced.a < 0.13)
        return lbc_bh_coarse_color(SceneSampler,SceneDepthSampler,holeInverseVP,
            texelFetch(CoarseSampler,ivec2(vec2(pixel) / lbc_bh_stride(holePeripheral)),0));
    return traced;
}

vec3 bhClosePixelCrack(ivec2 pixel, ivec2 size, vec4 traced) {
    if (!BH_FILL_GAPS || traced.a < 0.45 || traced.a > 0.55) return traced.rgb;
    // Close only one/two-pixel cracks INSIDE reconstructed surfaces. Six
    // of the eight surrounding samples must be actual geometry, excluding
    // untouched scene pixels, captured rays and the opaque accretion disk.
    // No original-frame depth/colour is pasted over the lensed geometry.
    const ivec2 offsets[8] = ivec2[8](
        ivec2(-1,0),ivec2(1,0),ivec2(0,-1),ivec2(0,1),
        ivec2(-1,-1),ivec2(1,1),ivec2(-1,1),ivec2(1,-1));
    bool nearSurface = false;
    for (int radius = 1; radius <= 2; radius++) {
        int supported = 0;
        int missing = 0;
        bool blocked = false;
        vec3 low = vec3(1.0), high = vec3(0.0), nearest = traced.rgb;
        for (int i = 0; i < 8; i++) {
            ivec2 neighbour = pixel + offsets[i] * radius;
            if (any(lessThan(neighbour,ivec2(0))) || any(greaterThanEqual(neighbour,size))) continue;
            vec4 sampleColor = bhResolvedTrace(neighbour);
            if (sampleColor.a <= 0.95) {
                missing |= 1 << i;
                blocked = blocked || sampleColor.a < 0.45 || sampleColor.a > 0.55;
                continue;
            }
            if (supported == 0) nearest = sampleColor.rgb;
            low = min(low,sampleColor.rgb);
            high = max(high,sampleColor.rgb);
            supported++;
        }
        nearSurface = nearSurface || supported > 0;
        // A line crack has two opposite missing neighbours, whereas a
        // silhouette corner has adjacent sky neighbours. Preserve corners
        // and boundaries against the horizon/untouched view.
        bool enclosed = supported == 8 || (supported == 6 &&
            (missing == 3 || missing == 12 || missing == 48 || missing == 192));
        if (!blocked && enclosed && max(high.r-low.r,max(high.g-low.g,high.b-low.b)) < 0.5) return nearest;
        if (!nearSurface) break;
    }
    return traced.rgb;
}

float sceneDistance(vec2 uv) {
    ivec2 size = textureSize(SceneDepthSampler, 0);
    float depth = texelFetch(SceneDepthSampler, clamp(ivec2(uv * vec2(size)), ivec2(0), size - 1), 0).r;
    if (depth <= 0.0000001 || depth >= 0.9999999) return 1e20;
    #ifndef RENDERPEARL_DEPTH_IS_ZERO_TO_ONE
    depth = depth * 2.0 - 1.0;
    #endif
    return 1.0 / (holeInverseVP[2][3] * depth + holeInverseVP[3][3]);
}

vec3 bhContinueNeighbour(ivec2 pixel, ivec2 size, vec4 traced) {
    // Fill only escaped rays. The horizon and opaque emitting layer have a
    // different tag and must never acquire wall fragments from neighbours.
    if (!BH_FILL_GAPS || traced.a < 0.45 || traced.a > 0.55) return traced.rgb;
    vec2 uv = (vec2(pixel) + 0.5) / vec2(size);
    float reference = sceneDistance(uv);
    // Broad sky/windows stay open. Subpixel cracks can appear where the
    // original view contained sky but the lens now shows a solid surface.
    if (reference > 1e19) return bhClosePixelCrack(pixel,size,traced);
    float depth = texelFetch(SceneDepthSampler, pixel, 0).r;
    #ifndef RENDERPEARL_DEPTH_IS_ZERO_TO_ONE
    depth = depth * 2.0 - 1.0;
    #endif
    vec4 a = holeInverseVP * vec4(uv * 2.0 - 1.0, depth, 1.0);
    vec4 b = holeInverseVP * vec4((uv + vec2(1.0 / float(size.x), 0.0)) * 2.0 - 1.0, depth, 1.0);
    float pixelWorldSize = length(a.xyz / a.w - b.xyz / b.w);
    // At most 0.65 block / 16 pixels across. This is local texture extension,
    // not a blur of the frame or an attempt to close large missing regions.
    int limit = int(clamp(floor(0.65 / max(pixelWorldSize, 1e-5)), 1.0, 16.0));
    for (int axis = 0; axis < 2; axis++) {
        ivec2 direction = axis == 0 ? ivec2(1, 0) : ivec2(0, 1);
        ivec2 distances = ivec2(0);
        vec3 left = vec3(0.0);
        vec3 right = vec3(0.0);
        bvec2 stopped = bvec2(false);
        for (int distance = 1; distance <= limit; distance++) {
            for (int side = 0; side < 2; side++) {
                if (stopped[side]) continue;
                ivec2 neighbour = pixel + direction * (side == 0 ? -distance : distance);
                if (any(lessThan(neighbour, ivec2(0))) || any(greaterThanEqual(neighbour, size))) {
                    stopped[side] = true;
                    continue;
                }
                vec4 sampleColor = bhResolvedTrace(neighbour);
                if (sampleColor.a > 0.95) {
                    float neighbourDepth = sceneDistance((vec2(neighbour) + 0.5) / vec2(size));
                    if (abs(neighbourDepth - reference) <= 1.5 + reference * 0.02) {
                        distances[side] = distance;
                        if (side == 0) left = sampleColor.rgb;
                        else right = sampleColor.rgb;
                    }
                    stopped[side] = true;
                } else if (sampleColor.a < 0.1 || sampleColor.a > 0.6) {
                    stopped[side] = true;
                }
            }
            if (all(stopped)) break;
        }
        if (all(greaterThan(distances, ivec2(0))) && distances.x + distances.y <= limit) {
            // Nearest already-lensed face retains its detail and the disk's
            // emission. Blending in the original frame would reintroduce
            // the duplicate unwarped map and wash out the filled texture.
            return distances.x <= distances.y ? left : right;
        }
    }
    return bhClosePixelCrack(pixel,size,traced);
}

void main() {
    vec4 original = texture(SceneSampler, texCoord);
    fragColor = original;
    ivec2 sceneSize = textureSize(SceneSampler, 0);
#ifdef LBC_BH_PACKED_ALPHA
    if (lbc_bh_carrier_pixel(ivec2(gl_FragCoord.xy), sceneSize)) fragColor.a = 1.0;
#endif
    if (ResolutionScale <= 1.0) {
        ivec2 pixel = clamp(ivec2(gl_FragCoord.xy), ivec2(0), sceneSize - 1);
        if (all(lessThan(pixel, ivec2(4))) &&
            all(lessThanEqual(abs(ivec3(round(original.rgb * 255.0)) - ivec3(72,82,25)), ivec3(1)))) return;
        vec4 coarse;
        float peripheral = lbc_bh_reconstruct(SceneSampler,SceneDepthSampler,CoarseSampler,
            gl_FragCoord.xy,vec2(sceneSize),holeInverseVP,holePeripheral,coarse);
        if (peripheral >= 1.0) {
            // Every RGB here is an actual traced result, including captured
            // rays. Original scene depth cannot paste unwarped objects back.
            fragColor.rgb = coarse.rgb;
            return;
        }
#ifdef LBC_BH_FAR_MAP_RESOLVE
        // Reconstruct the far 2x2 lens map in source coordinates as well.
        lbc_bh_reconstruct_grid(SceneSampler,SceneDepthSampler,TraceSampler,
            gl_FragCoord.xy,vec2(sceneSize),holeInverseVP,lbc_bh_far_stride(),coarse);
        fragColor.rgb = coarse.rgb;
#else
        vec4 traced = texelFetch(TraceSampler, pixel, 0);
        if (traced.a > 0.1) fragColor.rgb = bhContinueNeighbour(pixel, sceneSize, traced);
        if (peripheral > 0.0) fragColor.rgb = mix(fragColor.rgb, coarse.rgb, peripheral);
#endif
        return;
    }
    // The nexus control pixels belong to a different effect.
    if (all(lessThan(ivec2(texCoord * vec2(sceneSize)), ivec2(4))) &&
        all(lessThanEqual(abs(ivec3(round(original.rgb * 255.0)) - ivec3(72, 82, 25)), ivec3(1)))) return;
    ivec2 size = ivec2(ceil(vec2(sceneSize) / max(ResolutionScale, 1.0)));
    vec2 p = texCoord * vec2(size) - 0.5;
    ivec2 base = ivec2(floor(p));
    vec2 f = fract(p);
    float reference = sceneDistance(texCoord);
    vec3 color = vec3(0.0);
    float coverage = 0.0;
    float weight = 0.0;
    for (int y = 0; y < 2; y++) {
        for (int x = 0; x < 2; x++) {
            ivec2 pixel = clamp(base + ivec2(x, y), ivec2(0), size - 1);
            float distance = sceneDistance((vec2(pixel) + 0.5) / vec2(size));
            // Do not interpolate a black-hole pixel across a foreground edge.
            // Sky is a separate layer, rather than an infinitely thick wall.
            if ((reference > 1e19) != (distance > 1e19)) continue;
            if (reference < 1e19 && abs(distance - reference) > max(0.08, reference * 0.02)) continue;
            float w = (x == 0 ? 1.0 - f.x : f.x) * (y == 0 ? 1.0 - f.y : f.y);
            vec4 sampleColor = texelFetch(TraceSampler, pixel, 0);
            float covered = sampleColor.a > 0.1 ? 1.0 : 0.0;
            color += sampleColor.rgb * covered * w;
            coverage += covered * w;
            weight += w;
        }
    }
    if (coverage < 0.0001 || weight < 0.0001) return;
    fragColor.rgb = mix(original.rgb, color / coverage, clamp(coverage / weight, 0.0, 1.0));
}
