#include <flutter/runtime_effect.glsl>

uniform vec2 uSize;
uniform float uTime;
uniform float uSpeed;
uniform vec4 uC1;
uniform vec4 uC2;
uniform vec4 uC3;

out vec4 fragColor;

void main() {
  vec2 uv = FlutterFragCoord().xy / uSize;
  float aspect = uSize.x / max(uSize.y, 1.0);
  vec2 p = vec2(uv.x * aspect, uv.y);

  // Slow wash — visible motion without rushing.
  float t = uTime * (0.38 + 0.28 * uSpeed);

  // Domain warp — colors fold into each other instead of sliding as discs.
  vec2 warp = vec2(
    sin(p.y * 3.1 + t * 1.4) + 0.55 * sin(p.x * 2.2 - t * 0.9),
    cos(p.x * 2.7 - t * 1.1) + 0.55 * cos(p.y * 2.0 + t * 0.7)
  ) * 0.14;
  vec2 q = p + warp;

  vec2 c1 = vec2(
    0.26 * aspect + 0.28 * aspect * sin(t * 0.95),
    0.34 + 0.26 * cos(t * 0.80)
  );
  vec2 c2 = vec2(
    0.74 * aspect + 0.26 * aspect * cos(t * 0.70 + 1.2),
    0.66 + 0.24 * sin(t * 0.90 + 0.6)
  );
  vec2 c3 = vec2(
    0.52 * aspect + 0.30 * aspect * sin(t * 0.75 + 2.1),
    0.50 + 0.28 * cos(t * 0.85 + 0.9)
  );

  float d1 = length(q - c1);
  float d2 = length(q - c2);
  float d3 = length(q - c3);

  // Soft Gaussian lobes that sum-normalize → true melt / 相融 blend.
  float w1 = exp(-d1 * d1 * 4.5);
  float w2 = exp(-d2 * d2 * 4.5);
  float w3 = exp(-d3 * d3 * 4.5);
  float sum = w1 + w2 + w3 + 1e-4;
  vec3 col = (uC1.rgb * w1 + uC2.rgb * w2 + uC3.rgb * w3) / sum;

  // Keep the wash readable without washing toward white.
  col = col * 1.12;

  float vig = smoothstep(1.30, 0.30, length((uv - vec2(0.5)) * vec2(1.05, 1.15)));
  col *= 0.86 + 0.14 * vig;

  fragColor = vec4(min(col, vec3(1.0)), 1.0);
}
