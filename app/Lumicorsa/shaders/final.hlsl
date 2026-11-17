// Lumicorsa final pass, drawn fullscreen in the first UI callback (after the scene, before any HUD or app).
// Order per pixel: Detail (adaptive sharpen + clarity) -> depth of field -> Lens CA -> linear light: eye adaptation,
// contact AO -> Light (inverse tonemap, exposure, white balance, bloom, halation, sun shafts, lens flare, filmic,
// tone curve) -> Atmosphere (depth haze, ground mist) -> vignette + grain -> master mix / split view.
// @common
// @textures txPLBase txPLScreen txPLDepth txPLBloom txPLWide txPLLumaQ txPLProbe txPLShafts txPLFlare txPLAO txPLDofBlur txPLAdapt
// @values gPLTexel:float2 gPLSize:float2 gPLLight:float gPLAtmos:float gPLDetail:float gPLLens:float gPLBloomOn:float gPLSplit:float gPLNear:float gPLFar:float gPLTime:float gPLShaftsOn:float gPLFlareOn:float gPLAOOn:float gPLDofOn:float gPLSunColor:float3 gPLFocus:float gPLAdaptOn:float gPLMistOn:float gPLCamHeight:float gPLCamLook:float3 gPLCamUp:float3 gPLCamSide:float3 gPLTanHalf:float2 PL_Exposure:float PL_HighlightRecover:float PL_Temperature:float PL_Tint:float PL_BloomIntensity:float PL_Halation:float PL_FilmicStrength:float PL_Contrast:float PL_Lift:float PL_Saturation:float PL_Vibrance:float PL_BlackPoint:float PL_ShadowTint:float3 PL_HighlightTint:float3 PL_HazeDensity:float PL_HazeStart:float PL_HazeColor:float3 PL_AerialDesat:float PL_Mist:float PL_Clarity:float PL_Sharpen:float PL_ChromaAb:float PL_Vignette:float PL_Grain:float PL_Mix:float PL_Shafts:float PL_Flare:float PL_AO:float PL_Dof:float

float3 plBase(float2 uv) { return txPLBase.SampleLevel(samLinearClamp, uv, 0).rgb; }

float plDistance(float2 uv, bool reversed)
{
  float zr = txPLDepth.SampleLevel(samPointClamp, uv, 0).x;
  float zz = reversed ? zr : 1.0 - zr;                                   // 0 at the far plane / sky either way
  return gPLNear * gPLFar / (gPLNear + zz * (gPLFar - gPLNear));         // metres, same formula for both conventions
}

float4 main(PS_IN pin) {
  float2 uv = pin.Tex;
  float3 orig = txPLScreen.SampleLevel(samLinearClamp, uv, 0).rgb;

  // Split view: left half is the untouched game image, with a thin divider.
  if (gPLSplit > 0.5) {
    if (abs(uv.x - 0.5) < gPLTexel.x * 1.5) return float4(0.95, 0.95, 0.95, 1.0);
    if (uv.x < 0.5) return float4(orig, 1.0);
  }

  float2 px = gPLTexel;
  bool reversed = txPLProbe.SampleLevel(samPointClamp, float2(0.5, 0.5), 0).x < 0.5;
  float3 e = plBase(uv);
  float3 c = e;

  // ------------------------------------------------------------------ DETAIL
  if (gPLDetail > 0.5) {
    float3 b = plBase(uv + float2(0, -px.y)), d = plBase(uv + float2(-px.x, 0));
    float3 f = plBase(uv + float2(px.x, 0)),  h = plBase(uv + float2(0, px.y));
    float3 mn = min(e, min(min(b, d), min(f, h)));
    float3 mx = max(e, max(max(b, d), max(f, h)));
    float3 amp = sqrt(saturate(min(mn, 1.0 - mx) / max(mx, 1e-4)));
    float3 w = -amp * lerp(0.125, 0.2, PL_Sharpen);
    float3 sharp = saturate(((b + d + f + h) * w + e) / (1.0 + 4.0 * w));
    c = lerp(e, sharp, saturate(PL_Sharpen * 2.0));
    float l = plLuma(c);
    float blur = txPLLumaQ.SampleLevel(samLinearClamp, uv, 0).x;
    float mid = 1.0 - pow(abs(l * 2.0 - 1.0), 2.0);
    c *= 1.0 + (l - blur) * PL_Clarity * 2.0 * mid / max(l, 1e-3);
  }

  // ------------------------------------------------------------------ DEPTH OF FIELD (auto-focus on screen centre)
  if (gPLDofOn > 0.5) {
    float focus = 0.0;
    [unroll] for (int k = 0; k < 5; ++k) focus += plDistance(float2(0.5, 0.5) + float2(k - 2, 0) * 0.01, reversed);
    focus = gPLFocus > 0.0 ? gPLFocus : focus / 5.0;                      // manual focus (cockpit, photo) or auto
    float dist = plDistance(uv, reversed);
    float coc = saturate(abs(1.0 / max(dist, 0.05) - 1.0 / max(focus, 0.05)) * focus * PL_Dof * 1.5);
    c = lerp(c, plSample(txPLDofBlur, uv), coc);
  }

  // ------------------------------------------------------------------ LENS: chromatic aberration (before the "sensor")
  float2 cen = uv - 0.5;
  float aspect = gPLSize.x / max(gPLSize.y, 1.0);
  float r2 = dot(cen * float2(aspect, 1.0), cen * float2(aspect, 1.0));
  if (gPLLens > 0.5 && PL_ChromaAb > 0.0) {
    float2 off = cen * r2 * PL_ChromaAb * 0.012;
    c.r += plBase(uv - off).r - e.r;
    c.b += plBase(uv + off).b - e.b;
  }

  c = plToLin(c);

  // ------------------------------------------------------------------ EYE ADAPTATION (adapted mean log luminance)
  if (gPLAdaptOn > 0.5) {
    float adapted = exp2(txPLAdapt.SampleLevel(samPointClamp, float2(0.5, 0.5), 0).x);
    c *= exp2(clamp(log2(0.16 / max(adapted, 1e-4)), -1.5, 1.5) * 0.6);
  }

  // ------------------------------------------------------------------ CONTACT AO (linear light, before relighting)
  if (gPLAOOn > 0.5) c *= lerp(1.0, txPLAO.SampleLevel(samLinearClamp, uv, 0).x, PL_AO);

  // ------------------------------------------------------------------ LIGHT
  if (gPLLight > 0.5) {
    float3 hdr = plInverseTonemap(c, PL_HighlightRecover) * exp2(PL_Exposure);
    hdr = plWhiteBalance(hdr, PL_Temperature, PL_Tint);
    if (gPLBloomOn > 0.5) {
      hdr += plTent(txPLBloom, uv, px * 2.0) / 5.0 * PL_BloomIntensity;
      hdr += plSample(txPLWide, uv) / 3.0 * float3(1.0, 0.32, 0.12) * PL_Halation * 0.6;
    }
    if (gPLShaftsOn > 0.001) hdr += plSample(txPLShafts, uv) * gPLSunColor * PL_Shafts * gPLShaftsOn;   // faded in Lua
    if (gPLFlareOn > 0.5) hdr += plSample(txPLFlare, uv) * PL_Flare * 0.35;
    float3 ldr = lerp(saturate(hdr), plFilmic(hdr), PL_FilmicStrength);
    float lum = plLuma(ldr);
    float3 g = (ldr - 0.18) * (1.0 + PL_Contrast) + 0.18;
    g += PL_Lift * 0.08 * (1.0 - saturate(g)) * (1.0 - saturate(g));         // shadow lift (toe)
    g = max(g - PL_BlackPoint, 0.0) / max(1.0 - PL_BlackPoint, 1e-3);
    g *= lerp(PL_ShadowTint, PL_HighlightTint, smoothstep(0.05, 0.6, lum)) * 2.0;
    float sat = max(max(g.r, g.g), g.b) - min(min(g.r, g.g), g.b);
    g = lerp(plLuma(g).xxx, g, 1.0 + PL_Saturation + PL_Vibrance * (1.0 - sat));
    c = saturate(g);
  }

  // ------------------------------------------------------------------ ATMOSPHERE
  if (gPLAtmos > 0.5 && PL_HazeDensity > 0.0) {
    float zr = txPLDepth.SampleLevel(samPointClamp, uv, 0).x;
    float zz = reversed ? zr : 1.0 - zr;
    float dist = gPLNear * gPLFar / (gPLNear + zz * (gPLFar - gPLNear));
    float sky = zz <= 1e-6 ? 1.0 : 0.0;
    float f = (1.0 - exp(-max(dist - PL_HazeStart * 1000.0, 0.0) * PL_HazeDensity * 0.006)) * (1.0 - sky);
    float lc = plLuma(c);
    float3 aerial = lerp(c, lc.xxx, PL_AerialDesat * f);
    c = lerp(aerial, PL_HazeColor * max(lc, 0.35) * 1.6, f * 0.65);
  }

  // ------------------------------------------------------------------ GROUND MIST (height fog from depth + camera)
  if (gPLMistOn > 0.5 && PL_Mist > 0.0) {
    float zr = txPLDepth.SampleLevel(samPointClamp, uv, 0).x;
    float zz = reversed ? zr : 1.0 - zr;
    float dist = gPLNear * gPLFar / (gPLNear + zz * (gPLFar - gPLNear));
    float sky = zz <= 1e-6 ? 1.0 : 0.0;
    float3 ray = normalize(gPLCamLook + (uv.x * 2.0 - 1.0) * gPLTanHalf.x * gPLCamSide - (uv.y * 2.0 - 1.0) * gPLTanHalf.y * gPLCamUp);
    float height = gPLCamHeight + ray.y * min(dist, 2000.0);                // metres above the road under the car
    float m = (1.0 - exp(-min(dist, 2000.0) * PL_Mist * 0.004)) * exp(-max(height, 0.0) / 2.5) * (1.0 - sky);
    c = lerp(c, float3(0.72, 0.75, 0.78) * max(plLuma(c), 0.3) * 1.5, saturate(m) * 0.85);
  }

  // ------------------------------------------------------------------ LENS: vignette + grain
  if (gPLLens > 0.5) {
    float ct = rsqrt(1.0 + r2 * PL_Vignette * 1.6);
    c *= lerp(1.0, ct * ct * ct * ct, PL_Vignette);
  }
  c = plToGam(c);
  if (gPLLens > 0.5 && PL_Grain > 0.0) {
    float2 p = uv * gPLSize;
    float n = plHash(p + frac(gPLTime * 0.37) * 1013.0) + plHash(p.yx * 1.37 + frac(gPLTime * 0.11) * 517.0) - 1.0;
    float l = plLuma(c);
    c += n * PL_Grain * 0.06 * (1.0 - abs(l * 2.0 - 1.0)) * (l + 0.05);
  }

  return float4(lerp(orig, saturate(c), PL_Mix), 1.0);
}
