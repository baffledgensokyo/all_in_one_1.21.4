#ifndef LBC_ZONE_WINDOW_GLSL
#define LBC_ZONE_WINDOW_GLSL

// Horizontal distance to this part of the wall, independent of camera pitch.
// A monotone quintic Hermite spline: (5,5), (20,20), (100,200).
// Value, slope AND curvature match at every join and both flat limits.
float lbc_zone_half_height(float horizontalDistance) {
    if (horizontalDistance <= 5.0) return 5.0;
    if (horizontalDistance >= 100.0) return 200.0;
    if (horizontalDistance < 20.0) {
        float t = (horizontalDistance - 5.0) / 15.0;
        return 5.0 + t * t * t * (39.0 + t * (-33.0 + 9.0 * t));
    }
    float t = (horizontalDistance - 20.0) / 80.0;
    return clamp(20.0 + t * (160.0 + t * (256.0 + t * (72.0 + t * (-652.0 + 344.0 * t)))),
                 5.0, 200.0);
}

// Camera-relative WORLD Y: the band follows viewer height, not camera pitch.
float lbc_zone_window(vec3 relativePosition) {
    float halfHeight = lbc_zone_half_height(length(relativePosition.xz));
    float fadeWidth = max(1.0, halfHeight * 0.1);
    float t = clamp((abs(relativePosition.y) - halfHeight + fadeWidth) / fadeWidth, 0.0, 1.0);
    return 1.0 - t * t * t * (10.0 + t * (-15.0 + 6.0 * t));
}

#endif
