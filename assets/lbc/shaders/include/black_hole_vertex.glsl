#ifndef LBC_BH_TRACE_COUNT
#define LBC_BH_TRACE_COUNT 16
#endif

#include <lbc:black_hole_data.glsl>
#include <lbc:black_hole_sampling.glsl>

uniform sampler2D HoleDataSampler;
layout(location = 0) out vec2 texCoord;
layout(location = 1) flat out mat4 holeInverseVP;
layout(location = 5) flat out mat4 holeVP;
layout(location = 9) flat out vec4 holeObjects[LBC_BH_TRACE_COUNT];
layout(location = 25) flat out uvec4 holeStyles[(LBC_BH_TRACE_COUNT + 3) / 4];
layout(location = 29) flat out uint holeMask;
layout(location = 30) flat out vec4 holePeripheral;

ivec3 holeBytes(ivec2 pixel) {
#if defined(LBC_BH_PACKED_ALPHA) && !defined(LBC_EFFECT_HISTORY)
    int x = pixel.x * 3;
    return ivec3(round(vec3(texelFetch(HoleDataSampler, ivec2(x, pixel.y), 0).a,
                           texelFetch(HoleDataSampler, ivec2(x + 1, pixel.y), 0).a,
                           texelFetch(HoleDataSampler, ivec2(x + 2, pixel.y), 0).a) * 255.0));
#else
    return ivec3(round(texelFetch(HoleDataSampler, pixel, 0).rgb * 255.0));
#endif
}

int holeHeader(int row) {
    ivec3 bytes = holeBytes(ivec2(56, row));
    return bytes.r == 66 && bytes.g == 72 && (bytes.b == 100 || bytes.b == 101) ? bytes.b - 100 : -1;
}

float holeFloat(int field, int row, inout bool valid) {
    ivec3 low = holeBytes(ivec2(field * 2, row));
    ivec3 high = holeBytes(ivec2(field * 2 + 1, row));
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
    holePeripheral = vec4(0.0);
    float peripheralDistance = 4.0;
    holeInverseVP = mat4(1.0);
    holeVP = mat4(1.0);
    for (int i = 0; i < LBC_BH_TRACE_COUNT; i++) holeObjects[i] = vec4(0.0);
    for (int i = 0; i < (LBC_BH_TRACE_COUNT + 3) / 4; i++) holeStyles[i] = uvec4(0u);
    ivec2 size = textureSize(HoleDataSampler, 0);
#if defined(LBC_BH_PACKED_ALPHA) && !defined(LBC_EFFECT_HISTORY)
    if (size.x < LBC_BH_PIXELS * 3 || size.y < 2 * (LBC_BH_FIRST_ROW + LBC_BH_COUNT)) return;
#else
    if (size.x < LBC_BH_PIXELS || size.y < 2 * (LBC_BH_FIRST_ROW + LBC_BH_COUNT)) return;
#endif
    int count = 0;
    for (int slot = 0; slot < LBC_BH_COUNT; slot++) {
        for (int replica = 0; replica < 2; replica++) {
            int row = replica == 0 ? LBC_BH_FIRST_ROW + slot : size.y - 1 - LBC_BH_FIRST_ROW - slot;
            int kind = holeHeader(row);
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
#ifdef LBC_EFFECT_HISTORY
            // Grow/collapse the actual lens, shadow and disk together. Never
            // crossfade two differently refracted copies of the world.
            uvec4 fadeBytes=uvec4(round(texelFetch(HoleDataSampler,ivec2(58,row),0)*255.0));
            float appearance=uintBitsToFloat(fadeBytes.x|(fadeBytes.y<<8u)|(fadeBytes.z<<16u)|(fadeBytes.w<<24u));
            if(isnan(appearance)||isinf(appearance)||appearance<0.0||appearance>1.2)continue;
            radius*=appearance;
            if(radius<0.0001)continue;
#endif
            // Transport slots stay server-assigned; compact only the decoded
            // shader list. Ray steps must not scan fifteen empty slots for one
            // hole. Preserve slot order so accumulation remains unchanged.
            if (count < LBC_BH_TRACE_COUNT) holeObjects[count] = vec4(points[0], radius);
            float cameraDistance = length(points[0]) / radius;
            if (cameraDistance >= 1.0 && cameraDistance < peripheralDistance) {
                peripheralDistance = cameraDistance;
                float strength = 1.0 - smoothstep(3.0, 4.0, cameraDistance);
                holePeripheral = vec4(normalize(-points[0]), strength);
            }
            uvec3 normal = uvec3(round(clamp(normalize(y) * 0.5 + 0.5, 0.0, 1.0) * 1023.0));
            if (count < LBC_BH_TRACE_COUNT) holeStyles[count / 4][count % 4] = normal.x | (normal.y << 10u) |
                                              (normal.z << 20u) | (uint(kind) << 30u);
            if (holeMask == 0u) {
                holeInverseVP = invVP;
                holeVP = inverse(invVP);
            }
            holeMask |= 1u << uint(count);
            count++;
            break;
        }
    }
#ifdef LBC_BH_NEAR_ONLY
    if (holePeripheral.w <= 0.0) gl_Position = vec4(4.0,4.0,0.0,1.0);
#endif
#ifdef LBC_BH_FAR_ONLY
    if (holePeripheral.w > 0.0) gl_Position = vec4(4.0,4.0,0.0,1.0);
    holePeripheral = vec4(0.0);
    vec2 farScale = ceil(vec2(size) / lbc_bh_far_stride()) / vec2(size);
    gl_Position.xy = (gl_Position.xy + 1.0) * farScale - 1.0;
#endif
#ifdef LBC_BH_COARSE_PASS
    // Use the same grid spacing as trace and resolve, including partial tiles.
    float stride = lbc_bh_stride(holePeripheral);
    vec2 coarseScale = ceil(vec2(size) / stride) / vec2(size);
    gl_Position.xy = (gl_Position.xy + 1.0) * coarseScale - 1.0;
    if (holePeripheral.w <= 0.0) gl_Position = vec4(4.0, 4.0, 0.0, 1.0);
#endif
#ifdef LBC_BH_FAST_OBJECTS
    if (holeMask > 3u) gl_Position = vec4(4.0,4.0,0.0,1.0);
#endif
#ifdef LBC_BH_MANY_OBJECTS
    if (holeMask <= 3u) gl_Position = vec4(4.0,4.0,0.0,1.0);
#endif

}

