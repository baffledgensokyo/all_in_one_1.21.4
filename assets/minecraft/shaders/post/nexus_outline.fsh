#version 330
#extension GL_ARB_separate_shader_objects : require

uniform sampler2D MainDepthSampler;
layout(location = 0) in vec2 texCoord;
layout(location = 0) out vec4 fragColor;

void main() {
    // 26.3 exposes the combined scene depth, replacing the old per-layer targets.
    float depth = texture(MainDepthSampler, texCoord).r;
    float mask = 1.0 - depth;
    if (mask > 0.0) {
        fragColor = mix(vec4(1.0, 0.14, 0.44, 1.0), vec4(0.16, 0.84, 0.57, 1.0), clamp(pow(mask * 500.0, 4.0), 0.0, 1.0));
    } else {
        fragColor = vec4(0.0);
    }
}
