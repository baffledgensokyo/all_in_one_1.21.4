#version 330
#extension GL_ARB_separate_shader_objects : require
#include <lbc:bloom_blur.glsl>

layout(std140) uniform BlitConfig { vec2 BlurDir; float Whiten; };
uniform sampler2D DiffuseSampler;
layout(location = 0) in vec2 texCoord;
layout(location = 0) out vec4 fragColor;

void main() {
    fragColor = lbc_bloom_blur(DiffuseSampler, texCoord, BlurDir);
    if (Whiten > 0.0) fragColor.rgb = lbc_bloom_to_white(fragColor.rgb);
}
