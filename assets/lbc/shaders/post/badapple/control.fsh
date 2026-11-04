#version 330
#extension GL_ARB_separate_shader_objects : require
uniform sampler2D InSampler;
layout(std140) uniform BadAppleControl { float Code; };
layout(location=0) out vec4 fragColor;
void main() {
    ivec2 pixel=ivec2(gl_FragCoord.xy);
    fragColor=all(equal(pixel,ivec2(0)))?vec4(61.0,186.0,Code,255.0)/255.0:texelFetch(InSampler,pixel,0);
}
