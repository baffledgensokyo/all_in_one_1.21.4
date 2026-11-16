#version 330
#extension GL_ARB_separate_shader_objects : require

#include <minecraft:globals.glsl>

uniform sampler2D InSampler;
uniform sampler2D HistorySampler;
uniform sampler2D ClockSampler;
layout(location = 0) out vec4 fragColor;

// Exponential persistence: larger values leave longer trails, independent of FPS.
const float TRAIL_SECONDS = 0.65;
const float HUE_RADIANS_PER_SECOND = 1.6;

vec3 acidHue(vec3 color, float angle) {
    // Rotate around the gray axis without adding brightness on each feedback loop.
    vec3 axis = vec3(0.57735026919);
    vec3 rotated = color * cos(angle) + cross(axis, color) * sin(angle)
                 + axis * dot(axis, color) * (1.0 - cos(angle));
    rotated = max(rotated, vec3(0.0));
    float peak = max(color.r, max(color.g, color.b));
    return rotated * (peak / max(max(rotated.r, max(rotated.g, rotated.b)), 0.0001));
}

void main() {
    vec2 size = vec2(textureSize(InSampler, 0));
    vec2 uv = gl_FragCoord.xy / size;
    vec4 scene = texelFetch(InSampler, ivec2(gl_FragCoord.xy), 0);
    float gray = dot(scene.rgb, vec3(0.2126, 0.7152, 0.0722));
    vec3 fresh = clamp(mix(vec3(gray), scene.rgb, 1.3), 0.0, 1.0);

    // The separate clock keeps scene alpha intact and rejects stale history
    // after the effect has been disabled. Unsigned subtraction handles day wrap.
    uvec4 clock = uvec4(round(texelFetch(ClockSampler, ivec2(0), 0) * 255.0));
    uint previous = clock.r | (clock.g << 8u) | (clock.b << 16u);
    uint now = uint(GameTime * 16777216.0) & 16777215u;
    float delta = float((now - previous) & 16777215u) * (1200.0 / 16777216.0);
    if (clock.a == 0u || delta > 0.35) {
        fragColor = vec4(fresh, scene.a);
        return;
    }

    float seconds = GameTime * 1200.0;
    vec2 centered = uv - 0.5;
    // Feed the old screen back into itself: slow expansion and liquid drift
    // stretch real previous frames into the trails of an unredrawn desktop.
    vec2 velocity = centered * 0.018;
    velocity += vec2(sin(uv.y * 9.0 + seconds * 0.7),
                     cos(uv.x * 8.0 - seconds * 0.6)) * 0.007;
    velocity.x *= size.y / size.x;
    vec2 historyUV = uv - velocity * delta;
    vec2 halfPixel = 0.5 / size;
    vec3 history = texture(HistorySampler, clamp(historyUV, halfPixel, 1.0 - halfPixel)).rgb;
    history = acidHue(history, delta * HUE_RADIANS_PER_SECOND);

    float persistence = exp(-delta / TRAIL_SECONDS);
    vec3 color = mix(fresh, history, persistence);
    // Unbiased rounding prevents RGBA8 feedback from retaining dim ghosts
    // forever at high FPS. Noise is below one color step.
    uint seed = now ^ (uint(gl_FragCoord.x) * 1597334677u)
                    ^ (uint(gl_FragCoord.y) * 3812015801u);
    uvec3 bits = uvec3(seed) ^ uvec3(2246822519u, 3266489917u, 668265263u);
    bits ^= bits >> 16u;
    bits *= 2246822519u;
    bits ^= bits >> 13u;
    if (delta > 0.0) {
        color += (vec3(bits & 65535u) / 65536.0 - 0.5) / 255.0;
    }
    // Do not smear edge texels into a permanent border outside the saved image.
    if (any(lessThan(historyUV, halfPixel)) || any(greaterThan(historyUV, 1.0 - halfPixel))) {
        color = fresh;
    }
    fragColor = vec4(color, scene.a);
}
