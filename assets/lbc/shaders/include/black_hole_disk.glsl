#ifndef LBC_BLACK_HOLE_DISK
#define LBC_BLACK_HOLE_DISK

// Procedural material: periodic angular noise, differential orbital motion,
// radial filaments and absorbing lanes. No bitmap or noise atlas is required.
float bhDiskHash(vec2 p) {
    vec3 q = fract(vec3(p.xyx) * vec3(0.1031, 0.1030, 0.0973));
    q += dot(q, q.yzx + 33.33);
    return fract((q.x + q.y) * q.z);
}

float bhDiskNoise(vec2 p, float angularPeriod) {
    vec2 cell = floor(p);
    vec2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    float y0 = mod(cell.y, angularPeriod);
    float y1 = mod(cell.y + 1.0, angularPeriod);
    return mix(mix(bhDiskHash(vec2(cell.x, y0)), bhDiskHash(vec2(cell.x + 1.0, y0)), f.x),
               mix(bhDiskHash(vec2(cell.x, y1)), bhDiskHash(vec2(cell.x + 1.0, y1)), f.x), f.y);
}

float bhDiskDensity(float r, float angle, float seconds, float footprint) {
    float phase = angle - seconds * 1.2 * pow(3.0 / r, 1.5);
    float angular = phase / 6.28318530718;
    float cloud = bhDiskNoise(vec2(r * 1.8, angular * 12.0), 12.0);
    vec2 p = vec2(r * 8.0 + cloud * 0.9, angular * 32.0);
    float lowWeight = exp2(-footprint * footprint * 128.0);
    float highWeight = exp2(-footprint * footprint * 512.0);
    // Unresolved octaves contribute their mean. Avoid evaluating invisible
    // high-frequency noise when the disk is viewed edge-on or far away.
    float low = lowWeight > 0.0001 ? bhDiskNoise(p, 32.0) - 0.5 : 0.0;
    float high = highWeight > 0.0001 ? bhDiskNoise(p * 2.0 + vec2(17.0, 0.0), 64.0) - 0.5 : 0.0;
    float detail = 0.55 * low * lowWeight + 0.25 * high * highWeight;
    float filament = cos(r * 42.0 + cloud * 3.0) * exp2(-footprint * footprint * 1764.0);
    float spiral = 0.78 + 0.22 * sin(phase * 3.0 + r * 1.8);
    // Broad, sheared density variations break up the formerly uniform,
    // opaque bands; fine filaments do not become solid concentric rings.
    float clouds = mix(0.25, 1.3, smoothstep(0.22, 0.78, cloud));
    float dust = 1.0 - 0.55 * smoothstep(0.62, 0.86, cloud);
    return max(0.035, (0.72 + detail * 1.7 + filament * 0.09) * spiral * dust * clouds);
}

#endif
