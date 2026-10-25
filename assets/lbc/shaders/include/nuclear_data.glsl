#ifndef LBC_NUCLEAR_DATA_GLSL
#define LBC_NUCLEAR_DATA_GLSL

const int LBC_NUCLEAR_COUNT = 16;
// Rows 0..17 belong to the zone and the sixteen black holes.
const int LBC_NUCLEAR_FIRST_ROW = 18;
// Fade carriers have independent input rows, then resolve to the same slots.
// History stays 171x68; the outline/alpha transport needs 100 rows.
const int LBC_NUCLEAR_FADE_FIRST_ROW = LBC_NUCLEAR_FIRST_ROW + LBC_NUCLEAR_COUNT;
const int LBC_NUCLEAR_DATA_ROWS = 2 * (LBC_NUCLEAR_FADE_FIRST_ROW + LBC_NUCLEAR_COUNT);
const int LBC_EFFECT_ROWS = 2 * (LBC_NUCLEAR_FIRST_ROW + LBC_NUCLEAR_COUNT);
const ivec3 LBC_NUCLEAR_TINT = ivec3(251, 254, 255);

int lbc_nuclear_slot(vec3 color) {
    ivec3 bytes = ivec3(round(color * 255.0));
    return bytes.r == 231 && (bytes.g == 164 || bytes.g == 165) && bytes.b < LBC_NUCLEAR_COUNT ? bytes.b : -1;
}

bool lbc_nuclear_fade_carrier(vec3 color) {
    return int(round(color.g * 255.0)) == 165;
}

bool lbc_nuclear_header(ivec3 bytes, bool fading) {
    return all(equal(bytes, ivec3(78, 85, fading ? 76 : 75)));
}

bool lbc_nuclear_reserved_pixel(vec2 position, vec2 size) {
    float first = float(LBC_NUCLEAR_FIRST_ROW);
    float last = float(LBC_NUCLEAR_FADE_FIRST_ROW + LBC_NUCLEAR_COUNT);
    float row = min(position.y, size.y - position.y);
    return position.x < 57.0 && row >= first && row < last;
}

#endif
