// Separable 9-tap Gaussian on the quarter-res luma (run once horizontally, once vertically).
// @textures txPLSrc
// @values gPLDir:float2
float4 main(PS_IN pin) {
  const float w[5] = { 0.2270270270, 0.1945945946, 0.1216216216, 0.0540540541, 0.0162162162 };
  float r = txPLSrc.SampleLevel(samLinearClamp, pin.Tex, 0).x * w[0];
  [unroll] for (int i = 1; i < 5; ++i)
    r += (txPLSrc.SampleLevel(samLinearClamp, pin.Tex + gPLDir * i, 0).x + txPLSrc.SampleLevel(samLinearClamp, pin.Tex - gPLDir * i, 0).x) * w[i];
  return r.xxxx;
}
