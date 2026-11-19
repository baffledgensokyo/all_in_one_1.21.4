#version 330
#extension GL_ARB_separate_shader_objects : require
#include <lbc:bloom_blur.glsl>
#include <lbc:effect_packet_write.glsl>

layout(std140) uniform BlitConfig {
    vec4 ColorModulate;
    vec2 BlurDir;
};

uniform sampler2D DiffuseSampler;
uniform sampler2D BloomSampler;
uniform sampler2D OutlineSampler;

layout(location = 0) in vec2 texCoord;
layout(location = 0) out vec4 fragColor;

void main() {
    vec4 scene = texture(DiffuseSampler, texCoord);
    vec3 halo = lbc_bloom_to_white(lbc_bloom_blur(BloomSampler, texCoord, BlurDir).rgb);
    vec4 combined = vec4(lbc_bloom_screen(scene.rgb * ColorModulate.rgb, halo), scene.a);
    fragColor = lbc_write_effect_packet(OutlineSampler, ivec2(gl_FragCoord.xy), textureSize(DiffuseSampler, 0), combined);
}
