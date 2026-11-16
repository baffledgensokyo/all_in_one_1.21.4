#version 330
#extension GL_ARB_separate_shader_objects : require

uniform sampler2D InSampler;
uniform sampler2D HistorySampler;
layout(location = 0) out vec4 fragColor;

// Redraw visible detail; leave the rest of the old screen untouched.
const float DETAIL_THRESHOLD = 0.10;

float colorDifference(vec3 a, vec3 b) {
    vec3 difference = abs(a - b);
    return max(difference.r, max(difference.g, difference.b));
}

void main() {
    ivec2 pixel = ivec2(gl_FragCoord.xy);
    vec4 scene = texelFetch(InSampler, pixel, 0);
    vec4 history = texelFetch(HistorySampler, pixel, 0);
    if (history.a < 0.5) {
        fragColor = scene;
        return;
    }

    ivec2 lastPixel = textureSize(InSampler, 0) - 1;
    vec3 left = texelFetch(InSampler, max(pixel - ivec2(1, 0), ivec2(0)), 0).rgb;
    vec3 right = texelFetch(InSampler, min(pixel + ivec2(1, 0), lastPixel), 0).rgb;
    vec3 down = texelFetch(InSampler, max(pixel - ivec2(0, 1), ivec2(0)), 0).rgb;
    vec3 up = texelFetch(InSampler, min(pixel + ivec2(0, 1), lastPixel), 0).rgb;
    float detail = max(max(colorDifference(scene.rgb, left), colorDifference(scene.rgb, right)),
                       max(colorDifference(scene.rgb, down), colorDifference(scene.rgb, up)));

    // Stamp new contours over the saved screen, like windows on a desktop
    // whose background no longer repaints. Old pixels never fade or brighten.
    vec3 color = detail >= DETAIL_THRESHOLD ? scene.rgb : history.rgb;
    fragColor = vec4(color, scene.a);
}
