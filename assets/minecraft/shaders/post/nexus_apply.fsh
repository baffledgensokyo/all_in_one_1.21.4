#version 330
#extension GL_ARB_separate_shader_objects : require

uniform sampler2D DiffuseSampler;
uniform sampler2D NexusSampler;
uniform sampler2D BloomSampler;

layout(location = 0) in vec2 texCoord;
layout(location = 0) out vec4 fragColor;

void main() {
    bool glowing = any(greaterThan(texture(BloomSampler, texCoord).rgb, vec3(0.0)));
    if (!glowing) {
        fragColor = texture(NexusSampler, texCoord);
    } else {
        fragColor = texture(DiffuseSampler, texCoord);
    }
}
