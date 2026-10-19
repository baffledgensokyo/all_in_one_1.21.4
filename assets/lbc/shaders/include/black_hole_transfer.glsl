#ifndef LBC_BLACK_HOLE_TRANSFER
#define LBC_BLACK_HOLE_TRANSFER
#include <lbc:black_hole_data.glsl>

// Transport the outline payload in alpha, leaving scene RGB untouched.
// ENTITY_OUTLINE_BLIT writes RGB only in 26.3. Duplicate the strip at both
// vertical edges so the first-person hand can cover one copy safely.
bool lbc_bh_carrier_pixel(ivec2 pixel, ivec2 size) {
    int rows = LBC_BH_FIRST_ROW + LBC_BH_COUNT;
    return pixel.x < LBC_BH_PIXELS * 3 &&
           (pixel.y < rows || pixel.y >= size.y - rows);
}

bool lbc_bh_header(ivec3 bytes) {
    return bytes.r == 66 && bytes.g == 72 && (bytes.b == 100 || bytes.b == 101);
}

float lbc_bh_encode_alpha(sampler2D data, ivec2 pixel, ivec2 size, float original) {
    if (!lbc_bh_carrier_pixel(pixel, size)) return original;
    ivec2 dataSize = textureSize(data, 0);
    int row = min(pixel.y, size.y - 1 - pixel.y);
    if (row < LBC_BH_FIRST_ROW || dataSize.x < LBC_BH_PIXELS ||
        dataSize.y < 2 * (LBC_BH_FIRST_ROW + LBC_BH_COUNT)) return 1.0;
    ivec3 header = ivec3(round(texelFetch(data, ivec2(56, row), 0).rgb * 255.0));
    if (!lbc_bh_header(header)) {
        row = dataSize.y - 1 - row;
        header = ivec3(round(texelFetch(data, ivec2(56, row), 0).rgb * 255.0));
    }
    if (!lbc_bh_header(header)) return 1.0;
    return texelFetch(data, ivec2(pixel.x / 3, row), 0)[pixel.x % 3];
}

#endif
