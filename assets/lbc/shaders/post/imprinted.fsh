#version 330
#extension GL_ARB_separate_shader_objects : require

#include <minecraft:globals.glsl>

uniform sampler2D InSampler;
layout(location = 0) out vec4 fragColor;

const float GRAY_LEVELS = 32.0;
const float GRAIN_STRENGTH = 0.065;
const float DUST_STRENGTH = 0.12;
const float GRAIN_UPDATES_PER_SECOND = 8.0;

// A stationary ordered threshold gives flat surfaces a printed pixel texture.
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

void main() {
    ivec2 pixel = ivec2(gl_FragCoord.xy);
    vec4 scene = texelFetch(InSampler, pixel, 0);
    float gray = dot(scene.rgb, vec3(0.2126, 0.7152, 0.0722));
    gray = clamp((gray - 0.5) * 1.06 + 0.5, 0.0, 1.0);

    // Mostly fixed grain, with a small time-dependent component. Clock-based
    // updates keep its motion independent of FPS without full-screen flashing.
    uint frame = uint(floor(GameTime * 1200.0 * GRAIN_UPDATES_PER_SECOND));
    float fixedGrain = imprintedNoise(pixel, 1u);
    float movingGrain = imprintedNoise(pixel, frame + 101u);
    float grain = mix(fixedGrain, movingGrain, 0.25) - 0.5;
    float midtones = 4.0 * gray * (1.0 - gray);
    gray += grain * GRAIN_STRENGTH * midtones;

    // Rare two-pixel dust flecks sit over the finer single-pixel grain.
    float dust = imprintedNoise(pixel / 2, 51u);
    if (dust < 0.0035) gray -= DUST_STRENGTH;
    if (dust > 0.9975) gray += DUST_STRENGTH * 0.75;

    int index = (pixel.y & 3) * 4 + (pixel.x & 3);
    float threshold = (float(BAYER[index]) + 0.5) / 16.0 - 0.5;
    float steps = GRAY_LEVELS - 1.0;
    gray = clamp(floor(clamp(gray, 0.0, 1.0) * steps + 0.5 + threshold) / steps, 0.0, 1.0);

    // Keep alpha byte-exact for other post effects and their data transport.
    fragColor = vec4(vec3(gray), scene.a);
}
