#version 330
#extension GL_ARB_separate_shader_objects : require
#include <minecraft:globals.glsl>

uniform sampler2D HistorySampler;
layout(location = 0) out vec4 fragColor;

vec4 packFloat(float value) {
    uint b = floatBitsToUint(value);
    return vec4(float(b & 255u), float((b >> 8u) & 255u),
                float((b >> 16u) & 255u), float((b >> 24u) & 255u)) / 255.0;
}

float readFloat(int x) {
    uvec4 b = uvec4(round(texelFetch(HistorySampler, ivec2(x, 0), 0) * 255.0));
    return uintBitsToFloat(b.x | (b.y << 8u) | (b.z << 16u) | (b.w << 24u));
}

void main() {
    bool valid = all(equal(ivec4(round(texelFetch(HistorySampler, ivec2(2, 0), 0) * 255.0)),
                           ivec4(90, 79, 79, 77)));
    float now = GameTime * 1200.0;
    float elapsed = 0.0;
    if (valid) {
        float dt = now - readFloat(1);
        if (dt < 0.0) dt += 1200.0;
        elapsed = min(readFloat(0) + dt, 10.0);
    }
    int x = int(gl_FragCoord.x);
    fragColor = x == 0 ? packFloat(elapsed) :
                x == 1 ? packFloat(now) : vec4(90, 79, 79, 77) / 255.0;
}
