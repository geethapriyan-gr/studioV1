precision highp float;
uniform sampler2D u_texture;
uniform float u_progress;
uniform vec2 u_resolution;
varying vec2 v_texCoord;

float random(vec2 st) {
    return fract(sin(dot(st.xy, vec2(12.9898,78.233))) * 43758.5453123);
}

void main() {
    float blurAmount = u_progress * 0.05;
    vec4 color = vec4(0.0);
    float total = 0.0;
    
    for (float x = -3.0; x <= 3.0; x++) {
        for (float y = -3.0; y <= 3.0; y++) {
            float weight = exp(-(x*x + y*y) / (2.0 * 2.0));
            vec2 offset = vec2(x * blurAmount, y * blurAmount);
            color += texture2D(u_texture, v_texCoord + offset) * weight;
            total += weight;
        }
    }
    
    gl_FragColor = color / total;
}
