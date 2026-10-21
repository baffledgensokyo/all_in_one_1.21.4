#ifndef LBC_NUCLEAR_DATA_GLSL
#define LBC_NUCLEAR_DATA_GLSL

const int LBC_NUCLEAR_COUNT = 16;
// Rows 0..17 belong to the zone and the sixteen black holes.
const int LBC_NUCLEAR_FIRST_ROW = 18;
const int LBC_EFFECT_ROWS = 2 * (LBC_NUCLEAR_FIRST_ROW + LBC_NUCLEAR_COUNT);
const ivec3 LBC_NUCLEAR_TINT = ivec3(251, 254, 255);

int lbc_nuclear_slot(vec3 color) {
    ivec3 bytes = ivec3(round(color * 255.0));
    return bytes.r == 231 && bytes.g == 164 && bytes.b < LBC_NUCLEAR_COUNT ? bytes.b : -1;
}

bool lbc_nuclear_reserved_pixel(vec2 position, vec2 size) {
    float first = float(LBC_NUCLEAR_FIRST_ROW);
    float last = first + float(LBC_NUCLEAR_COUNT);
    float row = min(position.y, size.y - position.y);
    return position.x < 57.0 && row >= first && row < last;
}

#endif
