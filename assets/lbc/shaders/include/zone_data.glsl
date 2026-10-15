#ifndef LBC_ZONE_DATA_GLSL
#define LBC_ZONE_DATA_GLSL

const ivec3 LBC_ZONE_TINT = ivec3(253, 254, 255);
const ivec3 LBC_ZONE_GLOW = ivec3(253, 29, 66);
const int LBC_ZONE_DATA_PIXELS = 57;
const int LBC_ZONE_WALL_TAG = 63;

int lbc_zone_tag(vec2 uv, ivec2 atlasSize) {
    return int(floor(fract(uv.x * float(atlasSize.x)) * 64.0));
}

#endif
