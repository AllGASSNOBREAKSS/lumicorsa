# Architecture (v0.2, native CSP)

Photolap is one CSP Lua app: `csp-app/Photolap`. It runs no ReShade, loads no DLL and exchanges no files with another process.

```
Photolap.lua      panel (presets, toggles, sliders, status), hotkeys, persistence (ac.storage)
pl_pipeline.lua   render targets, pass graph, environment probes (upscaler, other PP apps, GPU time)
shaders/*.hlsl    pixel shaders; CSP compiles them at runtime inside its UI shader template
```

## Frame timeline

1. CSP renders the scene, runs its HDR post-processing (YEBIS or the WeatherFX style's own, e.g. Pure), then the upscaler (DLSS / FSR / XeSS if enabled). The result is the LDR frame CSP exposes as `dynamic::screen`, plus `dynamic::depth`.
2. **`ui.onExclusiveHUD`** fires. It's the first UI callback of the frame, so Photolap runs here:
   - offscreen passes into `ui.ExtraCanvas` targets (RGBA16F) through `canvas:updateWithShader()`;
   - one fullscreen `ui.renderShader()` (opaque) that writes the graded frame over the screen.
3. AC's HUD, chat, leaderboards and every app window, the Photolap panel included, draw on top, ungraded.

When the panel is BYPASSED, the callback returns without drawing anything, so the vanilla image is back in the same frame.

## Pass graph

| Pass | Shader | Size | Runs when |
|---|---|---|---|
| Neural layer 0..3 | `nn_0..3.hlsl` | full | Neural on and intensity > 0 |
| Bloom prefilter | `bloom_prefilter.hlsl` | 1/2 | Light on and (bloom or halation > 0) |
| Bloom down ×4 | `bloom_down.hlsl` | 1/4 … 1/32 | same |
| Bloom up ×4 | `bloom_up.hlsl` | 1/16 … 1/2 | same |
| Clarity luma + blur H/V | `luma_quarter.hlsl`, `blur9.hlsl` | 1/4 | Detail on and clarity > 0 |
| Depth probe | `depth_probe.hlsl` | 1×1 | Atmosphere on |
| Final composite | `final.hlsl` | screen | always (when engaged) |

With everything on, that's 17 offscreen passes plus the final one. All but the neural layers run at reduced resolution.

`final.hlsl`, per pixel: **Detail** (contrast-adaptive sharpen + clarity) → **Lens CA** (offsets R and B before the "sensor") → **Light** (inverse tonemap, exposure, white balance, bloom + halation, filmic, grade) → **Atmosphere** (haze) → **vignette + grain** → **Mix** against the original. The split view returns the original frame on the left half, with a divider line.

## Photolap Neural

Four 3×3 convolution layers with CReLU between them, taken unchanged from Anime4K v4 *Restore CNN Soft (S)* (MIT). That's about 1,000 weights. `tools/anime4k_to_hlsl.py` converts the GLSL: GLSL `mat4(a0..a15) * v` fills columns, which is HLSL `mul(v, float4x4(a0..a15))` filling rows, so weights are copied in file order. Each layer reads one RGBA16F target and writes the next.

On game frames the restore net's residual is a small, edge-aware smoothing step. Photolap applies it in reverse as a learned unsharp mask: `out = in − clamp(gain · residual, ±0.12)`, with gain = intensity × 3.5. Detail rises where the network sees structure, and the clamp keeps halos down. The checks behind this are in `RESEARCH.md` §6.

## Depth and haze

`dynamic::depth` is non-linear. The 1×1 probe averages the raw depth over an 8×8 grid. With standard depth almost every pixel is above 0.5 (anything beyond twice the near plane), and with reversed depth almost every pixel is below it, so the final pass picks the right convention by itself. With `zz` defined as 0 at the far plane for both conventions, distance in metres is `n·f / (n + zz·(f − n))`, using `cameraClipNear/Far` from `ac.getSim()`. The skybox (`zz ≈ 0`) is never hazed.

## Coexisting with other post-processing apps

Apps such as Dream Realism change CSP's own HDR pipeline (exposure, bloom, tonemapping) and add PNG overlays, so their look is already in `dynamic::screen`. Photolap sits on top of that. When one is detected (`ac.getAppWindows()`), Photolap drops its inverse tonemap and filmic curve, the parts that would tonemap a second time, and lowers the bloom threshold to match. Detail, grade, haze and lens still apply. *Advanced › Compatibility* overrides this.

## Status read-back

- **Shaders:** `running` once every pass has compiled and drawn (passes compile asynchronously on first use, shown as `compiling…`).
- **GPU cost:** the smoothed GPU frame time from `ac.getPerformanceCPUAndGPUTime()` while engaged, minus the same while bypassed.
- **Upscaler:** CSP's `[FSR] ACTIVE / OLD_IMPLEMENTATION` from the Graphics adjustments config, combined with `upscaleAppliedFactor` and `isTAAActive` from `ac.getSim()`.

## Checks

- `tools/hlslcheck.py`: compiles every shader with `d3dcompiler_47` (ps_5_0) against a stub of CSP's template, built from each file's `// @textures` and `// @values` header. A shader that fails to compile in game halts the Lua script, so this runs in CI on Windows.
- `tools/lua_mock_test.lua`: runs the app under LuaJIT with a stubbed CSP API, checks every pass's bound textures and values against the shader header (names and types), and flips every toggle.
- `tools/check_consistency.py`: panel keys ⊆ `final.hlsl` values ⊆ legacy `Photolap.fx` uniforms, and every shader is loaded.

## Legacy ReShade path

`legacy/reshade` keeps the v0.1 `Photolap.fx` + `photolap.addon64` and their installer. They're optional and never installed by default. The 0.2 panel doesn't drive them, so on that path the effects are tuned in ReShade's overlay.
