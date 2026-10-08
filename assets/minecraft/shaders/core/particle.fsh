#version 330
#extension GL_ARB_separate_shader_objects : require

#include <minecraft:fog.glsl>
#include <minecraft:dynamictransforms.glsl>
#include <minecraft:oit.glsl>

uniform sampler2D Sampler0;

layout(location = 0) in float sphericalVertexDistance;
layout(location = 1) in float cylindricalVertexDistance;
layout(location = 2) in vec2 texCoord0;
layout(location = 3) flat in vec4 vertexColor;

#ifndef OIT_ALPHA_ONLY
layout(location = 0) out vec4 fragColor;
#endif

vec4 calculateFinalColor(vec4 color, bool bypassFog) {
    #ifdef OIT_ACCUMULATE
    color = sampleColorForAccumulation(color);
    vec4 fogColor = vec4(FogColor.rgb * color.a, FogColor.a);
    #else
    vec4 fogColor = FogColor;
    #endif
    if (bypassFog) {
        return color;
    }
    return apply_fog(color, sphericalVertexDistance, cylindricalVertexDistance, FogEnvironmentalStart, FogEnvironmentalEnd, FogRenderDistanceStart, FogRenderDistanceEnd, fogColor);
}

void main() {
    vec4 color = texture(Sampler0, texCoord0) * vertexColor * ColorModulator;
    ivec3 marker = ivec3(round(vertexColor.rgb * 255.0));
    bool laser = marker == ivec3(20, 209, 255) || marker == ivec3(255, 170, 0);
    bool nexus = marker == ivec3(68, 64, 11);
    if (laser) {
        vec2 oneTexel = 1.0 / vec2(textureSize(Sampler0, 0));
        color = texture(Sampler0, texCoord0 + vec2(0.0, oneTexel.y * 10.0)) * vertexColor * ColorModulator;
    } else if (nexus) {
        color = vec4(vec3(72.0, 82.0, 25.0) / 255.0, 1.0);
    }
    if (color.a < 0.1) {
        discard;
    }
    #ifdef OIT_ALPHA_ONLY
    executeAlphaOnlyPhase(gl_FragCoord.z, color.a);
    #else
    fragColor = calculateFinalColor(color, laser || nexus);
    #endif
}
