#version 330
#extension GL_ARB_separate_shader_objects : require
uniform sampler2D SceneSampler;
uniform sampler2D HistorySampler;
uniform sampler2D StateSampler;
layout(location=0) out vec4 fragColor;
float readState(int x) {
    uvec4 b=uvec4(round(texelFetch(StateSampler,ivec2(x,0),0)*255.0));
    return uintBitsToFloat(b.x|(b.y<<8u)|(b.z<<16u)|(b.w<<24u));
}
void main() {
    ivec2 pixel=ivec2(gl_FragCoord.xy);
    // Consume the private control pixel; never leak marker color into the image/history.
    ivec2 source=all(equal(pixel,ivec2(0)))?ivec2(min(1,textureSize(SceneSampler,0).x-1),0):pixel;
    vec4 scene=texelFetch(SceneSampler,source,0);
    float elapsed=readState(0),dt=readState(6);
    bool prior=readState(7)>0.5;
    // Remaining-time weighting reaches the moving scene at precisely 0.5 seconds.
    // Temporal history deliberately trades a brief motion trail for a real lightmap transition.
    float amount=elapsed>=0.5||dt<0.0||!prior?1.0:clamp(dt/max(0.5-elapsed+dt,0.001),0.0,1.0);
    fragColor=vec4(mix(texelFetch(HistorySampler,pixel,0).rgb,scene.rgb,amount),scene.a);
}
