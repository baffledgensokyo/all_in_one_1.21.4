// Pixel-space scope primitives. No textures or resampling of the lens image.
float scopeLine(vec2 p, vec2 a, vec2 b, float width) {
    vec2 d = b-a;
    float t = clamp(dot(p-a,d)/max(dot(d,d),0.0001),0.0,1.0);
    return 1.0-smoothstep(width*0.5-0.5,width*0.5+0.5,length(p-a-d*t));
}
float scopeBox(vec2 p, vec2 halfSize) {
    vec2 q = abs(p)-halfSize;
    return length(max(q,0.0))+min(max(q.x,q.y),0.0);
}
float scopeStroke(float distanceToEdge, float width) {
    return 1.0-smoothstep(width*0.5-0.5,width*0.5+0.5,abs(distanceToEdge));
}
void scopePaint(inout vec3 color, vec3 ink, float coverage, float opacity) {
    color=mix(color,ink,clamp(coverage*opacity,0.0,1.0));
}
float scopeDigit(vec2 p,int digit,float scale) {
    // 3x5 bitmaps, left to right and top to bottom.
    const uint glyphs[10]=uint[](31599u,11415u,29671u,29647u,23497u,31183u,31215u,29257u,31727u,31695u);
    ivec2 c=ivec2(floor(p/scale));
    if(c.x<0||c.x>=3||c.y<0||c.y>=5)return 0.0;
    return float((glyphs[digit]>>uint((4-c.y)*3+2-c.x))&1u);
}
float scopeNumber(vec2 p,int value,float scale) {
    float ink=scopeDigit(p,value/10,scale);
    ink=max(ink,scopeDigit(p-vec2(4.0*scale,0.0),value%10,scale));
    float degree=scopeStroke(length(p-vec2(9.0,4.0)*scale)-scale,scale*0.7);
    return max(ink,degree);
}
