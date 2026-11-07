#version 330
#extension GL_ARB_separate_shader_objects : require
uniform sampler2D SceneSampler;
uniform sampler2D StateSampler;
layout(location=0) out vec4 fragColor;
float readState(int x) {
    uvec4 b=uvec4(round(texelFetch(StateSampler,ivec2(x,0),0)*255.0));
    return uintBitsToFloat(b.x|(b.y<<8u)|(b.z<<16u)|(b.w<<24u));
}
void main() {
    vec4 scene=texelFetch(SceneSampler,ivec2(gl_FragCoord.xy),0);
    float amount=clamp(readState(3),0.0,1.0);
    fragColor=vec4(mix(scene.rgb,vec3(1.0)-scene.rgb,amount),scene.a);
}
