#version 330
#extension GL_ARB_separate_shader_objects : require
#include <minecraft:globals.glsl>

#define WIDTH 1
uniform sampler2D DiffuseSampler;
uniform sampler2D NexusOutlineSampler;
uniform sampler2D MainDepthSampler;

layout(location = 0) in vec2 texCoord;
layout(location = 0) out vec4 fragColor;

void main() {
    vec2 oneTexel = 1.0 / vec2(textureSize(NexusOutlineSampler, 0));
    vec4 center = texture(NexusOutlineSampler, texCoord);
    bool edge = false;
    for (int y = -WIDTH; y <= WIDTH; y++) {
        for (int x = -WIDTH; x <= WIDTH; x++) {
            vec4 neighbour = texture(NexusOutlineSampler, texCoord + oneTexel * vec2(x, y));
            if (any(greaterThan(abs(center - neighbour), vec4(0.02, 0.02, 0.02, 0.0)))) {
                edge = true;
            }
        }
    }

    vec4 color = texture(DiffuseSampler, texCoord);
    if (texture(MainDepthSampler, texCoord).r < 1.0) {
        float luminance = (color.r + color.g + color.b) / 3.0;
        float phase = fract(GameTime * 12.0);
        int scanline = int(texCoord.y * ScreenSize.y + phase * ScreenSize.y);
        if ((scanline / 4) % 2 == 0) {
            luminance -= 0.3;
        }
        color = mix(vec4(0.0, 0.082, 0.308, 1.0), vec4(0.169, 0.847, 0.576, 1.0), luminance);
    }
    if (edge && center.a > 0.0) {
        color.rgb = center.rgb;
    }
    fragColor = color;
}
