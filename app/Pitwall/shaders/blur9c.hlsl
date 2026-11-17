// Separable 9-tap Gaussian on colour (depth of field background).
// @textures txPLSrc
// @values gPLDir:float2
float4 main(PS_IN pin) {
  const float w[5] = { 0.2270270270, 0.1945945946, 0.1216216216, 0.0540540541, 0.0162162162 };
  float3 r = txPLSrc.SampleLevel(samLinearClamp, pin.Tex, 0).rgb * w[0];
  [unroll] for (int i = 1; i < 5; ++i)
    r += (txPLSrc.SampleLevel(samLinearClamp, pin.Tex + gPLDir * i, 0).rgb + txPLSrc.SampleLevel(samLinearClamp, pin.Tex - gPLDir * i, 0).rgb) * w[i];
  return float4(r, 1.0);
}
