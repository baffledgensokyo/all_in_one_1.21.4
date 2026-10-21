#ifndef LBC_NUCLEAR_VOLUME_GLSL
#define LBC_NUCLEAR_VOLUME_GLSL

// One local unit = display X/Z scale * NUCLEAR_WORLD_SCALE blocks.
// No textures or per-frame allocations.
const float NUCLEAR_WORLD_SCALE = 3.0;
float nuclearHash(vec3 p) {
    p = fract(p * 0.3183099 + vec3(0.17, 0.31, 0.53));
    p *= 17.0;
    return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float nuclearNoise(vec3 p) {
    vec3 i = floor(p), f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    return mix(mix(mix(nuclearHash(i), nuclearHash(i + vec3(1,0,0)), f.x),
                   mix(nuclearHash(i + vec3(0,1,0)), nuclearHash(i + vec3(1,1,0)), f.x), f.y),
               mix(mix(nuclearHash(i + vec3(0,0,1)), nuclearHash(i + vec3(1,0,1)), f.x),
                   mix(nuclearHash(i + vec3(0,1,1)), nuclearHash(i + vec3(1,1,1)), f.x), f.y), f.z);
}

// Analytic derivative of value noise. Reuse the same eight corners for
// sculpted billow normals instead of six additional density evaluations.
vec4 nuclearNoiseGradient(vec3 p) {
    vec3 i = floor(p), f = fract(p);
    vec3 u = f * f * (3.0 - 2.0 * f);
    vec3 du = 6.0 * f * (1.0 - f);
    float a = nuclearHash(i), b = nuclearHash(i + vec3(1,0,0));
    float c = nuclearHash(i + vec3(0,1,0)), d = nuclearHash(i + vec3(1,1,0));
    float e = nuclearHash(i + vec3(0,0,1)), g = nuclearHash(i + vec3(1,0,1));
    float h = nuclearHash(i + vec3(0,1,1)), j = nuclearHash(i + vec3(1,1,1));
    float low = mix(mix(a,b,u.x), mix(c,d,u.x), u.y);
    float high = mix(mix(e,g,u.x), mix(h,j,u.x), u.y);
    vec3 gradient = du * vec3(
        mix(mix(b-a,d-c,u.y),mix(g-e,j-h,u.y),u.z),
        mix(mix(c-a,d-b,u.x),mix(h-e,j-g,u.x),u.z), high-low);
    return vec4(mix(low, high, u.z), gradient);
}

vec3 nuclearDimensions(float age) {
    float growth = 1.0 - exp(-age * 0.65);
    // exopersoexplodeparticles_2: cap Y=60, sigma X/Z=26, sigma Y=16.
    // At R=12 one local unit is 36 blocks. Use the two-sigma envelope;
    // Gaussian particles had no finite outer boundary.
    return mix(vec3(0.22,0.25,0.20),vec3(52.0,60.0,32.0)/36.0,growth);
}

float nuclearSmoothUnion(float a, float b, float radius) {
    float h = clamp(0.5 + 0.5 * (b-a) / radius, 0.0, 1.0);
    return mix(b,a,h) - radius * h * (1.0-h);
}

// Curl of three independent scalar potentials: no polar/atan coordinate map,
// no axis seam. The noise is a spatial velocity field, not a stack of quads.
vec3 nuclearCurl(vec3 p) {
    vec3 a = nuclearNoiseGradient(p).yzw;
    vec3 b = nuclearNoiseGradient(p + vec3(31.7,9.2,15.4)).yzw;
    vec3 c = nuclearNoiseGradient(p + vec3(7.8,41.3,3.6)).yzw;
    return vec3(c.y-b.z, a.z-c.x, b.x-a.y);
}

// Cheap support field for empty-space rejection and light attenuation.
vec2 nuclearColumnCenter(float height, float flow) {
    return vec2(sin(height*0.9-flow*0.8),sin(height*1.2-flow*0.7+1.4))*0.0025;
}

float nuclearColumnRadius(vec3 p, vec3 dim, float flow) {
    // Exactly one tenth of the previous radial profile, including its rolls.
    return (1.22 + 0.12*nuclearNoise(p*3.0-vec3(0.0,flow*2.0,0.0)) +
           0.40*pow(clamp(p.y/dim.y,0.0,1.0),3.0) + 0.18*exp(-p.y*p.y))*0.1;
}

float nuclearDustRadius(float age) { return min(80.0/36.0,0.35+age*0.24); }
float nuclearDustWidth(float age) { return min(0.65,0.30+age*0.0225); }

float nuclearBaseRadius(vec3 dim) {
    float growth=clamp((dim.y-0.25)/(60.0/36.0-0.25),0.0,1.0);
    // Standard R=12: strong inside 10 blocks, extinguished by 20 blocks.
    return mix(0.16,20.0/36.0,growth);
}

// The original had a broad lava/fire source at Y=-3/-5, not only dust.
// A compact circular fire bed curls upward into a low central funnel.
float nuclearBaseShape(vec3 p, vec3 dim) {
    float radial=length(p.xz);
    float radius=nuclearBaseRadius(dim);
    float rim=sqrt(max(1.0-pow(radial/radius,2.0),0.0));
    float height=(0.20+0.48*exp(-radial*2.3))*rim;
    return max((radial-radius)*4.0,abs(p.y+0.08)-height);
}

float nuclearSupport(vec3 p, vec3 dim, float flow) {
    float radial = length(p.xz);
    float cap = (length(vec2(radial/dim.x, (p.y-dim.y)/dim.z))-1.0)*dim.z;
    vec2 bend = nuclearColumnCenter(p.y,flow);
    float columnR = nuclearColumnRadius(p,dim,flow);
    // Rescale the stem SDF as well: otherwise old erosion would be wider
    // than the entire new stem and undo the tenfold narrowing.
    float column = max((length(p.xz-bend)-columnR)*10.0, max(-p.y,p.y-dim.y));
    float base=nuclearBaseShape(p,dim);
    return nuclearSmoothUnion(nuclearSmoothUnion(cap,column,0.12),base,0.14);
}

// Backtraced coherent flow: buoyant vertical jet below, Cartesian toroidal
// roll above, with a curl perturbation. Two overlapping advection windows
// reset stretched material coordinates without any temporal history buffer.
vec4 nuclearMedium(vec3 p, float age, float time, float seed) {
    vec3 dim = nuclearDimensions(age);
    float shape = nuclearSupport(p,dim,time);
    if (shape > 0.48 || age >= 70.0) return vec4(0.0);
    vec3 curl = nuclearCurl(p*1.45 + vec3(seed,time*0.63,0.0));
    float radial = sqrt(dot(p.xz,p.xz)+0.12);
    float capWeight = smoothstep(dim.y-dim.z*0.75,dim.y+dim.z*0.05,p.y);
    float vertical = p.y-dim.y;
    vec3 vortex = vec3(p.x*vertical/radial, -(radial-dim.x*0.58), p.z*vertical/radial)*2.3;
    vec3 velocity = mix(vec3(curl.x*0.08,3.4,curl.z*0.08),vortex,capWeight)+
                    curl*mix(vec3(0.06,0.35,0.06),vec3(0.42),capWeight);
    float baseWeight=1.0-smoothstep(0.18,0.65,p.y);
    // Negative radial velocity backtraces outward: material visibly travels
    // IN toward the foot from every azimuth, then accelerates up the stem.
    float baseRadial=length(p.xz);
    vec2 inward=-p.xz/max(baseRadial,0.08);
    vec3 intake=vec3(inward.x*1.8,0.40+2.8*exp(-baseRadial*3.0),inward.y*1.8);
    velocity=mix(velocity,intake+curl*vec3(0.16,0.28,0.16),baseWeight);
    float phase = fract(time*0.92 + seed*0.013);
    float second = fract(phase+0.5);
    float blend = 1.0-abs(phase*2.0-1.0);
    vec3 q0 = p-velocity*phase*0.9;
    vec3 q1 = p-velocity*second*0.9;
    vec4 b0 = nuclearNoiseGradient(q0*4.6+seed);
    vec4 b1 = nuclearNoiseGradient(q1*4.6+seed);
    vec4 billow = mix(b1,b0,blend);
    float detail0 = nuclearNoise(q0*12.7+seed+13.0);
    float detail1 = nuclearNoise(q1*12.7+seed+13.0);
    float fine = mix(detail1,detail0,blend);
    float erosion = (billow.x-0.48)*mix(0.28,0.58,capWeight) + (fine-0.5)*0.10;
    float density = (1.0-smoothstep(mix(-0.045,-0.10,capWeight),mix(0.025,0.045,capWeight),shape+erosion))*
                    (0.40+billow.x*1.7);
    // Keep the interior optically thick. Turbulence sculpts its outer rolls;
    // it must not carve transparent horizontal slits through the whole stem.
    float interior=1.0-smoothstep(-0.50,-0.12,shape);
    density=max(density,interior*1.4);
    float baseBody=1.0-smoothstep(-0.10,0.04,nuclearBaseShape(p,dim));
    density=max(density,baseBody*1.7);
    // A narrow, optically solid column carries the fast upward detail. Keep
    // edge billows turbulent without carving holes through the entire body.
    float columnRadius=nuclearColumnRadius(p,dim,time);
    float columnCore=(1.0-smoothstep(columnRadius*0.72,columnRadius*0.94,
                      length(p.xz-nuclearColumnCenter(p.y,time)))) *
                     smoothstep(-0.04,0.12,p.y) *
                     (1.0-smoothstep(dim.y-dim.z*0.7,dim.y,p.y));
    float columnMask=(1.0-smoothstep(columnRadius*0.80,columnRadius*1.3,
                      length(p.xz-nuclearColumnCenter(p.y,time)))) *
                     (1.0-smoothstep(dim.y-dim.z*0.75,dim.y-dim.z*0.10,p.y));
    // Advected, vertically elongated pockets make distinct flame tongues.
    // Keep the fade in their coverage, rather than washing out their color.
    float tongue=0.0;
    float baseInfluence=baseWeight*(1.0-capWeight)*(1.0-columnMask);
    if(baseInfluence>0.001) {
        vec3 frequency=vec3(23.0,7.0,23.0);
        float pockets=mix(nuclearNoise(q1*frequency+seed+41.0),
                          nuclearNoise(q0*frequency+seed+41.0),blend);
        tongue=smoothstep(0.43,0.60,pockets*0.78+fine*0.22);
        float edgeFade=1.0-smoothstep(nuclearBaseRadius(dim)*0.5,nuclearBaseRadius(dim),baseRadial);
        density*=mix(1.0,edgeFade*(0.10+tongue*1.55),baseInfluence);
    }
    // Preserve optical thickness after reducing the path length tenfold.
    density*=1.0+9.0*columnMask;
    density=max(density,columnCore*29.0);
    // Temperature follows moving material pockets, not a straight hot axis.
    float combustion = smoothstep(0.30,0.82,billow.x*0.72+fine*0.45);
    float underside = exp(-pow((p.y-dim.y+dim.z*0.65)/dim.z,2.0)*2.0);
    float heat = clamp(combustion*0.90 + underside*0.28 + exp(-max(p.y,0.0)*0.8)*0.14 -
                       age*0.012,0.0,1.0);
    heat *= 1.0-smoothstep(dim.y-dim.z*0.65,dim.y+dim.z*0.45,p.y)*0.35;
    heat=max(heat,columnCore*0.60*(1.0-smoothstep(20.0,48.0,age)));
    float baseCooling=1.0-smoothstep(18.0,48.0,age);
    heat=mix(heat,(0.30+tongue*0.53)*baseCooling,baseInfluence*baseBody);
    // Advected 3D ash embedded in the medium, not emitted particles or a
    // screen-space overlay. Full-resolution stem rays preserve these grains
    // equally against the sky and against terrain.
    if(columnMask>0.001) {
        vec3 ashPoint=p*vec3(110.0,75.0,110.0)-vec3(0.0,time*85.0,0.0)+seed;
        float ashNoise=nuclearNoise(ashPoint);
        float ash=smoothstep(0.52,0.76,ashNoise)*columnMask;
        heat*=1.0-ash*0.72;
        billow.x=mix(billow.x,0.18,ash*0.85);
    }
    // Beer-Lambert attenuation through an offset support sample + forward
    // scattering/powder term. This lights volume depth, not a fake surface.
    vec3 towardLight = normalize(vec3(-0.55,0.85,0.38));
    float shadowShape = nuclearSupport(p+towardLight*0.52,dim,time) +
                        (nuclearNoise((q0+towardLight*0.52)*4.6+seed)-0.48)*0.58;
    float occluder = (1.0-smoothstep(-0.22,0.15,shadowShape))*0.85;
    vec3 billowNormal=normalize(-billow.yzw+vec3(0.0,0.18,0.0));
    float lobelight=0.32+0.68*max(dot(billowNormal,towardLight),0.0);
    float lighting = 0.26+0.74*exp(-occluder*1.7)*lobelight;
    lighting *= 0.78+0.22*(1.0-exp(-density*2.0));
    return vec4(density*2.8,heat,billow.x,lighting);
}

vec3 nuclearFire(float heat) {
    return mix(mix(vec3(1.8,0.20,0.025),vec3(2.65,1.05,0.18),smoothstep(0.16,0.67,heat)),
               vec3(4.2,3.9,3.1),smoothstep(0.58,0.94,heat));
}

vec2 nuclearBox(vec3 ro, vec3 rd, vec3 lo, vec3 hi) {
    vec3 safe = mix(vec3(-1e-7),vec3(1e-7),greaterThanEqual(rd,vec3(0.0)));
    safe = mix(safe,rd,greaterThan(abs(rd),vec3(1e-7)));
    vec3 a=(lo-ro)/safe,b=(hi-ro)/safe;
    vec3 entry=min(a,b),leave=max(a,b);
    return vec2(max(max(entry.x,entry.y),entry.z),min(min(leave.x,leave.y),leave.z));
}
// Intersect the cap, stem and ground dust separately. Widening the cap
// must not lengthen rays below it into a huge mostly empty bounding box.
void nuclearMergeInterval(inout vec2 result, vec2 hit) {
    if (hit.y > max(hit.x, 0.0)) {
        result.x = min(result.x, hit.x);
        result.y = max(result.y, hit.y);
    }
}
vec2 nuclearInterval(vec3 ro, vec3 rd, vec3 dim, float age) {
    vec2 span=vec2(1e30,-1e30);
    // Erosion is measured in vertical SDF units. Its horizontal reach grows
    // with the cap's aspect ratio; a fixed margin clips a wide cap's billows.
    float capRadius=dim.x*(1.0+0.50/max(dim.z,0.1))+0.1;
    nuclearMergeInterval(span,nuclearBox(ro,rd,
        vec3(-capRadius,dim.y-dim.z-0.7,-capRadius),
        vec3(capRadius,dim.y+dim.z+0.7,capRadius)));
    nuclearMergeInterval(span,nuclearBox(ro,rd,vec3(-0.25,-0.2,-0.25),vec3(0.25,dim.y+0.5,0.25)));
    float baseRadius=nuclearBaseRadius(dim)+0.15;
    nuclearMergeInterval(span,nuclearBox(ro,rd,vec3(-baseRadius,-0.85,-baseRadius),
                                               vec3(baseRadius,1.15,baseRadius)));
    if(age<48.0) {
        float dustRadius=nuclearDustRadius(age)+2.75*nuclearDustWidth(age);
        nuclearMergeInterval(span,nuclearBox(ro,rd,vec3(-dustRadius,-1.2,-dustRadius),
                                           vec3(dustRadius,1.1,dustRadius)));
    }
    return span;
}
#endif
