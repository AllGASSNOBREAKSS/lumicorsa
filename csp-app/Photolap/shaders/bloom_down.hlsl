// Bloom downsample: one octave down with the 13-tap filter.
// @common
// @textures txPLSrc
// @values gPLSrcTexel:float2
float4 main(PS_IN pin) {
  return float4(plDown13(txPLSrc, pin.Tex, gPLSrcTexel), 1.0);
}
