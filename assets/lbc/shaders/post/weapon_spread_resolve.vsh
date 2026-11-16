#version 330
#extension GL_ARB_separate_shader_objects : require
#include <lbc:reticle_header.glsl>
uniform sampler2D SceneSampler;
layout(location=0) flat out vec4 reticleBounds;
layout(location=1) flat out vec2 reticleStyle;
layout(location=2) flat out vec2 reticleCenter;
layout(location=3) flat out vec4 nativeRect;
int byteAt(int n,int row,ivec2 size) {
    return int(round(texelFetch(SceneSampler,ivec2(size.x-20-n,row),0).a*255.0));
}
bool header(int row,ivec2 size) {
    for(int i=0;i<4;i++)if(byteAt(i,row,size)!=LBC_RETICLE_MAGIC[i])return false;
    return true;
}
bool nativePixel(ivec2 p,ivec2 size) {
    return all(greaterThanEqual(p,ivec2(0))) && all(lessThan(p,size)) &&
        int(round(texelFetch(SceneSampler,p,0).a*255.0))==251;
}
void main() {
    vec2 uv=vec2((gl_VertexIndex<<1)&2,gl_VertexIndex&2);
    gl_Position=vec4(uv*2.0-1.0,0,1);
    reticleBounds=vec4(0);reticleStyle=vec2(0);nativeRect=vec4(0);
    ivec2 size=textureSize(SceneSampler,0);
    reticleCenter=vec2(size)*.5;
    if(size.x<48 || size.y<2)return;
    int row=header(0,size)?0:size.y-1;
    if(!header(row,size))return;
    float fields[6];
    for(int i=0;i<6;i++) {
        uint bits=0u;
        for(int b=0;b<4;b++)bits|=uint(byteAt(4+i*4+b,row,size))<<uint(b*8);
        fields[i]=uintBitsToFloat(bits);
        if(isnan(fields[i]) || isinf(fields[i]) || fields[i]<0)return;
    }
    if(fields[4]<=0 || fields[4]>64 || fields[5]>256)return;
    // GameRenderer applies post effects BEFORE GuiRenderer.render. Decode the
    // current weapon header without looking for a future GUI crosshair pixel.
    reticleBounds=vec4(fields[0],fields[1],fields[2],fields[3]);
    reticleStyle=vec2(fields[4],fields[5]);
}
