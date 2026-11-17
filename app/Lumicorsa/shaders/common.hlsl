// Pitwall shared helpers. The app prepends this file to every shader marked `// @common`.
// Everything is prefixed `pl` / `PL_` so nothing collides with names in CSP's shader template.

static const float3 PL_LUMA = float3(0.2126, 0.7152, 0.0722);

float plLuma(float3 c) { return dot(c, PL_LUMA); }
float3 plToLin(float3 c) { c = saturate(c); return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4); }
float3 plToGam(float3 c) { c = saturate(c); return c <= 0.0031308 ? c * 12.92 : 1.055 * pow(c, 1.0 / 2.4) - 0.055; }

float3 plSample(Texture2D t, float2 uv) { return t.SampleLevel(samLinearClamp, uv, 0).rgb; }

// 13-tap downsample (Jimenez 2014 layout), soft-weighted to suppress fireflies.
float3 plDown13(Texture2D s, float2 uv, float2 px)
{
  float3 a = plSample(s, uv + px * float2(-2, -2)), b = plSample(s, uv + px * float2(0, -2)), c = plSample(s, uv + px * float2(2, -2));
  float3 d = plSample(s, uv + px * float2(-1, -1)), e = plSample(s, uv + px * float2(1, -1));
  float3 f = plSample(s, uv + px * float2(-2, 0)),  g = plSample(s, uv),                      h = plSample(s, uv + px * float2(2, 0));
  float3 i = plSample(s, uv + px * float2(-1, 1)),  j = plSample(s, uv + px * float2(1, 1));
  float3 k = plSample(s, uv + px * float2(-2, 2)),  l = plSample(s, uv + px * float2(0, 2)),  m = plSample(s, uv + px * float2(2, 2));
  return (d + e + i + j) * 0.125 + (a + b + f + g) * 0.03125 + (b + c + g + h) * 0.03125 + (f + g + k + l) * 0.03125 + (g + h + l + m) * 0.03125;
}

float3 plTent(Texture2D s, float2 uv, float2 px)
{
  float3 r = plSample(s, uv) * 4.0;
  r += (plSample(s, uv + float2(px.x, 0)) + plSample(s, uv - float2(px.x, 0)) + plSample(s, uv + float2(0, px.y)) + plSample(s, uv - float2(0, px.y))) * 2.0;
  r += plSample(s, uv + px) + plSample(s, uv - px) + plSample(s, uv + float2(px.x, -px.y)) + plSample(s, uv + float2(-px.x, px.y));
  return r / 16.0;
}

// LDR (0..1 linear) -> scene-referred estimate. Highlights near 1.0 are stretched back out.
float3 plInverseTonemap(float3 c, float k)
{
  float peak = max(max(c.r, c.g), c.b);
  float expand = 1.0 / max(1.0 - peak * k * 0.94, 0.06);
  return c * lerp(1.0, expand, saturate(peak * peak));
}

// Filmic shoulder (Narkowicz ACES fit) with a matching mid-grey, linear toe so cockpits and tunnels don't crush.
float3 plFilmic(float3 x)
{
  float3 y = x * 0.72;
  y = saturate((y * (2.51 * y + 0.03)) / (y * (2.43 * y + 0.59) + 0.14)) / 0.95;
  return saturate(lerp(x, y, saturate(x / 0.18)));
}

float3 plWhiteBalance(float3 c, float temp, float tint)
{
  float3 m = float3(1.0 + 0.10 * temp, 1.0 - 0.06 * tint, 1.0 - 0.10 * temp);
  m.g += 0.03 * tint;
  return c * m / plLuma(m);
}

float plHash(float2 p)
{
  float3 p3 = frac(float3(p.xyx) * 0.1031);
  p3 += dot(p3, p3.yzx + 33.33);
  return frac((p3.x + p3.y) * p3.z);
}
