#version 330
#extension GL_ARB_separate_shader_objects : require

#include <minecraft:fog.glsl>
#include <minecraft:dynamictransforms.glsl>
#include <minecraft:oit.glsl>

uniform sampler2D Sampler0;

layout(location = 0) in float sphericalVertexDistance;
layout(location = 1) in float cylindricalVertexDistance;
layout(location = 2) in vec2 texCoord0;
layout(location = 3) in vec4 vertexColor;
layout(location = 4) flat in int customParticle;
layout(location = 5) in vec2 particleCoord;

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
    bool laser = customParticle == 1 || customParticle == 2;
    bool nexus = customParticle == 3;
    if (laser) {
        // The original 8x8, 52-pixel dot, independent of sprite packing or age.
        // Never shift UV into a neighbouring (possibly transparent) sprite.
        vec2 pixel = floor(clamp(particleCoord, 0.0, 0.99999) * 8.0) - 3.5;
        if (dot(pixel, pixel) > 16.0) discard;
        color = vertexColor * ColorModulator;
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
