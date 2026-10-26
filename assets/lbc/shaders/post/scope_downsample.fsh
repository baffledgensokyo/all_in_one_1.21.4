#version 330
#extension GL_ARB_separate_shader_objects : require
uniform sampler2D InSampler;
layout(std140) uniform SamplerInfo {
    vec2 OutSize;
    vec2 InSize;
};
layout(location=0) in vec2 texCoord;
layout(location=0) out vec4 fragColor;
void main() {
    vec3 sum=vec3(0.0);
    // Prefilter the entire input-pixel footprint before reducing resolution.
    for(int y=0;y<4;y++)for(int x=0;x<4;x++) {
        vec2 offset=(vec2(x,y)+0.5)/4.0-0.5;
        vec2 uv=clamp(texCoord+offset/OutSize,0.5/InSize,1.0-0.5/InSize);
        sum+=texture(InSampler,uv).rgb;
    }
    fragColor=vec4(sum/16.0,1.0);
}
