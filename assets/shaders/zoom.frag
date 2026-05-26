precision highp float;
uniform sampler2D u_texture1;
uniform sampler2D u_texture2;
uniform float u_progress;
varying vec2 v_texCoord;

void main() {
    vec2 center = vec2(0.5, 0.5);
    vec2 texCoord = center + (v_texCoord - center) * (1.0 - u_progress * 0.5);
    
    vec4 color1 = texture2D(u_texture1, v_texCoord);
    vec4 color2 = texture2D(u_texture2, texCoord);
    
    gl_FragColor = mix(color1, color2, u_progress);
}
