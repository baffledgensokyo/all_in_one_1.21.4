#version 330
#extension GL_ARB_separate_shader_objects : require
#include <lbc:scope_ui.glsl>

// Overlay only. FOV is controlled by the server, not by these shaders.
uniform sampler2D InSampler;
uniform sampler2D AnimationSampler;
uniform sampler2D BlurSampler;
layout(std140) uniform SamplerInfo {
    vec2 OutSize;
    vec2 InSize;
    vec2 AnimationSize;
    vec2 BlurSize;
};
layout(std140) uniform ZoomConfig {
    float Direction;
    float Duration;
    float Style;       // 0: SLG, 1: Magnum
    float VerticalFov; // Actual vertical world FOV in degrees, for recoil marks.
};
layout(location=0) out vec4 fragColor;

float readElapsed() {
    uvec4 b=uvec4(round(texelFetch(AnimationSampler,ivec2(0,0),0)*255.0));
    return uintBitsToFloat(b.x|(b.y<<8u)|(b.z<<16u)|(b.w<<24u));
}

void main() {
    vec4 original=texelFetch(InSampler,ivec2(gl_FragCoord.xy),0);
    float t=clamp(readElapsed()/max(Duration,0.001),0.0,1.0);
    float eased=1.0-pow(1.0-t,3.0);
    float amount=Direction>0.0?eased:1.0-eased;
    if(amount<=0.0){fragColor=original;return;}

    float unit=min(OutSize.x,OutSize.y);
    float s=max(unit/720.0,0.5);
    vec2 p=gl_FragCoord.xy-OutSize*0.5;
    bool magnum=Style>0.5;
    float halfSize=mix(max(OutSize.x,OutSize.y)+unit,
                       unit*(magnum?0.455:0.365),amount);
    float edge=magnum?(abs(p.x)+abs(p.y)-halfSize)*0.70710678:
                       scopeBox(p,vec2(halfSize));
    float outside=smoothstep(-3.0*s,3.0*s,edge);
    vec3 blurred=texture(BlurSampler,gl_FragCoord.xy/OutSize).rgb;
    vec3 color=mix(original.rgb,blurred,outside*amount);
    float inner=1.0-smoothstep(-1.0*s,0.0,edge);

    vec3 metal=magnum?vec3(30,41,71)/255.0:vec3(44,45,56)/255.0;
    vec3 accent=magnum?vec3(94,193,199)/255.0:vec3(159,76,72)/255.0;
    vec3 pale=magnum?vec3(180,212,225)/255.0:vec3(222,231,237)/255.0;
    // A narrow mechanical rim, with a bright inner bevel; the exterior stays visible.
    scopePaint(color,metal,scopeStroke(edge,12.0*s),amount);
    scopePaint(color,pale,scopeStroke(edge+4.0*s,1.3*s)*0.65,amount);
    scopePaint(color,accent,scopeStroke(edge-5.0*s,2.0*s),amount);

    vec2 pixel=floor(gl_FragCoord.xy);
    vec2 lineStart=floor(OutSize*0.5)-1.0;
    bool vertical=pixel.x>=lineStart.x&&pixel.x<lineStart.x+2.0;
    bool horizontal=pixel.y>=lineStart.y&&pixel.y<lineStart.y+2.0;
    if(!magnum) {
        // SLG: long etched cross, crimson acquisition brackets and steel corner caps.
        float cross=float(vertical||horizontal)*inner;
        scopePaint(color,vec3(0.025),cross,amount*0.85);
        float brackets=scopeStroke(scopeBox(p,vec2(16.0*s)),2.0*s);
        brackets*=float(min(abs(p.x),abs(p.y))>7.0*s);
        scopePaint(color,accent,brackets,amount);
        vec2 a=abs(p);
        float corner=scopeStroke(edge,8.0*s)*float(min(a.x,a.y)>halfSize-34.0*s);
        scopePaint(color,accent,corner,amount);
        float rail=scopeLine(p,vec2(-halfSize+20.0*s,-55.0*s),
                              vec2(-halfSize+20.0*s,55.0*s),2.0*s);
        scopePaint(color,pale,rail,amount*0.7);
        for(int i=-3;i<=3;i++) {
            float tick=scopeLine(p,vec2(-halfSize+20.0*s,float(i)*16.0*s),
                                  vec2(-halfSize+29.0*s,float(i)*16.0*s),2.0*s);
            scopePaint(color,accent,tick,amount);
        }
    } else {
        // Magnum: interrupted cyan cross and angular lock-on diamond.
        float arms=float((vertical&&abs(p.y)>10.0*s&&abs(p.y)<30.0*s)||
                         (horizontal&&abs(p.x)>10.0*s&&abs(p.x)<36.0*s));
        scopePaint(color,metal,scopeStroke(length(p)-4.0*s,3.0*s),amount);
        scopePaint(color,pale,scopeStroke(length(p)-3.0*s,1.0*s),amount);
        scopePaint(color,accent,arms,amount);
        float lock=scopeStroke((abs(p.x)+abs(p.y)-19.0*s)*0.70710678,1.5*s);
        scopePaint(color,accent,lock,amount*0.9);
        for(int i=0;i<3;i++) {
            int degrees=(i+1)*5;
            float y=OutSize.y*0.5*tan(radians(float(degrees)))/
                    tan(radians(clamp(VerticalFov,1.0,175.0))*0.5);
            vec3 mark=i==0?vec3(186,115,245)/255.0:
                      i==1?vec3(94,193,199)/255.0:vec3(192,197,205)/255.0;
            // True angular coordinates. If outside the aperture, show a separate
            // edge warning with an upward arrow, never a false on-screen tick.
            bool offscreen=y>halfSize-80.0*s;
            vec2 q=p-vec2(0.0,y);
            if(offscreen) {
                q=p-vec2(halfSize*0.55,-halfSize*0.18-float(i)*23.0*s);
                float arrow=max(scopeLine(q,vec2(-5,-1)*s,vec2(0,4)*s,1.5*s),
                                scopeLine(q,vec2(0,4)*s,vec2(5,-1)*s,1.5*s));
                scopePaint(color,mark,arrow,amount);
                float plate=1.0-smoothstep(-0.5,0.5,
                    scopeBox(q-vec2(19.5,0)*s,vec2(11,6)*s));
                scopePaint(color,metal,plate,amount*0.9);
                float label=scopeNumber(q-vec2(11.0,-4.0)*s,degrees,1.5*s);
                scopePaint(color,mark,label,amount);
                if(i==1) {
                    scopePaint(color,vec3(248,221,114)/255.0,
                        scopeLine(q,vec2(11,-8)*s,vec2(15,-8)*s,2.0*s),amount);
                    scopePaint(color,vec3(91,188,244)/255.0,
                        scopeLine(q,vec2(17,-8)*s,vec2(21,-8)*s,2.0*s),amount);
                    scopePaint(color,vec3(106,178,91)/255.0,
                        scopeLine(q,vec2(23,-8)*s,vec2(27,-8)*s,2.0*s),amount);
                }
                continue;
            }
            float tick=scopeLine(q,vec2(-22.0*s,0),vec2(22.0*s,0),2.0);
            float outline=scopeLine(q,vec2(-23.0*s,0),vec2(23.0*s,0),4.0);
            scopePaint(color,metal,outline,amount);
            if(i==1) {
                mark=q.x< -7.0*s?vec3(248,221,114)/255.0:
                     q.x<7.0*s?vec3(91,188,244)/255.0:vec3(106,178,91)/255.0;
            }
            scopePaint(color,mark,tick,amount);
            float plate=1.0-smoothstep(-0.5,0.5,
                scopeBox(q-vec2(37.5,0)*s,vec2(11,6)*s));
            scopePaint(color,metal,plate,amount*0.9);
            float label=scopeNumber(q-vec2(29.0,-4.0)*s,degrees,1.5*s);
            scopePaint(color,i==1?accent:mark,label,amount);
        }
        // Short illuminated divisions on the lower diagonal edges.
        for(int i=1;i<=4;i++) {
            float d=float(i)*13.0*s;
            vec2 q=vec2(abs(p.x),p.y);
            float tick=scopeLine(q,vec2(halfSize*0.5-d,-halfSize*0.5-d),
                                  vec2(halfSize*0.5-d+5.0*s,-halfSize*0.5-d+5.0*s),2.0*s);
            scopePaint(color,accent,tick,amount*0.7);
        }
    }
    fragColor=vec4(color,original.a);
}
