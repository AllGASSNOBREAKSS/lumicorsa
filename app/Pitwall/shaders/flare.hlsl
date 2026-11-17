// Lens flare (quarter res): ghosts mirrored through the lens centre plus a halo ring, built from the bloom prefilter,
// with a little chromatic split per ghost like real coated glass.
// @common
// @textures txPLSrc
// @values gPLAspect:float
float3 plGhostSample(float2 uv, float2 dir, float split)
{
  return float3(plSample(txPLSrc, uv + dir * split).r, plSample(txPLSrc, uv).g, plSample(txPLSrc, uv - dir * split).b);
}

float4 main(PS_IN pin) {
  float2 uv = 1.0 - pin.Tex;                        // flip through the optical centre
  float2 toCentre = (0.5 - uv);
  float3 acc = 0.0;
  const float scales[5] = { -0.42, 0.18, 0.55, 0.78, 1.35 };
  const float3 tints[5] = { float3(1.0, 0.75, 0.45), float3(0.45, 0.75, 1.0), float3(0.85, 1.0, 0.7), float3(1.0, 0.55, 0.85), float3(0.6, 0.8, 1.0) };
  [unroll] for (int i = 0; i < 5; ++i) {
    float2 g = uv + toCentre * scales[i] * 2.0;
    float w = pow(saturate(1.0 - length(g - 0.5) / 0.75), 6.0);
    acc += plGhostSample(g, toCentre, 0.004 * (i + 1)) * tints[i] * w;
  }
  // halo: a thin ring sampled at a fixed radius from the centre
  float2 d = toCentre * float2(gPLAspect, 1.0);
  float2 hv = normalize(toCentre + 1e-5) * 0.42;
  float ring = pow(saturate(1.0 - abs(length(d) - 0.42) / 0.06), 3.0);
  acc += plGhostSample(uv + hv, toCentre, 0.01) * ring * float3(1.0, 0.85, 0.7) * 0.6;
  return float4(acc, 1.0);
}
