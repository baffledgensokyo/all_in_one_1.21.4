#version 330
#extension GL_ARB_separate_shader_objects : require
#include <lbc:bloom_rules.glsl>
#include <lbc:effect_packet.glsl>
uniform sampler2D DiffuseSampler;
layout(location = 0) out vec4 fragColor;
void main() {
    ivec2 pixel = ivec2(gl_FragCoord.xy);
    vec4 scene = texelFetch(DiffuseSampler, lbc_packet_clean_pixel(pixel, textureSize(DiffuseSampler, 0)), 0);
    fragColor = vec4(0.0);
    if (!lbc_bloom_marked(scene)) return;
    int index = lbc_bloom_rule(scene.rgb);
    if (index < 0) return;
    LbcBloomRule rule = LBC_BLOOM_RULES[index];
    // RGBA8 intermediate: retain headroom for strengths up to4, restore after blur.
    float weight = clamp(rule.strength, 0.0, 4.0) / 4.0;
    // RGB carries light; alpha carries a black halo. Unmarked pixels stay zero.
    fragColor = vec4(vec3(rule.halo) / 255.0 * weight, lbc_bloom_dark(rule) ? weight : 0.0);
}
