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
    // Rounded vector seven-segment digits: smooth coverage at any framebuffer size.
    const uint glyphs[10]=uint[](63u,6u,91u,79u,102u,109u,125u,7u,127u,111u);
    const vec2 start[7]=vec2[](vec2(0,6),vec2(4,6),vec2(4,3),vec2(0,0),
                               vec2(0,0),vec2(0,3),vec2(0,3));
    const vec2 end[7]=vec2[](vec2(4,6),vec2(4,3),vec2(4,0),vec2(4,0),
                             vec2(0,3),vec2(0,6),vec2(4,3));
    float ink=0.0;
    for(int i=0;i<7;i++)if((glyphs[digit]&(1u<<uint(i)))!=0u)
        ink=max(ink,scopeLine(p,start[i]*scale,end[i]*scale,max(1.6,0.8*scale)));
    return ink;
}
float scopeNumber(vec2 p,int value,float scale) {
    float advance=value>=10?6.0:0.0;
    float ink=value>=10?scopeDigit(p,value/10,scale):0.0;
    ink=max(ink,scopeDigit(p-vec2(advance*scale,0.0),value%10,scale));
    float degree=scopeStroke(length(p-vec2(advance+6.8,5.2)*scale)-0.8*scale,max(1.3,scale*0.65));
    return max(ink,degree);
}
void scopeLabel(inout vec3 color,vec2 p,int value,float scale,vec3 ink,float opacity) {
    scopePaint(color,ink,scopeNumber(p,value,scale),opacity);
}
