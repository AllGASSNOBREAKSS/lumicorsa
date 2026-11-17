// Panel background: frosted glass. Blurs the game frame behind the window, tints it, adds a soft top sheen and a
// hairline border, and cuts rounded corners (alpha-blended over the scene).
// @textures txPWScreen
// @values gPWUvMin:float2 gPWUvMax:float2 gPWSize:float2 gPWTexel:float2 gPWTint:float4 gPWRadius:float
float pwRoundBox(float2 p, float2 halfSize, float r)
{
  float2 q = abs(p) - halfSize + r;
  return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

float4 main(PS_IN pin) {
  float2 uv = pin.Tex;
  float2 local = (uv - gPWUvMin) / max(gPWUvMax - gPWUvMin, 1e-6) * gPWSize;

  // two-ring golden-angle blur, wide enough to read as frosted glass
  float3 acc = txPWScreen.SampleLevel(samLinearClamp, uv, 0).rgb;
  float wsum = 1.0;
  [unroll] for (int i = 0; i < 24; ++i) {
    float a = i * 2.39996;
    float r = (i < 12 ? 9.0 : 22.0) * (0.6 + 0.4 * frac(i * 0.618));
    float2 o = float2(cos(a), sin(a)) * r * gPWTexel;
    acc += txPWScreen.SampleLevel(samLinearClamp, uv + o, 0).rgb;
    wsum += 1.0;
  }
  float3 blur = acc / wsum;

  float3 col = lerp(blur * 0.55, gPWTint.rgb, gPWTint.a);
  float t = local.y / max(gPWSize.y, 1.0);
  col += (1.0 - smoothstep(0.0, 0.22, t)) * 0.045;                       // top sheen
  col += 0.012 * frac(sin(dot(local, float2(12.9898, 78.233))) * 43758.5453);   // fine grain

  float d = pwRoundBox(local - gPWSize * 0.5, gPWSize * 0.5, gPWRadius);
  float alpha = saturate(0.5 - d);                                         // anti-aliased rounded edge
  float border = saturate(1.0 - abs(d + 1.0)) * lerp(0.22, 0.08, t);       // hairline, brighter at the top
  col += border;
  return float4(col, alpha);
}
