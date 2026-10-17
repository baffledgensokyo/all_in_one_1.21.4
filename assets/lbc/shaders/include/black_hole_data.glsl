#ifndef LBC_BLACK_HOLE_DATA_GLSL
#define LBC_BLACK_HOLE_DATA_GLSL

const int LBC_BH_COUNT = 16;
const int LBC_BH_PIXELS = 57;
const int LBC_BH_FIRST_ROW = 2;
const ivec3 LBC_BH_SMALL_TINT = ivec3(252, 254, 255);
const ivec3 LBC_BH_DISK_TINT = ivec3(252, 253, 255);
// #B14A00 .. #B14A0F: blue is the independently allocated object slot.
int lbc_bh_slot(vec3 color) {
    ivec3 bytes = ivec3(round(color * 255.0));
    return bytes.r == 177 && bytes.g == 74 && bytes.b < LBC_BH_COUNT ? bytes.b : -1;
}

bool lbc_bh_reserved_pixel(vec2 position, vec2 size) {
    float rows = float(LBC_BH_FIRST_ROW + LBC_BH_COUNT);
    return position.x < float(LBC_BH_PIXELS) &&
           (position.y < rows || position.y > size.y - rows);
}

#endif
