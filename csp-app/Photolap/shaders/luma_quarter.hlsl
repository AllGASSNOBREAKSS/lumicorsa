// Clarity source: quarter-res luma of the frame (display space, like the frame Detail works on).
// @common
// @textures txPLSrc
// @values gPLSrcTexel:float2
float4 main(PS_IN pin) {
  return plLuma(plDown13(txPLSrc, pin.Tex, gPLSrcTexel * 2.0)).xxxx;
}
