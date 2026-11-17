// 1x1 probe: which way CSP writes depth (reversed: 1 near, 0 far; standard: 0 near, 1 far), latched over time.
// Sky pixels sit exactly on the far plane, so they are the evidence: exactly 0 means reversed, exactly 1 means standard.
// The decision only changes when the sky clearly votes the other way; with no sky in view (garage, tunnel, cockpit
// looking down) the previous decision is kept. 0.25 = reversed, 0.75 = standard; an empty canvas (0) reads as
// reversed, CSP's convention. (2.0.0 guessed from the mean depth every frame, which flipped in cockpit view.)
// @textures txPLDepth txPLPrev
float4 main(PS_IN pin) {
  float c0 = 0.0, c1 = 0.0;
  [unroll] for (int y = 0; y < 9; ++y)
    [unroll] for (int x = 0; x < 16; ++x) {
      float z = txPLDepth.SampleLevel(samPointClamp, (float2(x, y) + 0.5) / float2(16.0, 9.0), 0).x;
      c0 += z <= 1e-7 ? 1.0 : 0.0;
      c1 += z >= 1.0 - 1e-7 ? 1.0 : 0.0;
    }
  float prev = txPLPrev.Load(int3(0, 0, 0)).x;
  float v = prev < 0.5 ? 0.25 : 0.75;
  if (c0 >= 6.0 && c0 > c1 * 3.0) v = 0.25;
  else if (c1 >= 6.0 && c1 > c0 * 3.0) v = 0.75;
  return v.xxxx;
}
