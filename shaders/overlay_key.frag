// Colour key (green screen) for media overlays in the editor preview.
// Same formula as FFmpeg's `colorkey` filter used by the exporter:
//   diff  = sqrt(((r-kr)^2 + (g-kg)^2 + (b-kb)^2) / 3)
//   alpha = clamp((diff - similarity) / blend, 0, 1)   (blend > 0)
//         = diff > similarity ? 1 : 0                 (blend = 0)
#version 460 core

#include <flutter/runtime_effect.glsl>

uniform vec2 uSize;          // set by the engine
uniform vec3 uKey;           // key colour, 0..1
uniform float uSimilarity;   // 0..1
uniform float uBlend;        // 0..1
uniform sampler2D uTexture;  // set by the engine (filter input)

out vec4 fragColor;

void main() {
  vec2 uv = FlutterFragCoord().xy / uSize;
#ifdef IMPELLER_TARGET_OPENGLES
  uv.y = 1.0 - uv.y;
#endif
  vec4 c = texture(uTexture, uv);
  vec3 rgb = c.a > 0.0 ? c.rgb / c.a : vec3(0.0);
  vec3 d = rgb - uKey;
  float diff = sqrt(dot(d, d) / 3.0);
  float a = uBlend > 0.0001
      ? clamp((diff - uSimilarity) / uBlend, 0.0, 1.0)
      : (diff > uSimilarity ? 1.0 : 0.0);
  float outA = c.a * a;
  fragColor = vec4(rgb * outA, outA);
}
