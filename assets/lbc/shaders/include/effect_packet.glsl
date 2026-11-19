#ifndef LBC_EFFECT_PACKET
#define LBC_EFFECT_PACKET
#include <lbc:black_hole_data.glsl>
#include <lbc:nuclear_data.glsl>

// One RGBA8 texel per 32-bit word. Object slots store four reference points;
// the view/projection matrix is shared by all carriers of each effect type.
const int LBC_PACKET_POINTS = 12;
const int LBC_PACKET_MATRIX = 16;
const int LBC_PACKET_OBJECT = 1 + LBC_PACKET_POINTS;
const int LBC_PACKET_VIEW = 1 + LBC_PACKET_MATRIX;
const int LBC_PACKET_HOLE_VIEW = (LBC_BH_COUNT + LBC_NUCLEAR_COUNT) * LBC_PACKET_OBJECT;
const int LBC_PACKET_NUCLEAR_VIEW = LBC_PACKET_HOLE_VIEW + LBC_PACKET_VIEW;
const int LBC_PACKET_SIZE = LBC_PACKET_NUCLEAR_VIEW + LBC_PACKET_VIEW;
const int LBC_PACKET_LEFT = 4; // Nexus corner marker.
const int LBC_PACKET_RIGHT = 12; // TimeStop header.
const int LBC_PACKET_ZONE = 1;
const int LBC_PACKET_HOLE = 2;
const int LBC_PACKET_DISK = 3;
const int LBC_PACKET_NUCLEAR = 4;
const int LBC_PACKET_FADE = 5;

int lbc_packet_span(ivec2 size) {
    return size.x - LBC_PACKET_LEFT - LBC_PACKET_RIGHT;
}

int lbc_packet_rows(ivec2 size) {
    int span = lbc_packet_span(size);
    if (span <= 0) return 0;
    int rows = (2 * LBC_PACKET_SIZE + span - 1) / span;
    return rows < size.y ? rows : 0;
}

int lbc_packet_start(int copy, int span) {
    if (copy == 1) return span - LBC_PACKET_SIZE;
    // Center the primary where the first-person hand is least likely to draw.
    return min((span - LBC_PACKET_SIZE) / 2, span - 2 * LBC_PACKET_SIZE);
}

ivec2 lbc_packet_address(int index, ivec2 size) {
    int span = lbc_packet_span(size);
    if (span >= 2 * LBC_PACKET_SIZE) {
        int start = lbc_packet_start(index / LBC_PACKET_SIZE, span);
        return ivec2(LBC_PACKET_LEFT + start + index % LBC_PACKET_SIZE, 0);
    }
    return ivec2(LBC_PACKET_LEFT + index % span, index / span);
}

int lbc_packet_index(ivec2 pixel, ivec2 size) {
    int span = lbc_packet_span(size);
    int x = pixel.x - LBC_PACKET_LEFT;
    if (x < 0 || x >= span || pixel.y * span >= 2 * LBC_PACKET_SIZE || lbc_packet_rows(size) == 0) return -1;
    if (span >= 2 * LBC_PACKET_SIZE) {
        int primary = x - lbc_packet_start(0, span);
        if (primary >= 0 && primary < LBC_PACKET_SIZE) return primary;
        int backup = x - lbc_packet_start(1, span);
        return backup >= 0 ? LBC_PACKET_SIZE + backup : -1;
    }
    int index = pixel.y * span + x;
    return index < 2 * LBC_PACKET_SIZE ? index : -1;
}

ivec2 lbc_packet_clean_pixel(ivec2 pixel, ivec2 size) {
    if (lbc_packet_index(pixel, size) >= 0) pixel.y = lbc_packet_rows(size);
    return pixel;
}

uint lbc_packet_unpack(vec4 value) {
    uvec4 b = uvec4(round(value * 255.0));
    return b.r | (b.g << 8u) | (b.b << 16u) | (b.a << 24u);
}

vec4 lbc_packet_pack(uint word) {
    return vec4(uvec4(word, word >> 8u, word >> 16u, word >> 24u) & 255u) / 255.0;
}

uint lbc_packet_read(sampler2D scene, int index) {
    return lbc_packet_unpack(texelFetch(scene, lbc_packet_address(index, textureSize(scene, 0)), 0));
}

uint lbc_packet_hash(uint hash, uint word) {
    return (hash ^ word) * 16777619u;
}

int lbc_packet_kind(uint header) {
    int kind = int(header >> 24u) - 224;
    return kind >= LBC_PACKET_ZONE && kind <= LBC_PACKET_FADE ? kind : 0;
}

int lbc_packet_kind(sampler2D scene, int base) {
    return lbc_packet_kind(lbc_packet_read(scene, base));
}

int lbc_packet_record(sampler2D scene, int offset, int words, int kind1, int kind2) {
    if (lbc_packet_rows(textureSize(scene, 0)) == 0) return -1;
    for (int copy = 0; copy < 2; ++copy) {
        int base = offset + copy * LBC_PACKET_SIZE;
        uint header = lbc_packet_read(scene, base);
        int kind = lbc_packet_kind(header);
        if (kind != kind1 && kind != kind2) continue;
        uint hash = uint(offset + kind);
        for (int i = 1; i <= words; ++i) hash = lbc_packet_hash(hash, lbc_packet_read(scene, base + i));
        if ((hash & 0x00ffffffu) == (header & 0x00ffffffu)) return base;
    }
    return -1;
}

ivec3 lbc_packet_header_rgb(int kind) {
    if (kind == LBC_PACKET_ZONE) return ivec3(67, 65, 77);
    if (kind == LBC_PACKET_HOLE || kind == LBC_PACKET_DISK) return ivec3(66, 72, 98 + kind);
    if (kind == LBC_PACKET_NUCLEAR || kind == LBC_PACKET_FADE) return ivec3(78, 85, kind == LBC_PACKET_FADE ? 76 : 75);
    return ivec3(0);
}

#endif
