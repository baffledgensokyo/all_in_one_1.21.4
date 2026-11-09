#ifndef LBC_ATLAS_GLITCH_GLSL
#define LBC_ATLAS_GLITCH_GLSL

// Private lightmap ALPHA protocol. RGB remains vanilla lighting.
// Code 0 is disabled. V2 codes select 3600 yaw x 1801 pitch bins (0.1 degrees).
// A stationary camera keeps the same atlas selection across frames.
float lbc_atlas_glitch_code(sampler2D lightmap) {
    if (any(lessThan(textureSize(lightmap, 0), ivec2(5, 1)))) return 0.0;
    ivec3 header = ivec3(round(vec3(
        texelFetch(lightmap, ivec2(0, 0), 0).a,
        texelFetch(lightmap, ivec2(1, 0), 0).a,
        texelFetch(lightmap, ivec2(2, 0), 0).a) * 255.0));
    if (all(equal(header, ivec3(61, 103, 230)))) {
        if (textureSize(lightmap, 0).x < 6) return 0.0;
        uvec3 bytes = uvec3(round(vec3(
            texelFetch(lightmap, ivec2(3, 0), 0).a,
            texelFetch(lightmap, ivec2(4, 0), 0).a,
            texelFetch(lightmap, ivec2(5, 0), 0).a) * 255.0));
        uint seed = bytes.x | (bytes.y << 8u) | (bytes.z << 16u);
        return seed < 6483600u ? float(seed + 1u) : 0.0;
    }
    if (any(notEqual(header, ivec3(61, 103, 229)))) return 0.0;
    ivec2 cell = ivec2(round(vec2(texelFetch(lightmap, ivec2(3, 0), 0).a,
                                 texelFetch(lightmap, ivec2(4, 0), 0).a) * 255.0));
    if (any(greaterThan(cell, ivec2(15)))) return 0.0;
    return float(1 + cell.x + 16 * cell.y);
}

uint lbc_atlas_glitch_hash(uint value) {
    value ^= value >> 16u;
    value *= 0x7feb352du;
    value ^= value >> 15u;
    value *= 0x846ca68bu;
    return value ^ (value >> 16u);
}

int lbc_atlas_glitch_extent(uint seed) {
    return 8 << int(lbc_atlas_glitch_hash(seed ^ 0x93a761bdu) % 5u);
}

#ifdef LBC_ATLAS_GLITCH_FRAGMENT
vec3 lbc_atlas_glitch_rgb(sampler2D atlas, vec2 uv, float code, vec3 fallback) {
    ivec2 size = textureSize(atlas, 0);
    vec2 pixel = clamp(uv * vec2(size), vec2(0.0), vec2(size) - 0.0001);
    ivec2 targetCell = ivec2(floor(pixel / 16.0));
    vec2 local = fract(pixel / 16.0);
    uint cameraSeed = uint(clamp(int(round(code)) - 1, 0, 6483599));
    uint seed = lbc_atlas_glitch_hash(cameraSeed ^ (uint(targetCell.x) * 0x9e3779b9u) ^
                                    (uint(targetCell.y) * 0x85ebca6bu));
    ivec2 extent = min(ivec2(lbc_atlas_glitch_extent(seed)), size);
    ivec2 within = min(ivec2(local * vec2(extent)), extent - 1);
    ivec2 choices = max(size - extent + 1, ivec2(1));
    // Never use hidden RGB from empty atlas space as a visible surface color.
    // Retries are bounded; a fully empty atlas preserves the original color.
    // Native surface alpha is kept by every caller, including OIT depth passes.
    for (int attempt = 0; attempt < 8; ++attempt) {
        uint x = lbc_atlas_glitch_hash(seed + uint(attempt) * 0x27d4eb2du + 1u);
        uint y = lbc_atlas_glitch_hash(x ^ 0xa511e9b3u);
        ivec2 origin = ivec2(uvec2(x, y) % uvec2(choices));
        vec4 source = texelFetch(atlas, origin + within, 0);
        if (source.a > 0.0) return source.rgb;
    }
    return fallback;
}
#endif

#endif
