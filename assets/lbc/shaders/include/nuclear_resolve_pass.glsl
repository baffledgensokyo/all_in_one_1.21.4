#include <minecraft:globals.glsl>
#include <lbc:nuclear_inputs.glsl>
#include <lbc:nuclear_volume.glsl>
#include <lbc:nuclear_trace.glsl>
uniform sampler2D SceneSampler;
uniform sampler2D SceneDepthSampler;
uniform sampler2D VolumeSampler;
layout(location = 0) out vec4 fragColor;
void main() {
    vec4 scene=texture(SceneSampler,texCoord);
    fragColor=scene;
    if(nuclearCount==0)return;
    // Bilateral reconstruction at full resolution: never interpolate smoke
    // through a nearer wall/hand silhouette. The scene itself stays sharp.
    vec2 grid=gl_FragCoord.xy*0.5-0.5;
    ivec2 base=ivec2(floor(grid));
    vec2 f=fract(grid);
    ivec2 maximum=ivec2(ceil(ScreenSize*0.5))-1;
    float currentRange=nuclearDepthDistance(SceneDepthSampler,texCoord);
    // A depth edge BEHIND the entire plume must not punch a rectangular
    // hole in foreground smoke. Use bilateral rejection only where either
    // surface could actually intersect/occlude a volume's support box.
    vec2 ndc=texCoord*2.0-1.0;
    vec3 a=nuclearUnproject(ndc,0.25),b=nuclearUnproject(ndc,0.75);
    bool first=dot(a,a)<dot(b,b);
    vec3 origin=first?a:b,direction=normalize(first?b-a:a-b);
    float farthestExit=0.0,fineDetail=0.0;
    for(int i=0;i<nuclearCount;i++) {
        NuclearObject object=nuclearGetObject(i);
        if(object.age>=70.0)continue;
        float radius=object.sphere.w*NUCLEAR_WORLD_SCALE;
        vec3 dim=nuclearDimensions(object.age);
        vec3 ro=object.rotation*(origin-object.sphere.xyz)/radius;
        vec3 rd=object.rotation*direction/radius;
        vec2 interval=nuclearInterval(ro,rd,dim,object.age);
        if(interval.y>max(interval.x,0.0))farthestExit=max(farthestExit,interval.y+length(origin));
        // Thin, ash-filled stems cannot survive a half-resolution bilinear
        // enlargement. Refine only their small screen footprint, using the
        // SAME integrator and depth clipping on both sides of the horizon.
        vec2 stem=nuclearBox(ro,rd,vec3(-0.25,-0.12,-0.25),
                            vec3(0.25,max(dim.y-dim.z*0.35,0.2),0.25));
        stem.x=max(stem.x,0.0);
        stem.y=min(stem.y,max(currentRange-length(origin),0.0));
        if(stem.y>stem.x) {
            float closest=clamp(-dot(ro.xz,rd.xz)/max(dot(rd.xz,rd.xz),1e-15),stem.x,stem.y);
            vec3 p=ro+rd*closest;
            float detail=(1.0-smoothstep(0.19,0.25,length(p.xz)))*
                         (1.0-smoothstep(dim.y-dim.z*0.65,dim.y-dim.z*0.35,p.y));
            fineDetail=max(fineDetail,detail);
        }
        // Preserve the sharp tongues in the compact base as well. This
        // covers only its small footprint; the cap/dust remain half-res.
        float baseRadius=nuclearBaseRadius(dim);
        vec2 foot=nuclearBox(ro,rd,vec3(-baseRadius-0.08,-0.15,-baseRadius-0.08),
                            vec3(baseRadius+0.08,0.95,baseRadius+0.08));
        foot.x=max(foot.x,0.0);
        foot.y=min(foot.y,max(currentRange-length(origin),0.0));
        if(foot.y>foot.x) {
            float closest=clamp(-dot(ro.xz,rd.xz)/max(dot(rd.xz,rd.xz),1e-15),foot.x,foot.y);
            vec3 p=ro+rd*closest;
            float detail=(1.0-smoothstep(baseRadius,baseRadius+0.08,length(p.xz)))*
                         (1.0-smoothstep(0.70,0.95,p.y));
            fineDetail=max(fineDetail,detail);
        }
    }
    vec4 volume=vec4(0.0);
    float total=0.0,bestDifference=1e30;
    vec4 fallback=vec4(0.0,0.0,0.0,1.0);
    for(int y=0;y<2;y++)for(int x=0;x<2;x++) {
        ivec2 cell=clamp(base+ivec2(x,y),ivec2(0),maximum);
        vec2 uv=min((vec2(cell)+0.5)*2.0/ScreenSize,1.0-0.5/ScreenSize);
        float sampleRange=nuclearDepthDistance(SceneDepthSampler,uv);
        float difference=abs(sampleRange-currentRange)/max(min(currentRange,sampleRange),1.0);
        if(currentRange>farthestExit+1.0&&sampleRange>farthestExit+1.0)difference=0.0;
        vec4 v=texelFetch(VolumeSampler,cell,0);
        if(difference<bestDifference){bestDifference=difference;fallback=v;}
        float weight=(x==0?1.0-f.x:f.x)*(y==0?1.0-f.y:f.y)*exp(-difference*150.0);
        volume+=v*weight;total+=weight;
    }
    volume=total>0.0001?volume/total:fallback;
    if(bestDifference>0.05)volume=vec4(0.0,0.0,0.0,1.0);
    if(fineDetail>0.001) {
        vec4 sharp=nuclearTrace(origin,direction,max(currentRange-length(origin),0.0),gl_FragCoord.xy);
        volume=mix(volume,sharp,fineDetail);
    }
    fragColor=vec4(volume.rgb+volume.a*scene.rgb,scene.a);
}
