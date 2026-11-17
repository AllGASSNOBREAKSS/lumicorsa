/*
 * PHOTOLAP — photoreal post stack for Assetto Corsa (CSP)
 * Copyright (c) 2026 Photolap contributors. MIT License.
 *
 * Four techniques, meant to run in this order:
 *   Photolap_Light   inverse-tonemap -> exposure / white balance -> bloom + halation -> filmic re-tonemap -> grade
 *   Photolap_Atmos   depth-aware aerial perspective (distance haze, sky-safe)
 *   Photolap_Detail  clarity (local contrast) + contrast-adaptive sharpening
 *   Photolap_Lens    chromatic aberration, natural vignette, luma-aware film grain
 *
 * Every uniform is named PL_* so the Photolap add-on (and the in-game CSP app) can drive it live.
 * Standalone: needs no ReShade.fxh / no other shader packs.
 */

// ---------------------------------------------------------------- preprocessor
#ifndef PL_DEPTH_REVERSED
	#define PL_DEPTH_REVERSED 0      // AC (DX11) writes standard depth. Flip to 1 if haze hits the sky instead of the horizon.
#endif
#ifndef PL_DEPTH_UPSIDE_DOWN
	#define PL_DEPTH_UPSIDE_DOWN 0
#endif
#ifndef PL_DEPTH_FAR_PLANE
	#define PL_DEPTH_FAR_PLANE 1000.0
#endif

#define PL_PX     float2(BUFFER_RCP_WIDTH, BUFFER_RCP_HEIGHT)
#define PL_ASPECT (BUFFER_WIDTH * BUFFER_RCP_HEIGHT)

// ---------------------------------------------------------------- light
uniform float PL_Exposure        < ui_type = "slider"; ui_min = -2.0; ui_max = 2.0; ui_step = 0.01; ui_category = "Light"; ui_label = "Exposure (EV)"; > = 0.0;
uniform float PL_HighlightRecover< ui_type = "slider"; ui_min = 0.0;  ui_max = 1.0; ui_category = "Light"; ui_label = "Highlight recovery"; ui_tooltip = "Rebuilds HDR-ish highlights from the LDR frame so sun, headlights and chrome roll off like a camera."; > = 0.55;
uniform float PL_Temperature     < ui_type = "slider"; ui_min = -1.0; ui_max = 1.0; ui_category = "Light"; ui_label = "White balance: temperature"; > = 0.0;
uniform float PL_Tint            < ui_type = "slider"; ui_min = -1.0; ui_max = 1.0; ui_category = "Light"; ui_label = "White balance: tint"; > = 0.0;
uniform float PL_BloomIntensity  < ui_type = "slider"; ui_min = 0.0;  ui_max = 1.0; ui_category = "Light"; ui_label = "Bloom"; > = 0.22;
uniform float PL_BloomThreshold  < ui_type = "slider"; ui_min = 0.5;  ui_max = 4.0; ui_category = "Light"; ui_label = "Bloom threshold"; > = 1.25;
uniform float PL_Halation        < ui_type = "slider"; ui_min = 0.0;  ui_max = 1.0; ui_category = "Light"; ui_label = "Halation (red film glow)"; > = 0.25;
uniform float PL_FilmicStrength  < ui_type = "slider"; ui_min = 0.0;  ui_max = 1.0; ui_category = "Light"; ui_label = "Filmic response"; > = 0.75;

// ---------------------------------------------------------------- grade
uniform float PL_Contrast        < ui_type = "slider"; ui_min = -0.5; ui_max = 0.5; ui_category = "Grade"; ui_label = "Contrast"; > = 0.08;
uniform float PL_Saturation      < ui_type = "slider"; ui_min = -1.0; ui_max = 1.0; ui_category = "Grade"; ui_label = "Saturation"; > = -0.04;
uniform float PL_Vibrance        < ui_type = "slider"; ui_min = -1.0; ui_max = 1.0; ui_category = "Grade"; ui_label = "Vibrance"; > = 0.12;
uniform float PL_BlackPoint      < ui_type = "slider"; ui_min = -0.05; ui_max = 0.05; ui_category = "Grade"; ui_label = "Black point"; > = 0.004;
uniform float3 PL_ShadowTint     < ui_type = "color"; ui_category = "Grade"; ui_label = "Shadow tint"; > = float3(0.50, 0.50, 0.52);
uniform float3 PL_HighlightTint  < ui_type = "color"; ui_category = "Grade"; ui_label = "Highlight tint"; > = float3(0.51, 0.50, 0.49);

// ---------------------------------------------------------------- atmos
uniform float PL_HazeDensity     < ui_type = "slider"; ui_min = 0.0; ui_max = 1.0; ui_category = "Atmosphere"; ui_label = "Distance haze"; > = 0.30;
uniform float PL_HazeStart       < ui_type = "slider"; ui_min = 0.0; ui_max = 0.5; ui_category = "Atmosphere"; ui_label = "Haze start (linear depth)"; > = 0.02;
uniform float3 PL_HazeColor      < ui_type = "color"; ui_category = "Atmosphere"; ui_label = "Haze colour"; > = float3(0.62, 0.70, 0.80);
uniform float PL_AerialDesat     < ui_type = "slider"; ui_min = 0.0; ui_max = 1.0; ui_category = "Atmosphere"; ui_label = "Aerial desaturation"; > = 0.35;

// ---------------------------------------------------------------- detail
uniform float PL_Clarity         < ui_type = "slider"; ui_min = 0.0; ui_max = 1.0; ui_category = "Detail"; ui_label = "Clarity (local contrast)"; > = 0.22;
uniform float PL_Sharpen         < ui_type = "slider"; ui_min = 0.0; ui_max = 1.0; ui_category = "Detail"; ui_label = "Adaptive sharpening"; > = 0.35;

// ---------------------------------------------------------------- lens
uniform float PL_ChromaAb        < ui_type = "slider"; ui_min = 0.0; ui_max = 1.0; ui_category = "Lens"; ui_label = "Chromatic aberration"; > = 0.12;
uniform float PL_Vignette        < ui_type = "slider"; ui_min = 0.0; ui_max = 1.0; ui_category = "Lens"; ui_label = "Vignette"; > = 0.30;
uniform float PL_Grain           < ui_type = "slider"; ui_min = 0.0; ui_max = 1.0; ui_category = "Lens"; ui_label = "Film grain"; > = 0.10;

// ---------------------------------------------------------------- global
uniform float PL_Mix             < ui_type = "slider"; ui_min = 0.0; ui_max = 1.0; ui_category = "Global"; ui_label = "Master mix"; > = 1.0;
uniform bool  PL_SplitView       < ui_category = "Global"; ui_label = "Split view (left = vanilla)"; > = false;

uniform float PL_Timer  < source = "timer"; >;
uniform int   PL_Frame  < source = "framecount"; >;

// ---------------------------------------------------------------- resources
texture PL_BackBufferTex : COLOR;
texture PL_DepthTex      : DEPTH;
// sRGB is decoded/encoded by hand (no SRGBTexture / SRGBWriteEnable) so the passes work identically when the
// add-on renders them mid-frame on the game's UNORM back buffer in HUD-safe mode.
sampler PL_BackRaw { Texture = PL_BackBufferTex; };
sampler PL_Depth   { Texture = PL_DepthTex; };

texture PL_D2  { Width = BUFFER_WIDTH / 2;  Height = BUFFER_HEIGHT / 2;  Format = RGBA16F; };
texture PL_D4  { Width = BUFFER_WIDTH / 4;  Height = BUFFER_HEIGHT / 4;  Format = RGBA16F; };
texture PL_D8  { Width = BUFFER_WIDTH / 8;  Height = BUFFER_HEIGHT / 8;  Format = RGBA16F; };
texture PL_D16 { Width = BUFFER_WIDTH / 16; Height = BUFFER_HEIGHT / 16; Format = RGBA16F; };
texture PL_D32 { Width = BUFFER_WIDTH / 32; Height = BUFFER_HEIGHT / 32; Format = RGBA16F; };
texture PL_U16 { Width = BUFFER_WIDTH / 16; Height = BUFFER_HEIGHT / 16; Format = RGBA16F; };
texture PL_U8  { Width = BUFFER_WIDTH / 8;  Height = BUFFER_HEIGHT / 8;  Format = RGBA16F; };
texture PL_U4  { Width = BUFFER_WIDTH / 4;  Height = BUFFER_HEIGHT / 4;  Format = RGBA16F; };
texture PL_U2  { Width = BUFFER_WIDTH / 2;  Height = BUFFER_HEIGHT / 2;  Format = RGBA16F; };
sampler sD2  { Texture = PL_D2; };  sampler sD4  { Texture = PL_D4; };  sampler sD8 { Texture = PL_D8; };
sampler sD16 { Texture = PL_D16; }; sampler sD32 { Texture = PL_D32; };
sampler sU16 { Texture = PL_U16; }; sampler sU8  { Texture = PL_U8; };  sampler sU4 { Texture = PL_U4; }; sampler sU2 { Texture = PL_U2; };

texture PL_LumaQ  { Width = BUFFER_WIDTH / 4; Height = BUFFER_HEIGHT / 4; Format = R16F; };
texture PL_LumaQb { Width = BUFFER_WIDTH / 4; Height = BUFFER_HEIGHT / 4; Format = R16F; };
sampler sLumaQ  { Texture = PL_LumaQ; };
sampler sLumaQb { Texture = PL_LumaQb; };

// ---------------------------------------------------------------- helpers
static const float3 LUMA = float3(0.2126, 0.7152, 0.0722);
float Luma(float3 c) { return dot(c, LUMA); }
float3 ToLin(float3 c) { c = saturate(c); return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4); }
float3 ToGam(float3 c) { c = saturate(c); return c <= 0.0031308 ? c * 12.92 : 1.055 * pow(c, 1.0 / 2.4) - 0.055; }
float3 Back(float2 uv) { return ToLin(tex2D(PL_BackRaw, uv).rgb); }

void PostProcessVS(in uint id : SV_VertexID, out float4 pos : SV_Position, out float2 uv : TEXCOORD)
{
	uv.x = (id == 2) ? 2.0 : 0.0;
	uv.y = (id == 1) ? 2.0 : 0.0;
	pos = float4(uv * float2(2.0, -2.0) + float2(-1.0, 1.0), 0.0, 1.0);
}

// LDR (0..1 linear) -> scene-referred estimate. Highlights near 1.0 are stretched back out.
float3 InverseTonemap(float3 c, float k)
{
	float peak = max(max(c.r, c.g), c.b);
	float expand = 1.0 / max(1.0 - peak * k * 0.94, 0.06);
	return c * lerp(1.0, expand, saturate(peak * peak));
}

// Filmic shoulder (Narkowicz ACES approximation) with a matching mid-grey so overall brightness holds.
float3 Filmic(float3 x)
{
	float3 y = x * 0.72;   // maps scene mid-grey 0.18 -> ~0.18 so the curve only reshapes the shoulder
	y = saturate((y * (2.51 * y + 0.03)) / (y * (2.43 * y + 0.59) + 0.14)) / 0.95;   // /0.95: let recovered whites reach 1.0
	return saturate(lerp(x, y, saturate(x / 0.18)));   // keep the toe linear: no crushed shadows in cockpits/tunnels
}

float3 WhiteBalance(float3 c, float temp, float tint)
{
	float3 m = float3(1.0 + 0.10 * temp, 1.0 - 0.06 * tint, 1.0 - 0.10 * temp);
	m.g += 0.03 * tint;
	return c * m / Luma(m);
}

float LinearDepth(float2 uv)
{
#if PL_DEPTH_UPSIDE_DOWN
	uv.y = 1.0 - uv.y;
#endif
	float d = tex2Dlod(PL_Depth, float4(uv, 0, 0)).x;
#if PL_DEPTH_REVERSED
	d = 1.0 - d;
#endif
	const float N = 1.0;
	return d / (PL_DEPTH_FAR_PLANE - d * (PL_DEPTH_FAR_PLANE - N));
}

float Hash(float2 p)
{
	float3 p3 = frac(float3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return frac((p3.x + p3.y) * p3.z);
}

// 13-tap downsample (Jimenez 2014 layout), soft-weighted to suppress fireflies.
float3 Down13(sampler s, float2 uv, float2 px)
{
	float3 a = tex2D(s, uv + px * float2(-2, -2)).rgb, b = tex2D(s, uv + px * float2(0, -2)).rgb, c = tex2D(s, uv + px * float2(2, -2)).rgb;
	float3 d = tex2D(s, uv + px * float2(-1, -1)).rgb, e = tex2D(s, uv + px * float2(1, -1)).rgb;
	float3 f = tex2D(s, uv + px * float2(-2, 0)).rgb,  g = tex2D(s, uv).rgb,                   h = tex2D(s, uv + px * float2(2, 0)).rgb;
	float3 i = tex2D(s, uv + px * float2(-1, 1)).rgb,  j = tex2D(s, uv + px * float2(1, 1)).rgb;
	float3 k = tex2D(s, uv + px * float2(-2, 2)).rgb,  l = tex2D(s, uv + px * float2(0, 2)).rgb,  m = tex2D(s, uv + px * float2(2, 2)).rgb;
	return (d + e + i + j) * 0.125 + (a + b + f + g) * 0.03125 + (b + c + g + h) * 0.03125 + (f + g + k + l) * 0.03125 + (g + h + l + m) * 0.03125;
}

float3 Tent(sampler s, float2 uv, float2 px)
{
	float3 r = tex2D(s, uv).rgb * 4.0;
	r += (tex2D(s, uv + float2(px.x, 0)).rgb + tex2D(s, uv - float2(px.x, 0)).rgb + tex2D(s, uv + float2(0, px.y)).rgb + tex2D(s, uv - float2(0, px.y)).rgb) * 2.0;
	r += tex2D(s, uv + px).rgb + tex2D(s, uv - px).rgb + tex2D(s, uv + float2(px.x, -px.y)).rgb + tex2D(s, uv + float2(-px.x, px.y)).rgb;
	return r / 16.0;
}

float3 ApplyMix(float3 graded, float3 original, float2 uv)
{
	float3 o = lerp(original, graded, PL_Mix);
	if (PL_SplitView && uv.x < 0.5) o = original;
	return o;
}

// ================================================================= LIGHT
float4 PS_Prefilter(float4 p : SV_Position, float2 uv : TEXCOORD) : SV_Target
{
	float3 c = ToLin(Down13(PL_BackRaw, uv, PL_PX));
	c = InverseTonemap(c, PL_HighlightRecover) * exp2(PL_Exposure);
	float br = max(max(c.r, c.g), c.b);
	float knee = PL_BloomThreshold * 0.5;
	float soft = clamp(br - PL_BloomThreshold + knee, 0.0, 2.0 * knee);
	soft = soft * soft / (4.0 * knee + 1e-4);
	float w = max(soft, br - PL_BloomThreshold) / max(br, 1e-4);
	return float4(min(c * w, 64.0), 1.0);
}
float4 PS_Down4 (float4 p : SV_Position, float2 uv : TEXCOORD) : SV_Target { return float4(Down13(sD2,  uv, PL_PX * 2.0),  1); }
float4 PS_Down8 (float4 p : SV_Position, float2 uv : TEXCOORD) : SV_Target { return float4(Down13(sD4,  uv, PL_PX * 4.0),  1); }
float4 PS_Down16(float4 p : SV_Position, float2 uv : TEXCOORD) : SV_Target { return float4(Down13(sD8,  uv, PL_PX * 8.0),  1); }
float4 PS_Down32(float4 p : SV_Position, float2 uv : TEXCOORD) : SV_Target { return float4(Down13(sD16, uv, PL_PX * 16.0), 1); }
float4 PS_Up16(float4 p : SV_Position, float2 uv : TEXCOORD) : SV_Target { return float4(tex2D(sD16, uv).rgb + Tent(sD32, uv, PL_PX * 32.0), 1); }
float4 PS_Up8 (float4 p : SV_Position, float2 uv : TEXCOORD) : SV_Target { return float4(tex2D(sD8,  uv).rgb + Tent(sU16, uv, PL_PX * 16.0), 1); }
float4 PS_Up4 (float4 p : SV_Position, float2 uv : TEXCOORD) : SV_Target { return float4(tex2D(sD4,  uv).rgb + Tent(sU8,  uv, PL_PX * 8.0),  1); }
float4 PS_Up2 (float4 p : SV_Position, float2 uv : TEXCOORD) : SV_Target { return float4(tex2D(sD2,  uv).rgb + Tent(sU4,  uv, PL_PX * 4.0),  1); }

float4 PS_Light(float4 p : SV_Position, float2 uv : TEXCOORD) : SV_Target
{
	float3 original = Back(uv);
	float3 hdr = InverseTonemap(original, PL_HighlightRecover) * exp2(PL_Exposure);
	hdr = WhiteBalance(hdr, PL_Temperature, PL_Tint);

	float3 bloom = Tent(sU2, uv, PL_PX * 2.0) / 5.0;     // 5 summed octaves
	hdr += bloom * PL_BloomIntensity;
	// Halation: film's red-orange glow around strong lights (night tandems, headlights, sodium lamps).
	float3 wide = tex2D(sU8, uv).rgb / 3.0;
	hdr += wide * float3(1.0, 0.32, 0.12) * PL_Halation * 0.6;

	// Re-tonemap. Mix against a plain clip so the "Filmic" slider keeps AC's own look at 0.
	float3 ldr = lerp(saturate(hdr), Filmic(hdr), PL_FilmicStrength);

	// Grade in log-ish space around mid grey.
	float l = Luma(ldr);
	float3 c = ldr;
	c = (c - 0.18) * (1.0 + PL_Contrast) + 0.18;
	c = max(c - PL_BlackPoint, 0.0) / max(1.0 - PL_BlackPoint, 1e-3);
	float3 split = lerp(PL_ShadowTint, PL_HighlightTint, smoothstep(0.05, 0.6, l)) * 2.0;
	c *= split;
	float sat = max(max(c.r, c.g), c.b) - min(min(c.r, c.g), c.b);
	float lc = Luma(c);
	c = lerp(lc.xxx, c, 1.0 + PL_Saturation + PL_Vibrance * (1.0 - sat));
	return float4(ToGam(ApplyMix(saturate(c), original, uv)), 1.0);
}

// ================================================================= ATMOSPHERE
float4 PS_Atmos(float4 p : SV_Position, float2 uv : TEXCOORD) : SV_Target
{
	float3 c = Back(uv);
	float z = LinearDepth(uv);
	float sky = step(0.999, z);                       // never fog the skybox twice
	float d = saturate((z - PL_HazeStart) / max(1.0 - PL_HazeStart, 1e-3));
	float f = (1.0 - exp(-d * 6.0 * PL_HazeDensity)) * (1.0 - sky);
	float3 aerial = lerp(c, Luma(c).xxx, PL_AerialDesat * f);
	float3 o = lerp(aerial, PL_HazeColor * max(Luma(c), 0.35) * 1.6, f * 0.65);
	return float4(ToGam(ApplyMix(o, c, uv)), 1.0);
}

// ================================================================= DETAIL
float4 PS_LumaQ(float4 p : SV_Position, float2 uv : TEXCOORD) : SV_Target
{
	return Luma(Down13(PL_BackRaw, uv, PL_PX * 2.0)).xxxx;
}
static const float W[5] = { 0.2270270270, 0.1945945946, 0.1216216216, 0.0540540541, 0.0162162162 };
float Gauss9(sampler s, float2 uv, float2 dir)
{
	float r = tex2D(s, uv).x * W[0];
	[unroll] for (int i = 1; i < 5; ++i)
		r += (tex2D(s, uv + dir * i).x + tex2D(s, uv - dir * i).x) * W[i];
	return r;
}
float4 PS_BlurH(float4 p : SV_Position, float2 uv : TEXCOORD) : SV_Target { return Gauss9(sLumaQ,  uv, float2(PL_PX.x * 4.0, 0)).xxxx; }
float4 PS_BlurV(float4 p : SV_Position, float2 uv : TEXCOORD) : SV_Target { return Gauss9(sLumaQb, uv, float2(0, PL_PX.y * 4.0)).xxxx; }

float4 PS_Detail(float4 p : SV_Position, float2 uv : TEXCOORD) : SV_Target
{
	float2 px = PL_PX;
	float3 e = tex2D(PL_BackRaw, uv).rgb;
	float3 b = tex2D(PL_BackRaw, uv + float2(0, -px.y)).rgb, d = tex2D(PL_BackRaw, uv + float2(-px.x, 0)).rgb;
	float3 f = tex2D(PL_BackRaw, uv + float2(px.x, 0)).rgb,  h = tex2D(PL_BackRaw, uv + float2(0, px.y)).rgb;

	// Contrast-adaptive sharpening (original implementation): weight shrinks where local range is already high,
	// so tyre walls, kerbs and signage get crisper without ringing on high-contrast edges.
	float3 mn = min(e, min(min(b, d), min(f, h)));
	float3 mx = max(e, max(max(b, d), max(f, h)));
	float3 amp = saturate(min(mn, 1.0 - mx) / max(mx, 1e-4));
	amp = sqrt(amp);
	float3 w = -amp * lerp(0.125, 0.2, PL_Sharpen);
	float3 sharp = saturate(((b + d + f + h) * w + e) / (1.0 + 4.0 * w));
	float3 c = lerp(e, sharp, PL_Sharpen > 0.0 ? 1.0 : 0.0);

	// Clarity: midtone local contrast against a quarter-res blurred luma, masked off shadows/highlights.
	float l = Luma(c);
	float blur = tex2D(sLumaQ, uv).x;
	float mid = 1.0 - pow(abs(l * 2.0 - 1.0), 2.0);
	c *= 1.0 + (l - blur) * PL_Clarity * 2.0 * mid / max(l, 1e-3);
	return float4(ApplyMix(saturate(c), e, uv), 1.0);
}

// ================================================================= LENS
float4 PS_Lens(float4 p : SV_Position, float2 uv : TEXCOORD) : SV_Target
{
	float2 cen = uv - 0.5;
	float r2 = dot(cen * float2(PL_ASPECT, 1.0), cen * float2(PL_ASPECT, 1.0));
	float2 off = cen * r2 * PL_ChromaAb * 0.012;
	float3 o = Back(uv);
	float3 c = float3(Back(uv - off).r, o.g, Back(uv + off).b);

	// Natural (cos^4) vignette.
	float ct = rsqrt(1.0 + r2 * PL_Vignette * 1.6);
	c *= lerp(1.0, ct * ct * ct * ct, PL_Vignette);

	// Grain strongest in midtones, temporally animated, applied in display space.
	c = ToGam(c); o = ToGam(o);
	float n = Hash(p.xy + frac(PL_Timer * 0.001) * 1013.0) + Hash(p.yx * 1.37 + PL_Frame % 64) - 1.0;
	float l = Luma(c);
	c += n * PL_Grain * 0.06 * (1.0 - abs(l * 2.0 - 1.0)) * (l + 0.05);
	return float4(ApplyMix(saturate(c), o, uv), 1.0);
}

// ================================================================= TECHNIQUES
technique Photolap_Light < ui_label = "PHOTOLAP | Light (HDR bloom, filmic, grade)"; ui_tooltip = "Run first."; >
{
	pass { VertexShader = PostProcessVS; PixelShader = PS_Prefilter; RenderTarget = PL_D2; }
	pass { VertexShader = PostProcessVS; PixelShader = PS_Down4;  RenderTarget = PL_D4; }
	pass { VertexShader = PostProcessVS; PixelShader = PS_Down8;  RenderTarget = PL_D8; }
	pass { VertexShader = PostProcessVS; PixelShader = PS_Down16; RenderTarget = PL_D16; }
	pass { VertexShader = PostProcessVS; PixelShader = PS_Down32; RenderTarget = PL_D32; }
	pass { VertexShader = PostProcessVS; PixelShader = PS_Up16;   RenderTarget = PL_U16; }
	pass { VertexShader = PostProcessVS; PixelShader = PS_Up8;    RenderTarget = PL_U8; }
	pass { VertexShader = PostProcessVS; PixelShader = PS_Up4;    RenderTarget = PL_U4; }
	pass { VertexShader = PostProcessVS; PixelShader = PS_Up2;    RenderTarget = PL_U2; }
	pass { VertexShader = PostProcessVS; PixelShader = PS_Light;  }
}

technique Photolap_Atmos < ui_label = "PHOTOLAP | Atmosphere (depth haze)"; >
{
	pass { VertexShader = PostProcessVS; PixelShader = PS_Atmos; }
}

technique Photolap_Detail < ui_label = "PHOTOLAP | Detail (clarity + adaptive sharpen)"; >
{
	pass { VertexShader = PostProcessVS; PixelShader = PS_LumaQ; RenderTarget = PL_LumaQ; }
	pass { VertexShader = PostProcessVS; PixelShader = PS_BlurH; RenderTarget = PL_LumaQb; }
	pass { VertexShader = PostProcessVS; PixelShader = PS_BlurV; RenderTarget = PL_LumaQ; }
	pass { VertexShader = PostProcessVS; PixelShader = PS_Detail; }
}

technique Photolap_Lens < ui_label = "PHOTOLAP | Lens (CA, vignette, grain)"; ui_tooltip = "Run last."; >
{
	pass { VertexShader = PostProcessVS; PixelShader = PS_Lens; }
}
