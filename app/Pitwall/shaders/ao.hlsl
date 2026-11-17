// Contact ambient occlusion from depth only (half res). Inverse depth (1/distance) is linear across the screen for any
// plane, so for a pair of opposite samples a flat surface gives (w_a + w_b) / 2 == w_centre. Only creases, where both
// sides are closer than the centre, darken: no grey wash on roads or walls seen at a grazing angle.
// @textures txPLDepth txPLProbe
// @values gPLTexel:float2 gPLNear:float gPLFar:float gPLRadius:float
float pwDist(float2 uv, bool reversed)
{
  float zr = txPLDepth.SampleLevel(samPointClamp, uv, 0).x;
  float zz = reversed ? zr : 1.0 - zr;
  return gPLNear * gPLFar / (gPLNear + max(zz, 1e-7) * (gPLFar - gPLNear));
}

float4 main(PS_IN pin) {
  bool reversed = txPLProbe.SampleLevel(samPointClamp, float2(0.5, 0.5), 0).x < 0.5;
  float d0 = pwDist(pin.Tex, reversed);
  if (d0 > gPLFar * 0.5) return (1.0).xxxx;                            // sky
  float w0 = 1.0 / d0;
  float radiusPx = clamp(gPLRadius / d0, 2.0, 48.0);                   // ~constant world radius
  float occ = 0.0;
  [unroll] for (int i = 0; i < 6; ++i) {
    float a = i * 0.5236 + 0.26;                                       // 6 directions over 180 degrees
    [unroll] for (int s = 1; s <= 2; ++s) {
      float2 o = float2(cos(a), sin(a)) * radiusPx * (s * 0.5) * gPLTexel;
      float wa = 1.0 / pwDist(pin.Tex + o, reversed);
      float wb = 1.0 / pwDist(pin.Tex - o, reversed);
      float crease = ((wa + wb) * 0.5 - w0) / w0;                      // > 0: both neighbours closer
      float range = saturate(1.0 - abs(wa - wb) / w0 * 0.5);           // fade across silhouettes
      occ += saturate(crease * 6.0) * range;
    }
  }
  return (1.0 - occ / 12.0).xxxx;
}
