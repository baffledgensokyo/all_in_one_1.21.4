#version 330
#extension GL_ARB_separate_shader_objects : require

uniform sampler2D InSampler;
layout(std140) uniform SamplerInfo {
    vec2 OutSize;
    vec2 InSize;
};
layout(std140) uniform BlurConfig {
    vec2 BlurDir;
    float Radius;
};
layout(location=0) in vec2 texCoord;
layout(location=0) out vec4 fragColor;

void main() {
    vec2 delta=BlurDir*Radius/InSize;
    vec3 sum=vec3(0.0);
    float total=0.0;
    for(int i=-12;i<=12;i++) {
        float weight=exp(-float(i*i)/32.0);
        vec2 uv=clamp(texCoord+delta*float(i),0.5/InSize,1.0-0.5/InSize);
        sum+=texture(InSampler,uv).rgb*weight;
        total+=weight;
    }
    fragColor=vec4(sum/total,1.0);
}
