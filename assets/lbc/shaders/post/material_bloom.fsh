#version 330
#extension GL_ARB_separate_shader_objects : require
#include <lbc:bloom_blur.glsl>
#include <lbc:bloom_rules.glsl>
#include <lbc:effect_packet.glsl>
layout(std140) uniform BlitConfig { vec4 ColorModulate; vec2 BlurDir; };
uniform sampler2D DiffuseSampler;
uniform sampler2D BloomSampler;
layout(location = 0) in vec2 texCoord;
layout(location = 0) out vec4 fragColor;

void main() {
    ivec2 pixel = ivec2(gl_FragCoord.xy);
    vec4 scene = texelFetch(DiffuseSampler, lbc_packet_clean_pixel(pixel, textureSize(DiffuseSampler, 0)), 0);
    bool marked = lbc_bloom_marked(scene);
    int index = marked ? lbc_bloom_rule(scene.rgb) : -1;
    int coreMode = index >= 0 ? LBC_BLOOM_RULES[index].core : LBC_CORE_KEEP;
    vec3 core = lbc_bloom_core(scene.rgb, index) * ColorModulate.rgb;
    vec4 halo = clamp(4.0 * lbc_bloom_blur(BloomSampler, texCoord, BlurDir), 0.0, 1.0);
    vec3 combined = lbc_bloom_screen(core, halo.rgb);
    if (coreMode != LBC_CORE_WHITE) combined *= 1.0 - halo.a;
    if (coreMode == LBC_CORE_BLACK) combined = vec3(0.0);

    // effect_state has consumed the packet. Preserve material coverage for Nexus.
    float sceneAlpha = marked ? 1.0 : scene.a;
    fragColor = vec4(combined, index >= 0 ? 254.0 / 255.0 : sceneAlpha);
}
