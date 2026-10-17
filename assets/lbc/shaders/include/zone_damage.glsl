#ifndef LBC_ZONE_DAMAGE_GLSL
#define LBC_ZONE_DAMAGE_GLSL

float lbc_zone_damage_hash(int key) {
    uint bits = uint(key) * 747796405u + 2891336453u;
    bits = ((bits >> ((bits >> 28u) + 4u)) ^ bits) * 277803737u;
    bits = (bits >> 22u) ^ bits;
    return float(bits & 16777215u) / 16777216.0;
}

// Starts are 1.25*k + jitter[-0.25,0.25]: flashes are 0.75..1.75 seconds
// apart. Wrap the seed with the 1200-second GameTime period for a seamless day.
float lbc_zone_damage_start(int index) {
    int seed = (index % 960 + 960) % 960;
    return float(index) * 1.25 + lbc_zone_damage_hash(seed + 173) * 0.5 - 0.25;
}

vec3 lbc_zone_damage_event(float seconds) {
    int base = int(floor(seconds / 1.25));
    int selected = base - 1;
    float start = lbc_zone_damage_start(selected);
    for (int offset = 0; offset <= 1; offset++) {
        int candidate = base + offset;
        float candidateStart = lbc_zone_damage_start(candidate);
        if (candidateStart <= seconds && candidateStart > start) {
            selected = candidate;
            start = candidateStart;
        }
    }
    float age = seconds - start;
    float flash = smoothstep(0.0, 0.018, age) * (1.0 - smoothstep(0.06, 0.20, age));
    flash += 0.42 * smoothstep(0.19, 0.205, age) * (1.0 - smoothstep(0.23, 0.34, age));
    return vec3(flash, float((selected % 960 + 960) % 960), age);
}

float lbc_zone_damage_segment(vec2 p, vec2 a, vec2 b) {
    vec2 delta = b - a;
    float t = clamp(dot(p - a, delta) / max(dot(delta, delta), 1e-8), 0.0, 1.0);
    return length(p - a - delta * t);
}

vec2 lbc_zone_damage_node(int index, int seed, float start, float span) {
    float t = float(index) / 10.0;
    float jitter = lbc_zone_damage_hash(seed + index * 31);
    return vec2(start + span * t, 0.025 + jitter * 0.065 + sin(t * 3.14159265) * 0.025);
}

float lbc_zone_damage_bolt(vec2 uv, float aspect, int seed) {
    int side = int(lbc_zone_damage_hash(seed) * 4.0);
    vec2 q = uv * vec2(aspect, 1.0);
    vec2 p;
    float edgeLength;
    if (side < 2) {
        p = vec2(q.y, side == 0 ? q.x : aspect - q.x);
        edgeLength = 1.0;
    } else {
        p = vec2(q.x, side == 2 ? q.y : 1.0 - q.y);
        edgeLength = aspect;
    }
    float span = min(0.28 + lbc_zone_damage_hash(seed + 7) * 0.28, edgeLength * 0.65);
    float start = 0.06 + lbc_zone_damage_hash(seed + 13) * max(edgeLength - span - 0.12, 0.0);
    float distance = 10.0;
    vec2 a = lbc_zone_damage_node(0, seed, start, span);
    for (int index = 1; index <= 10; index++) {
        vec2 b = lbc_zone_damage_node(index, seed, start, span);
        distance = min(distance, lbc_zone_damage_segment(p, a, b));
        a = b;
    }
    // A short fork reaching inward makes this read as a lightning scar.
    a = lbc_zone_damage_node(5, seed, start, span);
    for (int index = 1; index <= 3; index++) {
        vec2 b = a + vec2((lbc_zone_damage_hash(seed + index * 53) - 0.5) * 0.07, 0.028);
        distance = min(distance, lbc_zone_damage_segment(p, a, b));
        a = b;
    }
    return distance;
}

vec3 lbc_zone_damage(vec3 scene, vec2 uv, float outsideDistance) {
    float outside = smoothstep(0.0, 1.25, outsideDistance);
    if (outside <= 0.0) return scene;
    float aspect = ScreenSize.x / max(ScreenSize.y, 1.0);
    vec2 edge = min(uv, 1.0 - uv) * vec2(aspect, 1.0);
    float edgeDistance = min(edge.x, edge.y);
    float rim = 1.0 - smoothstep(0.0, 0.19, edgeDistance);
    if (rim <= 0.0) return scene;
    float seconds = GameTime * 1200.0;
    float breathing = 0.96 + 0.04 * sin(seconds * 1.3);
    vec3 color = mix(scene, vec3(0.34, 0.002, 0.016), outside * rim * rim * 0.52 * breathing);
    color += vec3(0.065, 0.0, 0.004) * outside * rim * rim * rim;
    vec3 event = lbc_zone_damage_event(seconds);
    if (event.x <= 0.001) return color;
    int seed = int(event.y) * 997;
    float distance = min(lbc_zone_damage_bolt(uv, aspect, seed + 19),
                         lbc_zone_damage_bolt(uv, aspect, seed + 311));
    float pixel = 1.0 / max(ScreenSize.y, 1.0);
    float core = 1.0 - smoothstep(0.0007, 0.0007 + pixel * 1.5, distance);
    float glow = exp2(-distance * 150.0);
    float flash = outside * event.x * rim;
    color += vec3(0.85, 0.018, 0.045) * glow * flash * 0.65;
    return mix(color, vec3(1.0, 0.20, 0.24), core * flash * 0.94);
}

#endif
