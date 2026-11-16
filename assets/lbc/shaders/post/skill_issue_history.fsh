#version 330
#extension GL_ARB_separate_shader_objects : require

uniform sampler2D InSampler;
layout(location = 0) out vec4 fragColor;

void main() {
    // History alpha is only a readiness flag; presentation retains scene alpha.
    vec3 color = texelFetch(InSampler, ivec2(gl_FragCoord.xy), 0).rgb;
    fragColor = vec4(color, 1.0);
}
