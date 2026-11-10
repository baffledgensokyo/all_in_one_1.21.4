#version 330
#extension GL_ARB_separate_shader_objects : require
#include <minecraft:globals.glsl>
#include <lbc:bloom_blur.glsl>

layout(std140) uniform BlitConfig {
    vec4 ColorModulate;
    vec2 BlurDir;
};

uniform sampler2D DiffuseSampler;
uniform sampler2D BloomSampler;

layout(location = 0) in vec2 texCoord;
layout(location = 0) out vec4 fragColor;

void main() {
    if (BlurDir.x == 1.0) {
        fragColor = vec4(lbc_bloom_blur(DiffuseSampler, texCoord, BlurDir), 1.0);
    } else {
        vec3 scene = texture(DiffuseSampler, texCoord).rgb * ColorModulate.rgb;
        vec3 bloom = lbc_bloom_blur(BloomSampler, texCoord, BlurDir);
        fragColor = vec4(1.0 - (1.0 - scene) * (1.0 - bloom), 1.0);
    }
}
