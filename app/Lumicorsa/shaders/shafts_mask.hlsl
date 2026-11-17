// Sun shafts, step 1 (half res): bright sky only. Geometry is excluded with the depth buffer, so chrome and paint
// don't spray light rays.
// @common
// @textures txPLSrc txPLDepth txPLProbe
// @values gPLSrcTexel:float2
float4 main(PS_IN pin) {
  float3 c = plToLin(plDown13(txPLSrc, pin.Tex, gPLSrcTexel));
  float zr = txPLDepth.SampleLevel(samPointClamp, pin.Tex, 0).x;
  bool reversed = txPLProbe.SampleLevel(samPointClamp, float2(0.5, 0.5), 0).x < 0.5;
  float zz = reversed ? zr : 1.0 - zr;
  float sky = zz <= 1e-6 ? 1.0 : 0.0;
  float l = plLuma(c);
  return float4(c * sky * smoothstep(0.35, 0.95, l), 1.0);
}
