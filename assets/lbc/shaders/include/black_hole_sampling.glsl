#ifndef LBC_BLACK_HOLE_SAMPLING
#define LBC_BLACK_HOLE_SAMPLING

// Continuously increase the lens-map spacing near a horizon. Colour is
// fetched from the original full-resolution frame after UV reconstruction.
float lbc_bh_stride(vec4 peripheral) {
    return mix(2.0, 4.0, clamp(peripheral.w,0.0,1.0));
}

float lbc_bh_far_stride() {
    return 2.0;
}

vec2 lbc_bh_decode_uv(vec4 value) {
    uvec4 bytes = uvec4(round(value * 255.0));
    uint bits = bytes.r | (bytes.g << 8u) | (bytes.b << 16u) | ((bytes.a & 15u) << 24u);
    return vec2(bits & 16383u, (bits >> 14u) & 16383u) / 16383.0;
}

vec3 lbc_bh_sharp_color(sampler2D scene, sampler2D depth, vec2 uv, mat4 inverseVP) {
    ivec2 size = textureSize(depth,0);
    ivec2 pixel = clamp(ivec2(uv * vec2(size)),ivec2(0),size-1);
    float reference = texelFetch(depth,pixel,0).r;
    float r = reference;
    #ifndef RENDERPEARL_DEPTH_IS_ZERO_TO_ONE
    r = r * 2.0 - 1.0;
    #endif
    float distance = abs(1.0 / (inverseVP[2][3] * r + inverseVP[3][3]));
    ivec2 base = ivec2(floor(uv * vec2(size) - 0.5));
    for (int y=0;y<2;y++) for (int x=0;x<2;x++) {
        float d = texelFetch(depth,clamp(base+ivec2(x,y),ivec2(0),size-1),0).r;
        if (d <= 1e-7 || d >= 0.9999999) return texelFetch(scene,pixel,0).rgb;
        #ifndef RENDERPEARL_DEPTH_IS_ZERO_TO_ONE
        d = d * 2.0 - 1.0;
        #endif
        float other = abs(1.0 / (inverseVP[2][3] * d + inverseVP[3][3]));
        if (abs(other-distance) > max(0.005,distance*0.01)) return texelFetch(scene,pixel,0).rgb;
    }
    return textureLod(scene,uv, 0.0).rgb;
}

vec4 lbc_bh_coarse_color(sampler2D scene, sampler2D depth, mat4 inverseVP, vec4 value) {
    if (value.a < 239.5 / 255.0) return value;
    return vec4(lbc_bh_sharp_color(scene,depth,lbc_bh_decode_uv(value),inverseVP), 1.0);
}

float lbc_bh_reconstruct_grid(sampler2D scene, sampler2D depth, sampler2D coarse,
                         vec2 position, vec2 size, mat4 inverseVP, float stride,
                         out vec4 reconstructed) {
    reconstructed = vec4(0.0);
    vec2 grid = position / stride - 0.5;
    ivec2 base = ivec2(floor(grid));
    ivec2 last = ivec2(ceil(size / stride)) - 1;
    vec2 f = fract(grid);
    vec4 a = texelFetch(coarse, clamp(base, ivec2(0), last), 0);
    vec4 b = texelFetch(coarse, clamp(base + ivec2(1,0), ivec2(0), last), 0);
    vec4 c = texelFetch(coarse, clamp(base + ivec2(0,1), ivec2(0), last), 0);
    vec4 d = texelFetch(coarse, clamp(base + ivec2(1,1), ivec2(0), last), 0);
    bool smoothPatch = false;
    bool allWarp = min(min(a.a,b.a),min(c.a,d.a)) > 239.5 / 255.0;
    if (allWarp) {
        vec2 ua = lbc_bh_decode_uv(a), ub = lbc_bh_decode_uv(b);
        vec2 uc = lbc_bh_decode_uv(c), ud = lbc_bh_decode_uv(d);
        vec2 span = max(max(ua,ub),max(uc,ud)) - min(min(ua,ub),min(uc,ud));
        // A depth jump between two neighbouring block faces does not imply
        // a jump in their lens UVs. Keep the continuous warp across that edge;
        // the source colour fetch below still rejects sky/glass filtering.
        smoothPatch = max(span.x,span.y) < max(0.04,2.0 * stride / min(size.x,size.y));
        if (smoothPatch) {
            vec2 uv = mix(mix(ua,ub,f.x),mix(uc,ud,f.x),f.y);
            // Interpolation can cross a disocclusion in the source frame even
            // when all four traced rays hit solid faces. Never sample its sky
            // as a transparent seam between those known surfaces.
            ivec2 sourceSize = textureSize(depth,0);
            float observed = texelFetch(depth,clamp(ivec2(uv * vec2(sourceSize)),ivec2(0),sourceSize-1),0).r;
            if (observed <= 1e-7 || observed >= 0.9999999)
                uv = f.y < 0.5 ? (f.x < 0.5 ? ua : ub) : (f.x < 0.5 ? uc : ud);
            // Fetch original full-resolution colour, not enlarged low-res RGB.
            reconstructed = vec4(lbc_bh_sharp_color(scene,depth,uv,inverseVP), 1.0);
        }
    } else if (max(max(a.a,b.a),max(c.a,d.a)) < 0.1) {
        reconstructed = vec4(textureLod(scene, position / size, 0.0).rgb,0.0);
        smoothPatch = true;
    } else {
        smoothPatch = max(max(abs(a.a-b.a),abs(a.a-c.a)),abs(a.a-d.a)) < 0.01;
        if (smoothPatch) reconstructed = mix(mix(a,b,f.x),mix(c,d,f.x),f.y);
    }
    if (smoothPatch) return 1.0;
    // Never interpolate RGB or UVs between sky, a solid face and capture.
    // Pick one traced layer; mixing those categories made opaque block edges
    // appear translucent. Compressed repeats intentionally use nearest UVs.
    ivec2 nearest = clamp(ivec2(floor(position / stride)),ivec2(0),last);
    vec4 selected = texelFetch(coarse,nearest,0);
    reconstructed = selected.a < 0.1
        ? vec4(textureLod(scene,position / size,0.0).rgb,0.0)
        : lbc_bh_coarse_color(scene,depth,inverseVP,selected);
    return 1.0;
}

float lbc_bh_reconstruct(sampler2D scene, sampler2D depth, sampler2D coarse,
                         vec2 position, vec2 size, mat4 inverseVP, vec4 peripheral,
                         out vec4 reconstructed) {
    reconstructed = vec4(0.0);
    if (peripheral.w <= 0.0) return 0.0;
    return lbc_bh_reconstruct_grid(scene,depth,coarse,position,size,inverseVP,
                                  lbc_bh_stride(peripheral),reconstructed);
}

#endif
