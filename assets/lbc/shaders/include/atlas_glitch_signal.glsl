#ifndef LBC_ATLAS_GLITCH_SIGNAL_GLSL
#define LBC_ATLAS_GLITCH_SIGNAL_GLSL

// The independent lbc:atlas_glitch clock drives a visual-only timeline.
// Disabled multiplier is white. V2 uses two signature channels and a continuous
// blue ramp carrying a 23-bit seed. Also recognize the client's interpolation
// to/from vanilla's #999999 Night Vision, so it never flashes the carrier tint.
const vec3 LBC_ATLAS_GLITCH_NIGHT_VISION = vec3(153.0 / 255.0);
bool lbc_atlas_glitch_signal(vec3 carrier, out int code) {
    code = 0;
    carrier /= LBC_ATLAS_GLITCH_NIGHT_VISION;
    float strength = (1.0 - carrier.r) / (1.0 - 32.0 / 255.0);
    if (strength <= 0.0001 || strength > 1.0001) return false;
    // Full activation can round to 0.99999994 on a GPU. Subtracting its tiny
    // residual from a 23-bit payload would lose whole seed bits.
    if (abs(strength - 1.0) < 0.00001) strength = 1.0;
    float payload = (carrier.b - (1.0 - strength)) / strength;
    if (payload < -0.001 || payload > 1.001) return false;
    float expectedGreenV2 = mix(1.0, 160.0 / 255.0, strength);
    if (abs(carrier.g - expectedGreenV2) <= 0.00001) {
        code = clamp(int(round(payload * 8388608.0)), 0, 6483599);
        return true;
    }
    // Legacy servers/timelines remain usable at their original coarse precision.
    float expectedGreenV1 = mix(1.0, 96.0 / 255.0, strength);
    if (abs(carrier.g - expectedGreenV1) > 0.00001) return false;
    code = clamp(int(round(payload * 255.0)), 0, 255);
    return true;
}

float lbc_atlas_glitch_alpha(ivec2 pixel, int code, float original) {
    if (pixel.y != 0) return original;
    if (pixel.x < 3) return vec3(61, 103, 230)[pixel.x] / 255.0;
    if (pixel.x == 3) return float(code & 255) / 255.0;
    if (pixel.x == 4) return float((code >> 8) & 255) / 255.0;
    if (pixel.x == 5) return float((code >> 16) & 255) / 255.0;
    return original;
}

#endif
