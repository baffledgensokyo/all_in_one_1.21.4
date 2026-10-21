#ifndef LBC_NUCLEAR_TRANSFER_GLSL
#define LBC_NUCLEAR_TRANSFER_GLSL
#include <lbc:nuclear_data.glsl>

// Continue the existing alpha transport below the black-hole rows. RGB is
// untouched, and both edge copies survive normal glowing and hand rendering.
float lbc_nuclear_encode_alpha(sampler2D data, ivec2 pixel, ivec2 size, float original) {
    int row = min(pixel.y, size.y - 1 - pixel.y);
    if (pixel.x >= 171 || row < LBC_NUCLEAR_FIRST_ROW ||
        row >= LBC_NUCLEAR_FIRST_ROW + LBC_NUCLEAR_COUNT) return original;
    ivec2 dataSize = textureSize(data, 0);
    if (dataSize.x < 57 || dataSize.y < LBC_EFFECT_ROWS) return 1.0;
    ivec3 header = ivec3(round(texelFetch(data, ivec2(56, row), 0).rgb * 255.0));
    if (any(notEqual(header, ivec3(78,85,75)))) {
        row = dataSize.y - 1 - row;
        header = ivec3(round(texelFetch(data, ivec2(56, row), 0).rgb * 255.0));
    }
    if (any(notEqual(header, ivec3(78,85,75)))) return 1.0;
    return texelFetch(data, ivec2(pixel.x / 3, row), 0)[pixel.x % 3];
}
#endif
