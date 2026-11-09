#version 330
#extension GL_ARB_separate_shader_objects : require

#include <minecraft:globals.glsl>

uniform sampler2D InSampler;
layout(location = 0) out vec4 fragColor;

const float CELL_DENSITY = 0.50;
// Denser grids of smaller squares leave about 30% of the screen unobstructed.
const float MAX_TILE_FRACTION = 0.80;
const float SWITCH_SECONDS = 0.8;

float cellNoise(ivec2 cell, uint seed) {
    uint bits = uint(cell.x) * 1597334677u ^ uint(cell.y) * 3812015801u ^ seed * 2798796415u;
    bits ^= bits >> 16u;
    bits *= 2246822519u;
    bits ^= bits >> 13u;
    return float(bits & 16777215u) / 16777216.0;
}

vec3 cubeColor(ivec2 cell, uint seed) {
    // Four equally likely slots: black, black, white, independent random RGB.
    int slot = int(cellNoise(cell, seed + 1u) * 4.0);
    if (slot < 2) return vec3(0.0);
    if (slot == 2) return vec3(1.0);
    return vec3(cellNoise(cell, seed + 2u),
                cellNoise(cell, seed + 3u),
                cellNoise(cell, seed + 4u));
}

vec3 cubeGrid(vec3 scene, vec2 point, float pixelWidth, float seconds,
              float cellSize, vec2 offset, uint layerSeed) {
    vec2 grid = point / cellSize + offset;
    ivec2 cell = ivec2(floor(grid));
    vec2 local = (fract(grid) - 0.5) * cellSize;

    // Every cell switches on its own clock, including cells in currently empty areas.
    float period = mix(2.8, 5.5, cellNoise(cell, layerSeed));
    float clock = seconds + cellNoise(cell, layerSeed + 1u) * period;
    uint cycle = uint(int(floor(clock / period)));
    float transition = smoothstep(0.0, SWITCH_SECONDS, mod(clock, period));
    uint previousSeed = layerSeed + (cycle - 1u) * 1013u + 100u;
    uint nextSeed = layerSeed + cycle * 1013u + 100u;
    float previous = 1.0 - step(CELL_DENSITY, cellNoise(cell, previousSeed));
    float next = 1.0 - step(CELL_DENSITY, cellNoise(cell, nextSeed));
    float extent = mix(previous, next, transition);

    // Grow/shrink the square instead of fading it: its interior stays opaque.
    float halfSize = cellSize * MAX_TILE_FRACTION * 0.5 * extent;
    float edge = max(abs(local.x), abs(local.y));
    float face = clamp((halfSize - edge) / pixelWidth + 0.5, 0.0, 1.0);
    face *= step(0.0001, extent);
    if (face <= 0.0) return scene;

    vec3 previousColor = cubeColor(cell, previousSeed);
    vec3 nextColor = cubeColor(cell, nextSeed);
    // Appearing/disappearing cubes retain their color; surviving cubes change smoothly.
    float colorTransition = previous * next * transition + (1.0 - previous);
    vec3 color = mix(previousColor, nextColor, colorTransition);
    return mix(scene, color, face);
}

void main() {
    ivec2 pixel = ivec2(gl_FragCoord.xy);
    vec4 scene = texelFetch(InSampler, pixel, 0);
    float seconds = GameTime * 1200.0;
    float pixelWidth = 720.0 / float(textureSize(InSampler, 0).y);
    vec2 point = gl_FragCoord.xy * pixelWidth;

    // Fixed, offset grids at three scales; the scene itself is sampled unchanged.
    vec3 color = cubeGrid(scene.rgb, point, pixelWidth, seconds, 22.0, vec2(0.0), 17u);
    color = cubeGrid(color, point, pixelWidth, seconds, 35.0, vec2(0.37, 0.61), 131u);
    color = cubeGrid(color, point, pixelWidth, seconds, 51.0, vec2(-0.28, 0.19), 307u);

    // Preserve alpha data used by other post effects.
    fragColor = vec4(color, scene.a);
}
