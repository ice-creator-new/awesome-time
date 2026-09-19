#include <flutter/runtime_effect.glsl>

uniform vec2 uSize;
uniform float uTime;
uniform float uSpeed;
uniform vec4 uC1;
uniform vec4 uC2;

out vec4 fragColor;

void main() {
  vec2 uv = FlutterFragCoord().xy / uSize;
  float aspect = uSize.x / max(uSize.y, 1.0);
  vec2 p = vec2(uv.x * aspect, uv.y);
  float t = uTime * (0.18 + 0.22 * uSpeed);

  vec2 c1 = vec2(
    0.32 * aspect + 0.20 * aspect * sin(t * 0.63),
    0.38 + 0.18 * cos(t * 0.47)
  );
  vec2 c2 = vec2(
    0.70 * aspect + 0.18 * aspect * cos(t * 0.41 + 1.2),
    0.62 + 0.16 * sin(t * 0.55 + 0.6)
  );

  float d1 = length(p - c1);
  float d2 = length(p - c2);
  float a = smoothstep(0.92, 0.08, d1);
  float b = smoothstep(0.98, 0.10, d2);

  // Dark tinted well — never mix toward white.
  vec3 base = uC1.rgb * 0.18 + uC2.rgb * 0.08;
  vec3 col = base;
  col = mix(col, uC1.rgb, a * 0.92);
  col = mix(col, uC2.rgb, b * 0.88);

  float vig = smoothstep(1.15, 0.22, length((uv - vec2(0.5)) * vec2(1.05, 1.15)));
  col *= 0.55 + 0.45 * vig;

  fragColor = vec4(col, 1.0);
}
