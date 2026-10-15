#version 330
#extension GL_ARB_separate_shader_objects : require

#include <minecraft:dynamictransforms.glsl>
#include <minecraft:globals.glsl>
#include <lbc:zone_data.glsl>

uniform sampler2D Sampler0;
layout(location = 0) in vec4 vertexColor;
layout(location = 1) in vec2 texCoord0;
layout(location = 2) flat in int zoneDataIndex;
layout(location = 3) in float zoneDataValue;
layout(location = 0) out vec4 fragColor;

void main() {
    if (zoneDataIndex >= 0) {
        if (zoneDataIndex == 56) {
            fragColor = vec4(vec3(90, 66, 83) / 255.0, 0.0);
        } else {
            uint bits = floatBitsToUint(zoneDataValue);
            uint shift = (zoneDataIndex % 2 == 0) ? 0u : 16u;
            vec3 bytes = vec3(float((bits >> shift) & 255u),
                              float((bits >> (shift + 8u)) & 255u),
                              (zoneDataIndex % 2 == 0) ? 201.0 : 202.0);
            fragColor = vec4(bytes / 255.0, 0.0);
        }
        return;
    }
    // Protect invisible data against other glowing entities in this tiny strip.
    if (gl_FragCoord.x < float(LBC_ZONE_DATA_PIXELS) &&
        (gl_FragCoord.y < 1.0 || gl_FragCoord.y > ScreenSize.y - 1.0)) {
        discard;
    }
    vec4 color = texture(Sampler0, texCoord0);
    if (color.a == 0.0) discard;
    fragColor = vec4(ColorModulator.rgb * vertexColor.rgb, ColorModulator.a);
}
