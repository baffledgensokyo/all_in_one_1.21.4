#version 330
#extension GL_ARB_separate_shader_objects : require
#include <minecraft:globals.glsl>
uniform sampler2D SceneSampler;
uniform sampler2D HistorySampler;
layout(location=0) out vec4 fragColor;
float readState(int x) {
    uvec4 b=uvec4(round(texelFetch(HistorySampler,ivec2(x,0),0)*255.0));
    return uintBitsToFloat(b.x|(b.y<<8u)|(b.z<<16u)|(b.w<<24u));
}
vec4 packFloat(float value) {
    uint b=floatBitsToUint(value);
    return vec4(float(b&255u),float((b>>8u)&255u),float((b>>16u)&255u),float((b>>24u)&255u))/255.0;
}
void main() {
    bool valid=all(equal(ivec4(round(texelFetch(HistorySampler,ivec2(5,0),0)*255.0)),ivec4(66,65,70,50)));
    ivec4 control=ivec4(round(texelFetch(SceneSampler,ivec2(0),0)*255.0));
    float code=control.r==61&&control.g==186?float(control.b):0.0;
    bool paused=code>=4.0;float target=paused?code-4.0:code;
    float now=GameTime*1200.0,dt=valid?now-readState(1):0.0;
    if(dt<0.0)dt+=1200.0;dt=clamp(dt,0.0,0.1);
    float elapsed=valid?readState(0):0.0;
    float from=valid?readState(4):0.0;
    bool changed=!valid||target!=readState(2);
    if(changed){elapsed=0.0;from=valid?readState(3):0.0;}
    else if(!paused)elapsed=min(0.5,elapsed+dt);
    float inversion=mix(from,target==2.0?1.0:0.0,smoothstep(0.0,0.5,elapsed));
    int x=int(gl_FragCoord.x);
    if(x==5){fragColor=vec4(66,65,70,50)/255.0;return;}
    float value=x==0?elapsed:x==1?now:x==2?target:x==3?inversion:x==4?from:x==6?(paused?-1.0:dt):(valid?1.0:0.0);
    fragColor=packFloat(value);
}
