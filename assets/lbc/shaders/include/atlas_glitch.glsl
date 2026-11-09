#ifndef LBC_ATLAS_GLITCH_GLSL
#define LBC_ATLAS_GLITCH_GLSL

// Private lightmap ALPHA protocol. RGB remains vanilla lighting.
// Code 0 is disabled; codes 1..256 encode a shared 16x16 atlas offset.
float lbc_atlas_glitch_code(sampler2D lightmap) {
    if (any(lessThan(textureSize(lightmap, 0), ivec2(5, 1)))) return 0.0;
    ivec3 header = ivec3(round(vec3(
        texelFetch(lightmap, ivec2(0, 0), 0).a,
        texelFetch(lightmap, ivec2(1, 0), 0).a,
        texelFetch(lightmap, ivec2(2, 0), 0).a) * 255.0));
    if (any(notEqual(header, ivec3(61, 103, 229)))) return 0.0;
    ivec2 cell = ivec2(round(vec2(texelFetch(lightmap, ivec2(3, 0), 0).a,
                                 texelFetch(lightmap, ivec2(4, 0), 0).a) * 255.0));
    if (any(greaterThan(cell, ivec2(15)))) return 0.0;
    return float(1 + cell.x + 16 * cell.y);
}

vec2 lbc_atlas_glitch_offset(float code) {
    int cell = clamp(int(round(code)) - 1, 0, 255);
    return vec2(cell & 15, cell >> 4) / 16.0;
}

#ifdef LBC_ATLAS_GLITCH_FRAGMENT
vec3 lbc_atlas_glitch_rgb(sampler2D atlas, vec2 uv, float code) {
    // Wrap per fragment, never per vertex: triangles crossing the atlas edge
    // must not interpolate through the entire atlas. Keep the original LOD.
    return textureGrad(atlas, fract(uv + lbc_atlas_glitch_offset(code)),
                       dFdx(uv), dFdy(uv)).rgb;
}
#endif

#endif
