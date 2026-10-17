#version 330
#extension GL_ARB_separate_shader_objects : require

#include <lbc:black_hole_data.glsl>

uniform sampler2D HoleDataSampler;
layout(location = 0) out vec2 texCoord;
layout(location = 1) flat out mat4 holeInverseVP;
layout(location = 5) flat out mat4 holeVP;
layout(location = 9) flat out vec4 holeObjects[16];
layout(location = 25) flat out uvec4 holeStyles[4];
layout(location = 29) flat out uint holeMask;

int holeHeader(int row) {
    ivec3 bytes = ivec3(round(texelFetch(HoleDataSampler, ivec2(56, row), 0).rgb * 255.0));
    return bytes.r == 66 && bytes.g == 72 && (bytes.b == 100 || bytes.b == 101) ? bytes.b - 100 : -1;
}

float holeFloat(int field, int row, inout bool valid) {
    ivec3 low = ivec3(round(texelFetch(HoleDataSampler, ivec2(field * 2, row), 0).rgb * 255.0));
    ivec3 high = ivec3(round(texelFetch(HoleDataSampler, ivec2(field * 2 + 1, row), 0).rgb * 255.0));
    valid = valid && low.b == 201 && high.b == 202;
    uint bits = uint(low.r) | (uint(low.g) << 8u) | (uint(high.r) << 16u) | (uint(high.g) << 24u);
    float value = uintBitsToFloat(bits);
    valid = valid && !isnan(value) && !isinf(value);
    return value;
}

void main() {
    vec2 uv = vec2((gl_VertexIndex << 1) & 2, gl_VertexIndex & 2);
    gl_Position = vec4(uv * 2.0 - 1.0, 0.0, 1.0);
    texCoord = uv;
    holeMask = 0u;
    holeInverseVP = mat4(1.0);
    holeVP = mat4(1.0);
    for (int i = 0; i < 16; i++) holeObjects[i] = vec4(0.0);
    for (int i = 0; i < 4; i++) holeStyles[i] = uvec4(0u);
    ivec2 size = textureSize(HoleDataSampler, 0);
    if (size.x < LBC_BH_PIXELS || size.y < 2 * (LBC_BH_FIRST_ROW + LBC_BH_COUNT)) return;
    for (int slot = 0; slot < LBC_BH_COUNT; slot++) {
        int row = LBC_BH_FIRST_ROW + slot;
        int kind = holeHeader(row);
        if (kind < 0) {
            row = size.y - 1 - row;
            kind = holeHeader(row);
        }
        if (kind < 0) continue;
        bool valid = true;
        vec3 points[4];
        for (int point = 0; point < 4; point++) {
            for (int axis = 0; axis < 3; axis++) points[point][axis] = holeFloat(point * 3 + axis, row, valid);
        }
        mat4 invVP;
        for (int i = 0; i < 16; i++) invVP[i / 4][i % 4] = holeFloat(12 + i, row, valid);
        vec3 x = points[1] - points[0];
        vec3 y = points[2] - points[0];
        vec3 z = points[3] - points[0];
        float radius = length(x);
        if (!valid || radius < 0.0001 || radius > 1000000.0 ||
            length(y) < 0.0001 || length(z) < 0.0001 || abs(determinant(invVP)) < 1e-16) continue;
        holeObjects[slot] = vec4(points[0], radius);
        uvec3 normal = uvec3(round(clamp(normalize(y) * 0.5 + 0.5, 0.0, 1.0) * 1023.0));
        holeStyles[slot / 4][slot % 4] = normal.x | (normal.y << 10u) |
                                          (normal.z << 20u) | (uint(kind) << 30u);
        if (holeMask == 0u) {
            holeInverseVP = invVP;
            holeVP = inverse(invVP);
        }
        holeMask |= 1u << uint(slot);
    }
}
