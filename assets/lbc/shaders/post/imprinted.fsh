#version 330
#extension GL_ARB_separate_shader_objects : require

#include <minecraft:globals.glsl>

uniform sampler2D InSampler;
layout(location = 0) out vec4 fragColor;

const float GRAY_LEVELS = 16.0;
const float GRAIN_STRENGTH = 0.065;
const float DUST_STRENGTH = 0.24;
const float GRAIN_UPDATES_PER_SECOND = 8.0;
const float BREATH_SECONDS = 6.0;

// The ordered texture stays stable while its vignette breathes around it.
const int BAYER[16] = int[](
     0,  8,  2, 10,
    12,  4, 14,  6,
     3, 11,  1,  9,
    15,  7, 13,  5
);

float imprintedNoise(ivec2 pixel, uint seed) {
    uint bits = uint(pixel.x) * 1597334677u ^ uint(pixel.y) * 3812015801u ^ seed * 2798796415u;
    bits ^= bits >> 16u;
    bits *= 2246822519u;
    bits ^= bits >> 13u;
    return float(bits & 16777215u) / 16777216.0;
}

float driftingDust(vec2 point, float seconds, vec2 velocity, float cellSize, float size, uint seed) {
    // Subtracting the offset moves persistent flecks toward +X/+Y: upper right.
    vec2 drifting = point - velocity * seconds;
    drifting.x -= 2.5 * sin(seconds * 0.8 + float(seed));
    ivec2 cell = ivec2(floor(drifting / cellSize));
    vec2 local = mod(drifting, cellSize);
    vec2 randomCenter = vec2(imprintedNoise(cell, seed), imprintedNoise(cell, seed + 1u));
    // Keep each fleck inside its cell so it never clips at a moving grid edge.
    vec2 center = mix(vec2(4.0), vec2(cellSize - 4.0), randomCenter);
    float radius = mix(0.75, 1.65, imprintedNoise(cell, seed + 2u)) * size;
    float distance = length(local - center);
    float softness = max(fwidth(distance), 0.35) * 0.5;
    float fleck = 1.0 - smoothstep(radius - softness, radius + softness, distance);
    float shade = mix(-1.0, 0.85, step(0.45, imprintedNoise(cell, seed + 3u)));
    return fleck * shade;
}

void main() {
    ivec2 pixel = ivec2(gl_FragCoord.xy);
    vec2 screenSize = vec2(textureSize(InSampler, 0));
    float seconds = GameTime * 1200.0;
    vec4 scene = texelFetch(InSampler, pixel, 0);
    float gray = dot(scene.rgb, vec3(0.2126, 0.7152, 0.0722));
    gray = clamp((gray - 0.5) * 1.06 + 0.5, 0.0, 1.0);

    // An elliptical vignette contracts and expands smoothly once per breath.
    vec2 centered = gl_FragCoord.xy / screenSize * 2.0 - 1.0;
    float breath = 0.5 - 0.5 * cos(seconds * 6.28318530718 / BREATH_SECONDS);
    float innerRadius = mix(0.30, 0.65, breath);
    float vignette = smoothstep(innerRadius, innerRadius + 0.65, length(centered));
    gray *= 1.0 - 0.20 * vignette;

    // Mostly fixed grain, with a small time-dependent component. Clock-based
    // updates keep its motion independent of FPS without full-screen flashing.
    uint frame = uint(floor(seconds * GRAIN_UPDATES_PER_SECOND));
    float fixedGrain = imprintedNoise(pixel, 1u);
    float movingGrain = imprintedNoise(pixel, frame + 101u);
    float grain = mix(fixedGrain, movingGrain, 0.25) - 0.5;
    float midtones = 4.0 * gray * (1.0 - gray);
    gray += grain * GRAIN_STRENGTH * midtones;

    // Two depths of continuously moving dust, scaled consistently with height.
    vec2 dustPoint = gl_FragCoord.xy * (1080.0 / screenSize.y);
    float dust = driftingDust(dustPoint, seconds, vec2(26.0, 34.0), 30.0, 1.0, 51u);
    dust += driftingDust(dustPoint, seconds, vec2(48.0, 62.0), 54.0, 1.45, 79u) * 0.85;
    gray += dust * DUST_STRENGTH;

    ivec2 ditherPixel = pixel / 2;
    int index = (ditherPixel.y & 3) * 4 + (ditherPixel.x & 3);
    float threshold = (float(BAYER[index]) + 0.5) / 16.0 - 0.5;
    float ditherStrength = mix(0.85, 3.0, vignette);
    float steps = GRAY_LEVELS - 1.0;
    gray = clamp(floor(clamp(gray, 0.0, 1.0) * steps + 0.5 + threshold * ditherStrength) / steps, 0.0, 1.0);

    // Keep alpha byte-exact for other post effects and their data transport.
    fragColor = vec4(vec3(gray), scene.a);
}
