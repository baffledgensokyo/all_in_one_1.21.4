#version 330
#extension GL_ARB_separate_shader_objects : require
#include <minecraft:globals.glsl>
#include <lbc:nuclear_data.glsl>

uniform sampler2D CurrentSampler;
uniform sampler2D HistorySampler;
layout(location = 0) out vec4 fragColor;

// Tiny persistent object records, never previous world RGB. Durations are
// seconds and are independent of FPS, particle age and display scale.
const float BH_FADE_SECONDS=0.20;
const float NUCLEAR_FADE_OUT=4.0;
const float BH_SPAWN_BACK=1.70158; // About 10% overshoot, then settle.
const ivec2 EFFECT_SIZE=ivec2(171,LBC_EFFECT_ROWS);

vec4 packBits(uint bits) {
    return vec4(float(bits&255u),float((bits>>8u)&255u),
                float((bits>>16u)&255u),float(bits>>24u))/255.0;
}
uint readBits(ivec2 pixel) {
    uvec4 b=uvec4(round(texelFetch(HistorySampler,pixel,0)*255.0));
    return b.x|(b.y<<8u)|(b.z<<16u)|(b.w<<24u);
}
float oldFloat(ivec2 pixel) { return uintBitsToFloat(readBits(pixel)); }
ivec3 rawBytes(int x,int row) {
    return ivec3(round(vec3(texelFetch(CurrentSampler,ivec2(x*3,row),0).a,
                           texelFetch(CurrentSampler,ivec2(x*3+1,row),0).a,
                           texelFetch(CurrentSampler,ivec2(x*3+2,row),0).a)*255.0));
}
bool header(ivec3 b,int row) {
    return row<18 ? b.r==66&&b.g==72&&(b.b==100||b.b==101) : all(equal(b,ivec3(78,85,75)));
}
int currentRow(int row) {
    ivec2 size=textureSize(CurrentSampler,0);
    if(size.x<171||size.y<LBC_EFFECT_ROWS)return -1;
    for(int copy=0;copy<2;copy++) {
        int y=copy==0?row:size.y-1-row;
        if(!header(rawBytes(56,y),row))continue;
        bool valid=true;
        for(int field=0;field<28;field++)
            valid=valid&&rawBytes(field*2,y).b==201&&rawBytes(field*2+1,y).b==202;
        if(valid)return y;
    }
    return -1;
}
int cameraRow() {
    for(int row=2;row<LBC_NUCLEAR_FIRST_ROW+LBC_NUCLEAR_COUNT;row++) {
        int y=currentRow(row);
        if(y>=0)return y;
    }
    ivec2 size=textureSize(CurrentSampler,0);
    if(size.x>=171&&size.y>=LBC_EFFECT_ROWS)for(int copy=0;copy<2;copy++) {
        int row=copy==0?1:size.y-2;
        if(all(equal(rawBytes(56,row),ivec3(67,65,77)))) {
            bool valid=true;
            for(int field=12;field<28;field++)
                valid=valid&&rawBytes(field*2,row).b==201&&rawBytes(field*2+1,row).b==202;
            if(valid)return row;
        }
    }
    return -1;
}
float pointField(int field,int row,bool current) {
    ivec3 a=current?rawBytes(field*2,row):ivec3(round(texelFetch(HistorySampler,ivec2(field*2,row),0).rgb*255.0));
    ivec3 b=current?rawBytes(field*2+1,row):ivec3(round(texelFetch(HistorySampler,ivec2(field*2+1,row),0).rgb*255.0));
    return uintBitsToFloat(uint(a.r)|(uint(a.g)<<8u)|(uint(b.r)<<16u)|(uint(b.g)<<24u));
}
vec3 point(int index,int row,bool current) {
    return vec3(pointField(index*3,row,current),pointField(index*3+1,row,current),pointField(index*3+2,row,current));
}
vec4 encodedField(float value,int x) {
    uint bits=floatBitsToUint(value);
    uint shift=(x%2==0)?0u:16u;
    return vec4(float((bits>>shift)&255u),float((bits>>(shift+8u))&255u),x%2==0?201.0:202.0,255.0)/255.0;
}
float holeArrival(float phase) {
    float t=phase-1.0;
    return 1.0+(BH_SPAWN_BACK+1.0)*t*t*t+BH_SPAWN_BACK*t*t;
}
void main() {
    ivec2 pixel=ivec2(gl_FragCoord.xy);
    int x=pixel.x,row=min(pixel.y,EFFECT_SIZE.y-1-pixel.y);
    fragColor=vec4(0.0);
    bool history=all(equal(ivec4(round(texelFetch(HistorySampler,ivec2(7,1),0)*255.0)),ivec4(76,73,70,69)));
    float now=GameTime*1200.0;
    float dt=history?mod(now-oldFloat(ivec2(6,1))+1200.0,1200.0):0.0;
    ivec3 oldBlock=ivec3(int(readBits(ivec2(0,1))),int(readBits(ivec2(1,1))),int(readBits(ivec2(2,1))));
    vec3 offset=vec3(oldFloat(ivec2(3,1)),oldFloat(ivec2(4,1)),oldFloat(ivec2(5,1)));
    vec3 delta=vec3(oldBlock-CameraBlockPos)+offset-CameraOffset;
    history=history&&dt<=2.0&&length(delta)<256.0;
    if(!history)dt=0.0;

    if(row==1) {
        if(x<3)fragColor=packBits(uint(CameraBlockPos[x]));
        else if(x<6)fragColor=packBits(floatBitsToUint(CameraOffset[x-3]));
        else if(x==6)fragColor=packBits(floatBitsToUint(now));
        else if(x==7)fragColor=vec4(76,73,70,69)/255.0;
        return;
    }
    if(row==0) {
        if(x>=24&&x<56) {
            int live=cameraRow();
            fragColor=live>=0?vec4(vec3(rawBytes(x,live))/255.0,1.0):
                                 (history?texelFetch(HistorySampler,ivec2(x,0),0):vec4(0.0));
        }
        return;
    }
    int live=currentRow(row);
    bool wasAlive=history&&header(ivec3(round(texelFetch(HistorySampler,ivec2(56,row),0).rgb*255.0)),row);
    float progress=wasAlive?oldFloat(ivec2(57,row)):0.0;
    if(isnan(progress)||isinf(progress))progress=0.0;
    progress=clamp(progress,0.0,1.0);
    float previousProgress=progress;
    if(live>=0&&wasAlive) {
        vec3 oldCenter=point(0,row,false)+delta;
        float radius=length(point(1,live,true)-point(0,live,true));
        bool replaced=any(notEqual(rawBytes(56,live),ivec3(round(texelFetch(HistorySampler,ivec2(56,row),0).rgb*255.0))))||
                      distance(oldCenter,point(0,live,true))>max(radius*4.0,8.0);
        if(replaced){progress=0.0;wasAlive=false;}
    }
    bool nuclear=row>=18;
    if(live>=0)progress=nuclear?1.0:min(progress+(wasAlive?dt/BH_FADE_SECONDS:0.0),1.0);
    else {
        // A removal during arrival still gets its complete exit duration,
        // beginning at the actual displayed radius (including overshoot).
        if(wasAlive&&oldFloat(ivec2(59,row))>0.5){progress=1.0;previousProgress=1.0;}
        progress=max(progress-dt/(nuclear?NUCLEAR_FADE_OUT:BH_FADE_SECONDS),0.0);
    }
    if(x==57) {fragColor=packBits(floatBitsToUint(progress));return;}
    if(x==59) {fragColor=packBits(floatBitsToUint(live>=0?1.0:0.0));return;}
    if(nuclear&&x>=60&&x<=75&&(live>=0||wasAlive&&progress>0.0)) {
        // Prepare exact float object data once per frame for the 5..16 path.
        // The fragment stage fetches only its current object; no huge arrays
        // of matrices need to cross the vertex/fragment interface.
        int source=live>=0?live:row;
        bool current=live>=0;
        vec3 origin=point(0,source,current);
        vec3 axisX=point(1,source,current)-origin;
        vec3 axisY=point(2,source,current)-origin;
        vec3 axisZ=point(3,source,current)-origin;
        float radius=length(axisX),value=0.0;
        if(x<63)value=(origin+(current?vec3(0.0):delta))[x-60];
        else if(x==63)value=radius;
        else if(x<73) {
            mat3 rotation=transpose(mat3(normalize(axisX),normalize(axisY),normalize(axisZ)));
            value=rotation[(x-64)/3][(x-64)%3];
        } else if(x==73)value=clamp(length(axisY)-1.0,0.0,120.0);
        else if(x==74) {
            float visibility=clamp(2.0-length(axisZ)/max(radius,0.0001),0.0,1.0);
            value=round(smoothstep(0.0,1.0,progress)*visibility*255.0)/255.0;
        } else value=float(row-LBC_NUCLEAR_FIRST_ROW)*13.71;
        fragColor=packBits(floatBitsToUint(value));return;
    }
    if(x>58||(live<0&&(!wasAlive||progress<=0.0)))return;
    if(x==56||x==58) {
        // Optional server-controlled fade while the display is still alive:
        // Z/X=1 means fully visible (existing commands), Z/X=2 means hidden.
        // Keeping the live carrier until zero also supplies fresh camera data.
        int source=live>=0?live:row;
        vec3 origin=point(0,source,live>=0);
        float ratio=length(point(3,source,live>=0)-origin)/max(length(point(1,source,live>=0)-origin),0.0001);
        float visibility=clamp(2.0-ratio,0.0,1.0);
        float fade=smoothstep(0.0,1.0,progress);
        if(x==58) {
            // Store radius in a float: RGBA8 alpha cannot carry overshoot >1.
            // If removed during the bounce, contract from the actual last size.
            float size=live>=0?holeArrival(progress)*visibility:
                oldFloat(ivec2(58,row))*fade/max(smoothstep(0.0,1.0,previousProgress),1e-6);
            fragColor=packBits(floatBitsToUint(nuclear?fade*visibility:max(size,0.0)));
        } else {
            vec3 bytes=live>=0?vec3(rawBytes(x,live))/255.0:texelFetch(HistorySampler,ivec2(x,row),0).rgb;
            fragColor=vec4(bytes,fade*visibility);
        }
    } else if(live>=0)fragColor=vec4(vec3(rawBytes(x,live))/255.0,1.0);
    else if(x<24) {
        int index=x/6,axis=(x/2)%3;
        vec3 p=point(index,row,false)+delta;
        // Retain the last mushroom stage during its four-second tail;
        // GameTime still animates flow, but age 70 cannot cut the tail short.
        fragColor=encodedField(p[axis],x);
    } else {
        int camera=cameraRow();
        fragColor=camera>=0?vec4(vec3(rawBytes(x,camera))/255.0,1.0):texelFetch(HistorySampler,ivec2(x,0),0);
    }
}
