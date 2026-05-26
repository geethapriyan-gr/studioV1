precision highp float;
uniform sampler2D u_texture;
uniform float u_progress;
uniform vec2 u_resolution;
varying vec2 v_texCoord;

float random(vec2 st) {
    return fract(sin(dot(st.xy, vec2(12.9898,78.233))) * 43758.5453123);
}

void main() {
    float shakeIntensity = u_progress * 0.05;
    float time = u_progress * 10.0;
    float offsetX = sin(time * 10.0) * shakeIntensity;
    float offsetY = cos(time * 15.0) * shakeIntensity;
    
    vec2 offset = vec2(offsetX, offsetY);
    vec4 color = texture2D(u_texture, v_texCoord + offset);
    
    gl_FragColor = color;
}
