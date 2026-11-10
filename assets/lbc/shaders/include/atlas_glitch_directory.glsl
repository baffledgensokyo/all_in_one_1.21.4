#ifndef LBC_ATLAS_GLITCH_DIRECTORY_GLSL
#define LBC_ATLAS_GLITCH_DIRECTORY_GLSL

// Runtime sprite directory, written by the native atlas upload shaders.
// One entry is two RGBA8 texels in the outermost bottom padding row.
// The directory contains no artwork and never occupies sprite image pixels.
uint lbc_glitch_directory_hash(uint value) {
    value ^= value >> 16u;
    value *= 0x7feb352du;
    value ^= value >> 15u;
    value *= 0x846ca68bu;
    return value ^ (value >> 16u);
}

bool lbc_glitch_directory_atlas(ivec2 size) {
    return size.x >= 32 && size.y >= 16;
}

uint lbc_glitch_directory_key(ivec4 sprite) {
    return lbc_glitch_directory_hash(uint(sprite.x) | (uint(sprite.y) << 16u));
}

uint lbc_glitch_directory_slot(uint key, uint copy, uint slots) {
    return lbc_glitch_directory_hash(key + copy * 0x9e3779b9u) % slots;
}

uint lbc_glitch_directory_check(ivec4 sprite) {
    uint extent = uint(sprite.z) | (uint(sprite.w) << 8u);
    return lbc_glitch_directory_hash(lbc_glitch_directory_key(sprite) ^ extent) & 255u;
}

bool lbc_glitch_directory_eligible(ivec4 sprite) {
    return all(greaterThanEqual(sprite.zw, ivec2(8))) &&
           all(lessThanEqual(sprite.zw, ivec2(128)));
}

vec4 lbc_glitch_directory_record(ivec4 sprite, int halfEntry) {
    uvec4 bytes;
    if (halfEntry == 0) {
        bytes = uvec4(uint(sprite.x) & 255u, uint(sprite.x) >> 8u,
                      uint(sprite.y) & 255u, uint(sprite.y) >> 8u);
    } else {
        bytes = uvec4(sprite.zw, lbc_glitch_directory_check(sprite), 213u);
    }
    return vec4(bytes) / 255.0;
}

ivec4 lbc_glitch_directory_read(sampler2D atlas, uint choice) {
    ivec2 size = textureSize(atlas, 0);
    if (!lbc_glitch_directory_atlas(size)) return ivec4(0);
    int x = int(choice % uint(size.x / 2)) * 2;
    uvec4 position = uvec4(round(texelFetch(atlas, ivec2(x, size.y - 1), 0) * 255.0));
    uvec4 extent = uvec4(round(texelFetch(atlas, ivec2(x + 1, size.y - 1), 0) * 255.0));
    if (extent.a != 213u) return ivec4(0);
    ivec4 sprite = ivec4(int(position.x | (position.y << 8u)),
                        int(position.z | (position.w << 8u)), extent.xy);
    if (!lbc_glitch_directory_eligible(sprite) ||
        any(lessThan(sprite.xy, ivec2(1))) ||
        any(greaterThan(sprite.xy + sprite.zw, size - 1)) ||
        extent.z != lbc_glitch_directory_check(sprite)) return ivec4(0);
    return sprite;
}

#endif
