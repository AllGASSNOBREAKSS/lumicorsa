// 1x1 probe: mean raw depth over an 8x8 grid. With standard depth nearly every pixel is above 0.5 (anything past
// twice the near plane); with reversed depth nearly every pixel is below it. The final pass reads this to pick the
// convention, so haze works whichever way CSP writes depth.
// @textures txPLDepth
float4 main(PS_IN pin) {
  float s = 0.0;
  [unroll] for (int y = 0; y < 8; ++y)
    [unroll] for (int x = 0; x < 8; ++x)
      s += txPLDepth.SampleLevel(samPointClamp, (float2(x, y) + 0.5) / 8.0, 0).x;
  return (s / 64.0).xxxx;
}
