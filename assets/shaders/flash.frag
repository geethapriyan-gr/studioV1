precision highp float;
uniform sampler2D u_texture;
uniform float u_progress;
uniform vec2 u_resolution;
varying vec2 v_texCoord;

void main() {
    vec4 color = texture2D(u_texture, v_texCoord);
    
    float flashIntensity = sin(u_progress * 3.14159 * 4.0) * 0.5 + 0.5;
    flashIntensity = pow(flashIntensity, 3.0);
    
    vec3 flashColor = vec3(1.0, 0.9, 0.7);
    vec3 finalColor = mix(color.rgb, flashColor, flashIntensity * u_progress * 0.5);
    
    gl_FragColor = vec4(finalColor, color.a);
}
