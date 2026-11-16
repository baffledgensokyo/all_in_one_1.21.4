#version 330
#extension GL_ARB_separate_shader_objects : require

#include <minecraft:globals.glsl>

layout(location = 0) out vec4 fragColor;

void main() {
    // A 24-bit timestamp in RGBA8, with alpha marking initialized history.
    uint tick = uint(GameTime * 16777216.0) & 16777215u;
    fragColor = vec4(vec3(float(tick & 255u), float((tick >> 8u) & 255u),
                         float((tick >> 16u) & 255u)) / 255.0, 1.0);
}
