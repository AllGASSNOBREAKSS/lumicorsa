// Bloom upsample: same-size octave plus a tent-filtered copy of the octave below.
// @common
// @textures txPLSkip txPLLow
// @values gPLLowTexel:float2
float4 main(PS_IN pin) {
  return float4(plSample(txPLSkip, pin.Tex) + plTent(txPLLow, pin.Tex, gPLLowTexel), 1.0);
}
