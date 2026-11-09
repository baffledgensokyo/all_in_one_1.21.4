// TMT: sample the bound atlas on a 16px grid, without overlapping shape layers.
// These are atlas cells, not sprite bounds (core shaders have no sprite table).
#ifndef LBC_TMT_ATLAS_GLSL
#define LBC_TMT_ATLAS_GLSL
bool lbc_tmt_carrier(vec4 sampleColor, uint tintPrefix) {
    return tintPrefix == 250u && all(equal(ivec4(round(sampleColor * 255.0)), ivec4(31, 197, 83, 255)));
}
uint lbc_tmt_hash(uint x) {
    x ^= x >> 16u; x *= 0x7feb352du;
    x ^= x >> 15u; x *= 0x846ca68bu;
    return x ^ (x >> 16u);
}
float lbc_tmt_random(inout uint state) {
    state = lbc_tmt_hash(state + 0x9e3779b9u);
    return float(state & 0x00ffffffu) / 16777216.0;
}
// Explicit sequencing avoids implementation-dependent function-argument order.
vec2 lbc_tmt_random2(inout uint state) {
    float x = lbc_tmt_random(state);
    float y = lbc_tmt_random(state);
    return vec2(x, y);
}
vec3 lbc_tmt_random3(inout uint state) {
    float x = lbc_tmt_random(state);
    float y = lbc_tmt_random(state);
    float z = lbc_tmt_random(state);
    return vec3(x, y, z);
}
// Preserve the observed legacy PNG size weights, with one stable choice per seed.
int lbc_tmt_resolution(uint seed) {
    uint ticket = lbc_tmt_hash(seed ^ 0x93a761bdu) % 12758u;
    if (ticket < 7248u) return 16;
    if (ticket < 9508u) return 32;
    if (ticket < 11379u) return 64;
    if (ticket < 12159u) return 128;
    return 256;
}
const uint LBC_TMT_EMPTY = 0xffffffffu;

// Run only in the vertex stage. One transparent pixel must never reroll a cell.
bool lbc_tmt_cell_visible(sampler2D atlas, ivec2 origin) {
    ivec2 extent = min(ivec2(16), textureSize(atlas, 0) - origin);
    for (int y = 0; y < extent.y; ++y) {
        for (int x = 0; x < extent.x; ++x) {
            if (texelFetch(atlas, origin + ivec2(x, y), 0).a > 0.0) return true;
        }
    }
    return false;
}

uvec4 lbc_tmt_sources(sampler2D atlas, uint seed) {
    ivec2 grid = max(textureSize(atlas, 0) / 16, ivec2(1));
    uvec4 sources = uvec4(LBC_TMT_EMPTY);
    uint state = lbc_tmt_hash(seed ^ 0x5bf03635u);
    for (int slot = 0; slot < 4; ++slot) {
        // Bounded retries avoid scanning an entire empty/mostly unused atlas.
        // If retries run out, reuse an already verified cell, or stay transparent.
        if (slot > 0) sources[slot] = sources[slot - 1];
        for (int attempt = 0; attempt < 16; ++attempt) {
            ivec2 origin = ivec2(lbc_tmt_random2(state) * vec2(grid)) * 16;
            if (!lbc_tmt_cell_visible(atlas, origin)) continue;
            sources[slot] = uint(origin.x) | (uint(origin.y) << 16u);
            break;
        }
    }
    // A later slot may have found art after the first exhausted its retries.
    for (int slot = 2; slot >= 0; --slot) {
        if (sources[slot] == LBC_TMT_EMPTY) sources[slot] = sources[slot + 1];
    }
    return sources;
}

vec4 lbc_tmt_collage(sampler2D atlas, vec2 quad, uint seed, uvec4 sources) {
    float resolution = float(lbc_tmt_resolution(seed));
    vec2 cell = clamp(floor(quad * resolution), vec2(0.0), vec2(resolution - 1.0));
    ivec2 pixel = ivec2(cell);
    uint layoutTicket = lbc_tmt_hash(seed ^ 0x3c6ef372u);
    // Half of the layout tickets shift the whole tiling. Wrapping keeps coverage
    // square; source cells and cut/swap pieces remain grid-aligned.
    if ((layoutTicket & 1u) != 0u) {
        ivec2 offset = ivec2(1u + ((layoutTicket >> 1u) % 15u), 1u + ((layoutTicket >> 5u) % 15u));
        pixel = (pixel + offset) % int(resolution);
    }
    ivec2 tile = pixel / 16;
    int tileIndex = tile.x + tile.y * (int(resolution) / 16);
    uint state = lbc_tmt_hash(seed ^ (uint(tileIndex + 1) * 0x9e3779b9u));
    int slot = int(state & 3u);
    ivec2 local = pixel % 16;
    int rotation = int(lbc_tmt_random(state) * 4.0);
    bool flip = lbc_tmt_random(state) < 0.5;
    bool cut = lbc_tmt_random(state) < 0.5;
    bool swap = lbc_tmt_random(state) < 0.5;
    uint permutation = lbc_tmt_hash(state ^ 0xa511e9b3u);
    vec3 tint = 0.55 + 0.9 * lbc_tmt_random3(state);
    if (flip) local.x = 15 - local.x;
    if (rotation == 1) local = ivec2(local.y, 15 - local.x);
    if (rotation == 2) local = ivec2(15) - local;
    if (rotation == 3) local = ivec2(15 - local.y, local.x);
    if (cut) {
        int part = local.x / 8 + (local.y / 8) * 2;
        // An odd multiplier gives a bijection of the four 8x8 quadrants.
        int sourcePart = (part * (int(permutation & 1u) * 2 + 1) +
                          1 + int((permutation >> 1u) % 3u)) % 4;
        local = local % 8 + ivec2(sourcePart % 2, sourcePart / 2) * 8;
        if (swap) slot = (slot + part) % 4;
    }
    uint sourceAddress = sources[slot];
    if (sourceAddress == LBC_TMT_EMPTY) return vec4(0.0);
    ivec2 origin = ivec2(sourceAddress & 0xffffu, sourceAddress >> 16u);
    ivec2 extent = min(ivec2(16), textureSize(atlas, 0) - origin);
    local = min(local, extent - 1);
    vec4 source = texelFetch(atlas, origin + local, 0);
    // Keep holes and fractional alpha, including the pack's effect-marker values.
    // Callers bypass alpha-marker dispatch for TMT rather than altering alpha.
    return vec4(clamp(source.rgb * tint, 0.0, 1.0), source.a);
}
#endif
