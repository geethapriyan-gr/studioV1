// Aggressive Green Screen Removal Fragment Shader
// CapCut-level quality with complete green, shadow, and spill removal
#version 460 core

precision highp float;

uniform sampler2D u_texture;
uniform vec2 u_resolution;

// Chroma key parameters
uniform float u_hue_min;  // 0-360 degrees (target: 60-180)
uniform float u_hue_max;  // 0-360 degrees (target: 60-180)
uniform float u_saturation_min;  // 0-1 (target: 0.15)
uniform float u_similarity;  // 0-1 (tolerance adjustment)
uniform float u_shadow_removal;  // 0-1 (dark green detection strength)
uniform float u_spill_reduction;  // 0-1 (green tint removal)
uniform float u_edge_transition;  // 0-1 (edge transition width)
uniform float u_skin_protection;  // 0-1 (skin tone protection strength)

in vec2 v_uv;
out vec4 o_fragColor;

// RGB to HSV conversion
vec3 rgb2hsv(vec3 c) {
    vec4 K = vec4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
    vec4 p = mix(vec4(c.bg, K.wz), vec4(c.gb, K.xy), step(c.b, c.g));
    vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r));
    
    float d = q.x - min(q.w, q.y);
    float e = 1.0e-10;
    
    return vec3(
        abs(q.z + (q.w - q.y) / (6.0 * d + e)),
        d / (q.x + e),
        q.x
    );
}

// Calculate green dominance: G - max(R, B)
float calculateGreenDominance(vec3 rgb) {
    return rgb.g - max(rgb.r, rgb.b);
}

// Check if pixel is skin tone (0-50° or 300-360° hue)
bool isSkinTone(vec3 hsv) {
    float hueDeg = hsv.x * 360.0;
    return (hueDeg >= 0.0 && hueDeg <= 50.0) || (hueDeg >= 300.0 && hueDeg <= 360.0);
}

// Morphological erosion (1px)
float erode(sampler2D tex, vec2 uv, vec2 resolution, float threshold, float sampleStep) {
    float count = 0.0;
    float total = 0.0;
    
    for (float x = -1.0; x <= 1.0; x++) {
        for (float y = -1.0; y <= 1.0; y++) {
            if (x == 0.0 && y == 0.0) continue;
            vec2 offset = vec2(x * sampleStep, y * sampleStep);
            vec4 neighbor = texture(tex, uv + offset / resolution);
            float dominance = neighbor.g - max(neighbor.r, neighbor.b);
            count += (dominance > threshold) ? 1.0 : 0.0;
            total += 1.0;
        }
    }
    
    return count / total;
}

// Morphological dilation (1px)
float dilate(sampler2D tex, vec2 uv, vec2 resolution, float threshold, float sampleStep) {
    float count = 0.0;
    float total = 0.0;
    
    for (float x = -1.0; x <= 1.0; x++) {
        for (float y = -1.0; y <= 1.0; y++) {
            if (x == 0.0 && y == 0.0) continue;
            vec2 offset = vec2(x * sampleStep, y * sampleStep);
            vec4 neighbor = texture(tex, uv + offset / resolution);
            float dominance = neighbor.g - max(neighbor.r, neighbor.b);
            count += (dominance <= threshold) ? 1.0 : 0.0;
            total += 1.0;
        }
    }
    
    return count / total;
}

// Gaussian blur
float blur(sampler2D tex, vec2 uv, vec2 resolution, float radius) {
    float sum = 0.0;
    float weight = 0.0;
    
    for (float x = -2.0; x <= 2.0; x++) {
        for (float y = -2.0; y <= 2.0; y++) {
            vec2 offset = vec2(x * radius, y * radius);
            vec4 neighbor = texture(tex, uv + offset / resolution);
            float w = exp(-(x*x + y*y) * 0.5);
            sum += neighbor.a * w;
            weight += w;
        }
    }
    
    return sum / weight;
}

void main() {
    vec2 uv = gl_FragCoord.xy / u_resolution.xy;
    vec4 color = texture(u_texture, uv);
    
    // Convert to HSV
    vec3 hsv = rgb2hsv(color.rgb);
    
    // Calculate green dominance
    float greenDominance = calculateGreenDominance(color.rgb);
    
    // Base alpha calculation
    float alpha = 1.0;
    
    // Aggressive green classification - any of these conditions means background
    bool isBackground = false;
    
    // Condition A: HSV green
    bool conditionA = hsv.x >= u_hue_min / 360.0 && hsv.x <= u_hue_max / 360.0 && hsv.y > u_saturation_min;
    
    // Condition B: Green dominance
    bool conditionB = color.g > color.r * 1.15 && color.g > color.b * 1.15;
    
    // Condition C: Shadow green (G dominant + low brightness)
    bool conditionC = color.g >= color.r && color.g >= color.b && hsv.z < 0.40;
    
    isBackground = conditionA || conditionB || conditionC;
    
    // Force complete transparency for confirmed green pixels
    if (isBackground) {
        alpha = 0.0;
    }
    
    // Edge transition for hair and fine edges (narrow range)
    float edgeLow = 0.02;
    float edgeHigh = 0.08;
    
    if (alpha > 0.0 && greenDominance > edgeLow) {
        float transitionWidth = u_edge_transition * 0.06;
        alpha = smoothstep(edgeHigh + transitionWidth, edgeLow - transitionWidth * 0.5, greenDominance);
    }
    
    // Skin tone protection
    if (u_skin_protection > 0.0 && isSkinTone(hsv)) {
        alpha = mix(alpha, 1.0, u_skin_protection);
    }
    
    // Morphological operations for mask refinement
    float erosionResult = erode(u_texture, uv, u_resolution, 0.05, 1.0);
    float dilationResult = dilate(u_texture, uv, u_resolution, 0.05, 1.0);
    
    if (erosionResult > 0.5) {
        alpha = 0.0;
    }
    
    // Apply spill suppression - strong green tint removal
    if (u_spill_reduction > 0.0 && alpha > 0.0 && alpha < 1.0) {
        float spill = color.g - max(color.r, color.b);
        if (spill > 0.0) {
            color.g = max(color.r, color.b);
        }
    }
    
    // Ensure fully transparent pixels have zero alpha
    if (alpha < 0.01) {
        alpha = 0.0;
    }
    
    // Output final color with alpha
    o_fragColor = vec4(color.rgb, color.a * alpha);
}
