#ifndef LBC_ZONE_WINDOW_GLSL
#define LBC_ZONE_WINDOW_GLSL

// Horizontal distance to this part of the wall, independent of camera pitch.
// Near the viewer the half-height follows distance; beyond 20 blocks it grows
// gradually faster: distance 5 -> +/-5, 20 -> +/-20, 100 -> +/-400.
// Both joins have continuous value and first derivative.
float lbc_zone_half_height(float horizontalDistance) {
    float nearDistance = max(horizontalDistance - 5.0, 0.0);
    float farDistance = max(horizontalDistance - 20.0, 0.0);
    return 5.0 + nearDistance * smoothstep(0.0, 1.0, nearDistance) +
           (3.0 / 64.0) * farDistance * farDistance;
}

// Camera-relative WORLD Y: the band follows viewer height, not camera pitch.
float lbc_zone_window(vec3 relativePosition) {
    float halfHeight = lbc_zone_half_height(length(relativePosition.xz));
    float fadeWidth = max(1.0, halfHeight * 0.1);
    return 1.0 - smoothstep(halfHeight - fadeWidth, halfHeight, abs(relativePosition.y));
}

#endif
