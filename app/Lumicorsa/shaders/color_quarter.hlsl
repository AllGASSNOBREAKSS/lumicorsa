// Depth of field source: quarter-res colour copy of the frame.
// @common
// @textures txPLSrc
// @values gPLSrcTexel:float2
float4 main(PS_IN pin) {
  return float4(plDown13(txPLSrc, pin.Tex, gPLSrcTexel * 2.0), 1.0);
}
