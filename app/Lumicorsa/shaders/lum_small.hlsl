// Eye adaptation, step 1 (16x9): mean log luminance of a block of the frame (display-referred, linearised).
// @common
// @textures txPLSrc
// @values gPLSrcTexel:float2
float4 main(PS_IN pin) {
  float acc = 0.0;
  [unroll] for (int y = 0; y < 4; ++y)
    [unroll] for (int x = 0; x < 4; ++x) {
      float2 o = (float2(x, y) - 1.5) / float2(16.0 * 4.0, 9.0 * 4.0);
      acc += log2(max(plLuma(plToLin(plSample(txPLSrc, pin.Tex + o))), 1e-4));
    }
  return (acc / 16.0).xxxx;
}
