precision highp float;
uniform sampler2D u_texture;
uniform float u_progress;
uniform vec2 u_resolution;
varying vec2 v_texCoord;

float random(vec2 st) {
    return fract(sin(dot(st.xy, vec2(12.9898,78.233))) * 43758.5453123);
}

void main() {
    float glitchIntensity = u_progress * 0.1;
    
    vec2 offset = vec2(
        sin(u_progress * 10.0) * glitchIntensity,
        cos(u_progress * 15.0) * glitchIntensity
    );
    
    vec4 color = texture2D(u_texture, v_texCoord + offset);
    
    float r = texture2D(u_texture, v_texCoord + vec2(glitchIntensity * 0.1, 0.0)).r;
    float g = texture2D(u_texture, v_texCoord).g;
    float b = texture2D(u_texture, v_texCoord - vec2(glitchIntensity * 0.1, 0.0)).b;
    
    if (random(v_texCoord + u_progress * 10.0) < u_progress * 0.1) {
        color = vec4(r, g, b, 1.0);
    }
    
    gl_FragColor = color;
}
