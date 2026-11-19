#ifndef LBC_EFFECT_PACKET_WRITE
#define LBC_EFFECT_PACKET_WRITE
#include <lbc:effect_packet.glsl>

ivec3 lbc_outline_bytes(sampler2D outlineData, int x, int y) {
    return ivec3(round(texelFetch(outlineData, ivec2(x, y), 0).rgb * 255.0));
}

int lbc_outline_kind(ivec3 header, int row) {
    if (row == 0) return all(equal(header, ivec3(90, 66, 83))) ? LBC_PACKET_ZONE : 0;
    if (row < LBC_NUCLEAR_FIRST_ROW) {
        if (all(equal(header, lbc_packet_header_rgb(LBC_PACKET_HOLE)))) return LBC_PACKET_HOLE;
        if (all(equal(header, lbc_packet_header_rgb(LBC_PACKET_DISK)))) return LBC_PACKET_DISK;
        return 0;
    }
    int kind = row < LBC_NUCLEAR_FADE_FIRST_ROW ? LBC_PACKET_NUCLEAR : LBC_PACKET_FADE;
    return all(equal(header, lbc_packet_header_rgb(kind))) ? kind : 0;
}

// Physical outline row, record kind. Both renderer coordinate conventions
// are accepted before writing the canonical lower strip in the main target.
ivec2 lbc_outline_source(sampler2D outlineData, int row) {
    ivec2 size = textureSize(outlineData, 0);
    if (size.x < 57 || size.y < 2 * (row + 1)) return ivec2(0);
    int kind = lbc_outline_kind(lbc_outline_bytes(outlineData, 56, row), row);
    if (kind != 0) return ivec2(row, kind);
    int mirror = size.y - 1 - row;
    return ivec2(mirror, lbc_outline_kind(lbc_outline_bytes(outlineData, 56, mirror), row));
}

ivec2 lbc_outline_nuclear_source(sampler2D outlineData, int slot) {
    ivec2 source = lbc_outline_source(outlineData, LBC_NUCLEAR_FIRST_ROW + slot);
    return source.y != 0 ? source : lbc_outline_source(outlineData, LBC_NUCLEAR_FADE_FIRST_ROW + slot);
}

ivec2 lbc_outline_view(sampler2D outlineData, int offset) {
    if (offset == LBC_PACKET_HOLE_VIEW) {
        for (int slot = 0; slot < LBC_BH_COUNT; ++slot) {
            ivec2 source = lbc_outline_source(outlineData, LBC_BH_FIRST_ROW + slot);
            if (source.y != 0) return source;
        }
        return lbc_outline_source(outlineData, 0);
    }
    for (int slot = LBC_NUCLEAR_COUNT - 1; slot >= 0; --slot) {
        ivec2 source = lbc_outline_nuclear_source(outlineData, slot);
        if (source.y != 0) return source;
    }
    return ivec2(0);
}

uint lbc_outline_word(sampler2D outlineData, int row, int field, inout bool valid) {
    ivec3 lo = lbc_outline_bytes(outlineData, field * 2, row);
    ivec3 hi = lbc_outline_bytes(outlineData, field * 2 + 1, row);
    valid = valid && lo.b == 201 && hi.b == 202;
    return uint(lo.r) | (uint(lo.g) << 8u) | (uint(hi.r) << 16u) | (uint(hi.g) << 24u);
}

vec4 lbc_write_effect_packet(sampler2D outlineData, ivec2 pixel, ivec2 size, vec4 scene) {
    int index = lbc_packet_index(pixel, size);
    if (index < 0) return scene;
    index %= LBC_PACKET_SIZE;

    int offset, words, first;
    ivec2 source;
    if (index < LBC_PACKET_HOLE_VIEW) {
        int slot = index / LBC_PACKET_OBJECT;
        offset = slot * LBC_PACKET_OBJECT;
        words = LBC_PACKET_POINTS;
        first = 0;
        source = slot < LBC_BH_COUNT ? lbc_outline_source(outlineData, LBC_BH_FIRST_ROW + slot) :
                 lbc_outline_nuclear_source(outlineData, slot - LBC_BH_COUNT);
    } else {
        offset = index < LBC_PACKET_NUCLEAR_VIEW ? LBC_PACKET_HOLE_VIEW : LBC_PACKET_NUCLEAR_VIEW;
        words = LBC_PACKET_MATRIX;
        first = LBC_PACKET_POINTS;
        source = lbc_outline_view(outlineData, offset);
    }
    if (source.y == 0) return scene;

    int cell = index - offset;
    bool valid = true;
    if (cell != 0) {
        uint word = lbc_outline_word(outlineData, source.x, first + cell - 1, valid);
        return valid ? lbc_packet_pack(word) : scene;
    }
    // Exact integrity check catches hand geometry and blends that overwrite
    // only part of a record. The reader can then use its other copy.
    uint hash = uint(offset + source.y);
    for (int i = 0; i < words; ++i) hash = lbc_packet_hash(hash, lbc_outline_word(outlineData, source.x, first + i, valid));
    uint header = (uint(224 + source.y) << 24u) | (hash & 0x00ffffffu);
    return valid ? lbc_packet_pack(header) : scene;
}

#endif
