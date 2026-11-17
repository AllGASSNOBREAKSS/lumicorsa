// Sun shafts, step 2 (half res): radial blur of the sky mask toward the sun's screen position.
// @textures txPLSrc
// @values gPLSunUV:float2 gPLLength:float
float4 main(PS_IN pin) {
  float2 uv = pin.Tex;
  float2 delta = (uv - gPLSunUV) * (gPLLength / 40.0);
  float3 acc = 0.0;
  float decay = 1.0;
  [loop] for (int i = 0; i < 40; ++i) {
    uv -= delta;
    acc += txPLSrc.SampleLevel(samLinearClamp, uv, 0).rgb * decay;
    decay *= 0.955;
  }
  return float4(acc / 14.0, 1.0);
}
