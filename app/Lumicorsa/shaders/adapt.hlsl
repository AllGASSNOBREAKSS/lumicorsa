// Eye adaptation, step 2 (1x1): average the 16x9 grid and move the adapted value toward it at the chosen speed.
// Two 1x1 canvases ping-pong frame to frame, so the adaptation state stays on the GPU.
// @textures txPLSmall txPLPrev
// @values gPLRate:float
float4 main(PS_IN pin) {
  float acc = 0.0;
  [unroll] for (int y = 0; y < 9; ++y)
    [unroll] for (int x = 0; x < 16; ++x)
      acc += txPLSmall.Load(int3(x, y, 0)).x;
  float target = acc / 144.0;
  float prev = txPLPrev.Load(int3(0, 0, 0)).x;
  float v = (prev == 0.0 || prev != prev) ? target : lerp(prev, target, saturate(gPLRate));
  return v.xxxx;
}
