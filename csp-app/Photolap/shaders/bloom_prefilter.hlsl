// Bloom prefilter: full-res frame -> half-res, rebuilt into scene-referred light, soft-knee threshold.
// @common
// @textures txPLSrc
// @values gPLSrcTexel:float2 gPLRecover:float gPLExposure:float gPLThreshold:float
float4 main(PS_IN pin) {
  float3 c = plToLin(plDown13(txPLSrc, pin.Tex, gPLSrcTexel));
  c = plInverseTonemap(c, gPLRecover) * exp2(gPLExposure);
  float br = max(max(c.r, c.g), c.b);
  float knee = gPLThreshold * 0.5;
  float soft = clamp(br - gPLThreshold + knee, 0.0, 2.0 * knee);
  soft = soft * soft / (4.0 * knee + 1e-4);
  float w = max(soft, br - gPLThreshold) / max(br, 1e-4);
  return float4(min(c * w, 64.0), 1.0);
}
