#version 330
#extension GL_ARB_separate_shader_objects : require

uniform sampler2D DiffuseSampler;
uniform sampler2D NexusSampler;
uniform sampler2D ControlSampler;
uniform sampler2D BloomSampler;

layout(location = 0) in vec2 texCoord;
layout(location = 0) out vec4 fragColor;

void main() {
    ivec3 marker = ivec3(round(texelFetch(ControlSampler, ivec2(1, 1), 0).rgb * 255.0));
    bool nexusEnabled = all(lessThanEqual(abs(marker - ivec3(72, 82, 25)), ivec3(1)));
    bool glowing = any(greaterThan(texture(BloomSampler, texCoord).rgb, vec3(0.0)));
    if (nexusEnabled && !glowing) {
        fragColor = texture(NexusSampler, texCoord);
    } else {
        fragColor = texture(DiffuseSampler, texCoord);
    }
}
