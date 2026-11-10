#ifndef LBC_BLOOM_BLUR
#define LBC_BLOOM_BLUR

vec3 lbc_bloom_to_white(vec3 color) {
    float brightness = dot(color, vec3(0.2126, 0.7152, 0.0722));
    return mix(color, vec3(1.0), smoothstep(0.5, 1.0, brightness));
}

vec3 lbc_bloom_blur(sampler2D source, vec2 coord, vec2 dir) {
    // The original radius-10 kernel, normalized by its total weight 2.470269.
    // Each linear sample combines two adjacent taps with the same weights.
    // Inputs MUST use bilinear filtering; scene/data samplers stay nearest.
    const vec2 pairs[5] = vec2[](
        vec2(1.4615384980, 0.1706784160),
        vec2(3.3846153360, 0.1280088120),
        vec2(5.5,          0.0984683045),
        vec2(7.5,          0.0437636549),
        vec2(9.5,          0.0131289345)
    );
    vec2 stepUV = dir / ScreenSize;
    vec3 blurred = texture(source, coord).rgb * 0.0919037562;
    for (int i = 0; i < 5; i++) {
        vec2 offset = stepUV * pairs[i].x;
        blurred += (texture(source, coord - offset).rgb +
                    texture(source, coord + offset).rgb) * pairs[i].y;
    }
    return lbc_bloom_to_white(blurred);
}

#endif
