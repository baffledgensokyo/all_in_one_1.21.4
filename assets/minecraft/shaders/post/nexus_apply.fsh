#version 330
#extension GL_ARB_separate_shader_objects : require
#include <lbc:bloom_rules.glsl>

uniform sampler2D DiffuseSampler;
uniform sampler2D NexusSampler;

layout(location = 0) out vec4 fragColor;

void main() {
    ivec2 pixel = ivec2(gl_FragCoord.xy);
    vec4 scene = texelFetch(DiffuseSampler, pixel, 0);
    fragColor = lbc_bloom_marked(scene) ? scene : texelFetch(NexusSampler, pixel, 0);
}
