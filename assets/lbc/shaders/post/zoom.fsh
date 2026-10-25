#version 330
#extension GL_ARB_separate_shader_objects : require

// Shared by zoom (entry) and zoom_out (exit). See blockbench/zoom.txt.
// 26.3 applies this before the 2D GUI, but after rendering the hand.
uniform sampler2D InSampler;
uniform sampler2D AnimationSampler;

layout(std140) uniform SamplerInfo {
    vec2 OutSize;
    vec2 InSize;
    vec2 AnimationSize;
};

layout(std140) uniform ZoomConfig {
    float ZoomFactor;
    float Direction;
    float Duration;
};

layout(location = 0) in vec2 texCoord;
layout(location = 0) out vec4 fragColor;

float readElapsed() {
    uvec4 b = uvec4(round(texelFetch(AnimationSampler, ivec2(0, 0), 0) * 255.0));
    return uintBitsToFloat(b.x | (b.y << 8u) | (b.z << 16u) | (b.w << 24u));
}

vec4 cubicWeights(float t) {
    return vec4(-0.5*t + t*t - 0.5*t*t*t,
                1.0 - 2.5*t*t + 1.5*t*t*t,
                0.5*t + 2.0*t*t - 1.5*t*t*t,
                -0.5*t*t + 0.5*t*t*t);
}

vec3 sharpScene(vec2 uv) {
    // Catmull-Rom reconstruction, independent of hardware bilinear filtering.
    // Clamp to the central four texels to suppress ringing on bright edges.
    ivec2 size = textureSize(InSampler, 0);
    vec2 p = uv * vec2(size) - 0.5;
    ivec2 base = ivec2(floor(p));
    vec4 wx = cubicWeights(fract(p.x));
    vec4 wy = cubicWeights(fract(p.y));
    vec3 color = vec3(0.0), lo = vec3(1.0), hi = vec3(0.0);
    for (int y = 0; y < 4; ++y) {
        for (int x = 0; x < 4; ++x) {
            vec3 c = texelFetch(InSampler, clamp(base + ivec2(x-1, y-1), ivec2(0), size-1), 0).rgb;
            color += c * wx[x] * wy[y];
            if (x >= 1 && x <= 2 && y >= 1 && y <= 2) {
                lo = min(lo, c);
                hi = max(hi, c);
            }
        }
    }
    return clamp(color, lo, hi);
}

void main() {
    float t = clamp(readElapsed() / max(Duration, 0.001), 0.0, 1.0);
    float easeOut = 1.0 - pow(1.0 - t, 3.0);
    float amount = Direction > 0.0 ? easeOut : 1.0 - easeOut;
    if (amount <= 0.0) {
        fragColor = texelFetch(InSampler, ivec2(gl_FragCoord.xy), 0);
        return;
    }

    vec2 center = OutSize * 0.5;
    vec2 offset = gl_FragCoord.xy - center;
    float radius = mix(length(center) + 2.0, min(OutSize.x, OutSize.y) * 0.465, amount);
    float distanceFromCenter = length(offset);
    float shadow = smoothstep(radius * 0.88, radius, distanceFromCenter);
    if (shadow >= 1.0 && amount >= 1.0) {
        fragColor = vec4(0.0, 0.0, 0.0, 1.0);
        return;
    }

    float zoom = mix(1.0, ZoomFactor, amount);
    vec2 zoomCoord = (texCoord - vec2(0.5)) / zoom + vec2(0.5);
    vec3 scene = sharpScene(zoomCoord);
    scene *= 1.0 - amount * shadow;

    // Exactly two framebuffer pixels, independent of GUI scale and zoom.
    // Odd-sized viewports necessarily put an even-width line half a pixel off center.
    vec2 pixel = floor(gl_FragCoord.xy);
    vec2 lineStart = floor(center) - 1.0;
    bool vertical = pixel.x >= lineStart.x && pixel.x < lineStart.x + 2.0;
    bool horizontal = pixel.y >= lineStart.y && pixel.y < lineStart.y + 2.0;
    if (vertical || horizontal) scene *= 1.0 - amount;
    fragColor = vec4(scene, 1.0);
}
