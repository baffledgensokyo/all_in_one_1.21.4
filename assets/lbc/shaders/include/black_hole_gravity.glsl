#ifndef LBC_BLACK_HOLE_GRAVITY
#define LBC_BLACK_HOLE_GRAVITY

float bhHorizonSegment(vec3 start, vec3 end) {
    vec3 direction = end - start;
    float dd = dot(direction, direction);
    float first = 2.0;
    for (int i = 0; i < LBC_BH_TRACE_COUNT && (holeMask >> uint(i)) != 0u; i++) {
        if ((holeMask & (1u << uint(i))) == 0u) continue;
        vec3 p = start - holeObjects[i].xyz;
        float b = dot(p, direction);
        float c = dot(p, p) - holeObjects[i].w * holeObjects[i].w;
        if (c < 0.0) return 0.0;
        float discriminant = b * b - dd * c;
        if (discriminant < 0.0 || b >= 0.0 || dd < 1e-12) continue;
        float t = (-b - sqrt(discriminant)) / dd;
        if (t >= 0.0 && t <= 1.0) first = min(first, t);
    }
    return first;
}

vec3 bhNormal(int slot) {
    uint bits = holeStyles[slot / 4][slot % 4];
    vec3 normal = vec3(float(bits & 1023u), float((bits >> 10u) & 1023u),
                       float((bits >> 20u) & 1023u)) / 1023.0 * 2.0 - 1.0;
    return normalize(normal);
}

bool bhDisk(int slot) {
    return (holeStyles[slot / 4][slot % 4] & (1u << 30u)) != 0u;
}

float bhErf(float x) {
    // Smooth Gaussian column integral: disk opacity must not jump whenever
    // the midplane happens to cross a ray-march step boundary.
    float a = abs(x);
    float t = 1.0 / (1.0 + 0.3275911 * a);
    float value = 1.0 - (((((1.061405429 * t - 1.453152027) * t) + 1.421413741) * t -
                           0.284496736) * t + 0.254829592) * t * exp(-a * a);
    return x < 0.0 ? -value : value;
}

float bhEntry(vec3 origin, vec3 direction) {
    float nearest = 1e30;
    for (int i = 0; i < LBC_BH_TRACE_COUNT && (holeMask >> uint(i)) != 0u; i++) {
        if ((holeMask & (1u << uint(i))) == 0u) continue;
        vec3 offset = origin - holeObjects[i].xyz;
        float radius = holeObjects[i].w * BH_REACH;
        float middle = -dot(offset, direction);
        vec3 closest = offset + direction * middle;
        float remainder = radius * radius - dot(closest, closest);
        if (remainder < 0.0) continue;
        float halfDistance = sqrt(remainder);
        if (middle + halfDistance <= 0.0) continue;
        nearest = min(nearest, max(middle - halfDistance, 0.0) + holeObjects[i].w * 0.0005);
    }
    return nearest;
}

vec3 bhField(vec3 position, vec3 velocity, out float stepSize, out bool captured,
             out bool nearHorizon) {
    vec3 acceleration = vec3(0.0);
    float strongestField2 = 0.0;
    stepSize = 1e30;
    captured = false;
    nearHorizon = false;
    for (int i = 0; i < LBC_BH_TRACE_COUNT && (holeMask >> uint(i)) != 0u; i++) {
        if ((holeMask & (1u << uint(i))) == 0u) continue;
        float radius = holeObjects[i].w;
        vec3 p = (position - holeObjects[i].xyz) / radius;
        float r2 = dot(p, p);
        float r = sqrt(r2);
        // Exact horizon clipping is only needed near a horizon.
        nearHorizon = nearHorizon || r < 1.5;
        captured = captured || r < 1.0;
        if (r >= BH_REACH || r < 0.5) continue;
        // Spatial null-ray equation in Schwarzschild units (event horizon=1).
        // Central force preserves angular momentum for an isolated hole.
        vec3 momentum = cross(p, velocity);
        float angularMomentum2 = dot(momentum, momentum);
        float taper = 1.0 - smoothstep(10.0, BH_REACH, r);
        vec3 field = -1.5 * angularMomentum2 * p * taper /
                     (radius * max(r2 * r2 * r, 0.001));
        acceleration += field;
        strongestField2 = max(strongestField2, dot(field, field));
        stepSize = min(stepSize, radius * r * mix(0.045, 0.16, smoothstep(1.5, 5.0, r)) /
                                max(length(velocity), 0.25));
    }
    // Art-directed overlap: retain the combined direction, but never bend
    // light more strongly than the strongest individual field at this point.
    // Coincident holes then keep one hole's shadow instead of adding mass.
    // The magnitude cap is continuous and independent of transport slot order.
    float combinedField2 = dot(acceleration, acceleration);
    if (combinedField2 > strongestField2)
        acceleration *= sqrt(strongestField2 / combinedField2);
    return acceleration;
}

void bhAccretion(int slot, vec3 start, vec3 end, vec3 direction,
                 float pixelAngle, inout vec3 emission, inout float transmission) {
    vec4 object = holeObjects[slot];
    vec3 a = (start - object.xyz) / object.w;
    vec3 b = (end - object.xyz) / object.w;
    // Reject most steps before unpacking the disk normal or evaluating noise.
    if (min(dot(a, a), dot(b, b)) > 81.0) return;
    vec3 normal = bhNormal(slot);
    float ha = dot(a, normal);
    float hb = dot(b, normal);
    bool crossing = (ha <= 0.0 && hb > 0.0) || (ha >= 0.0 && hb < 0.0);
    float normalVelocity = abs(dot(normal, direction));
    // Resolve a thin surface at its exact crossing, as in the Noita mod.
    // A narrow volume is needed only for the nearly coplanar, edge-on view.
    if (!crossing && normalVelocity > 0.08) return;
    float t = abs(ha - hb) > 1e-8 ? clamp(ha / (ha - hb), 0.0, 1.0) : 0.5;
    vec3 p = mix(a, b, t);
    float height = dot(p, normal);
    vec3 radial = p - normal * height;
    float r = length(radial);
    if (r < 2.8 || r > 8.2) return;
    float edge = smoothstep(2.8, 3.15, r) * (1.0 - smoothstep(6.8, 8.2, r));
    float thickness = r * 0.013;
    if (!crossing && min(abs(ha), abs(hb)) > thickness * 4.0) return;
    float deltaHeight = hb - ha;
    float path;
    if (crossing && normalVelocity > 0.08) {
        path = 1.0 / normalVelocity;
    } else if (abs(deltaHeight) > thickness * 0.001) {
        path = 0.5 * (bhErf(hb / (1.41421356 * thickness)) -
                      bhErf(ha / (1.41421356 * thickness))) * length(b - a) / deltaHeight;
    } else {
        float midpoint = (ha + hb) * 0.5 / thickness;
        path = exp(-0.5 * midpoint * midpoint) * length(b - a) / (2.50662827 * thickness);
    }
    path = max(path, 0.0);
    // The nearly coplanar view used to evaluate all noise octaves even for
    // zero-density steps many scale heights away from the emitting layer.
    if (edge * path < 0.00001) return;
    vec3 tangent = normalize(cross(normal, radial));
    vec3 reference = normalize(cross(abs(normal.y) < 0.9 ? vec3(0, 1, 0) : vec3(1, 0, 0), normal));
    float angle = atan(dot(radial, cross(normal, reference)), dot(radial, reference));
    float seconds = GameTime * 1200.0;
    // Project the pixel cone onto the disk plane: radial stretching is 1/cos,
    // not 1/sqrt(cos). At grazing incidence unresolved radial filaments must
    // converge to their average instead of becoming concentric dotted bands.
    float incidence = max(abs(dot(normal, direction)), 0.025);
    float footprint = pixelAngle * length(start) / object.w / incidence;
    float density = bhDiskDensity(r, angle, seconds, footprint);
    float opticalDepth = edge * path * density * 0.9;
    float opacity = 1.0 - exp(-opticalDepth);
    float temperature = pow(3.0 / max(r, 3.0), 0.8);
    float approach = -dot(tangent, direction) / sqrt(r);
    float heat = clamp(pow(3.0 / r, 0.65) + approach * 0.12, 0.0, 1.0);
    vec3 color = mix(vec3(1.0, 0.12, 0.008), vec3(1.0, 0.97, 0.88), heat * heat);
    float doppler = pow(clamp(1.0 + approach * 0.65, 0.6, 1.5), 3.0);
    float redshift = sqrt(max(1.0 - 1.0 / r, 0.0));
    emission += transmission * color * opacity * (4.0 * temperature * doppler * redshift);
    transmission *= 1.0 - opacity;
    // Low-energy scattering around the bright surface, without the former
    // thick orange fog bar across the horizon.
    float haloThickness = r * 0.04;
    float corona = exp2(-height * height / (haloThickness * haloThickness));
    emission += transmission * vec3(1.0, 0.42, 0.12) * corona * edge * length(b - a) * 0.0015;
}

#endif
