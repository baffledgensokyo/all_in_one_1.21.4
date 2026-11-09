#ifndef LBC_ATLAS_GLITCH_SIGNAL_GLSL
#define LBC_ATLAS_GLITCH_SIGNAL_GLSL

// The independent lbc:atlas_glitch clock drives a visual-only timeline.
// Disabled multiplier is white. Enabled colors have two signature channels
// and one byte of payload. Also recognize the client's one-tick interpolation
// to/from vanilla's #999999 Night Vision, so it never flashes the carrier tint.
const vec3 LBC_ATLAS_GLITCH_NIGHT_VISION = vec3(153.0 / 255.0);
bool lbc_atlas_glitch_signal(vec3 carrier, out int code) {
    code = 0;
    carrier /= LBC_ATLAS_GLITCH_NIGHT_VISION;
    float strength = (1.0 - carrier.r) / (1.0 - 32.0 / 255.0);
    if (strength <= 0.0001 || strength > 1.0001) return false;
    float expectedGreen = mix(1.0, 96.0 / 255.0, strength);
    if (abs(carrier.g - expectedGreen) > 0.00001) return false;
    float payload = (carrier.b - (1.0 - strength)) / strength;
    if (payload < -0.001 || payload > 1.001) return false;
    code = clamp(int(round(payload * 255.0)), 0, 255);
    return true;
}

float lbc_atlas_glitch_alpha(ivec2 pixel, int code, float original) {
    if (pixel.y != 0) return original;
    if (pixel.x < 3) return vec3(61, 103, 229)[pixel.x] / 255.0;
    if (pixel.x == 3) return float(code & 15) / 255.0;
    if (pixel.x == 4) return float(code >> 4) / 255.0;
    return original;
}

#endif
