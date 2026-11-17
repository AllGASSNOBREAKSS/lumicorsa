# Architecture

Pitwall is one CSP Lua app in `app/Pitwall`. It uses no ReShade and no DLL.

```
Pitwall.lua         window (header, nav rail, page, footer), presets, state, hotkeys, HUD hook
src/pipeline.lua    render targets and the shader pass graph; upscaler / other-app / GPU-time probes
src/settings.lua    bridge to CSP module configs, AC video.ini, audio, weather time, Pure; CSP schema parser
src/pages.lua       the ten pages as declarative cards and rows
src/ui_kit.lua      glass background, Space Grotesk text, widgets (toggle, slider, choice, buttons, info, note)
shaders/*.hlsl      pixel shaders; CSP compiles them at runtime inside its UI shader template
fonts/, icon.png
```

## Drawing the look

`ui.onExclusiveHUD` is the first UI callback of the frame. Pitwall renders its offscreen passes there into
`ui.ExtraCanvas` targets (RGBA16F), then draws one fullscreen opaque `ui.renderShader`. That lands after the finished
scene (CSP post-processing and upscaler included) and before AC's HUD and every app window. Inputs are
`dynamic::screen` and `dynamic::depth`. Bypassed means nothing is drawn at all.

| Pass | Shader | Size | Runs when |
|---|---|---|---|
| Neural ×4 | `nn_0..3` | full | Neural on |
| Depth probe | `depth_probe` | 1×1 | haze, AO, shafts or DoF on |
| Bloom prefilter, down ×4, up ×4 | `bloom_*` | 1/2 … 1/32 | Light on with bloom or halation |
| Lens flare | `flare` | 1/4 | Light + flare on |
| Sun shafts ×2 | `shafts_mask`, `shafts_blur` | 1/2 | Light + shafts on and the sun is on screen |
| Contact AO + blur | `ao`, `blur9` | 1/2 | AO on |
| Clarity | `luma_quarter`, `blur9` | 1/4 | Detail + clarity on |
| DoF background | `color_quarter`, `blur9c` | 1/4 | DoF on (always / replays) |
| Final | `final` | screen | engaged |

The final pass runs Detail, then DoF, then lens CA. In linear light it applies AO, then Light (inverse tonemap,
exposure, white balance, bloom, halation, shafts, flare, filmic, grade), then haze. Last come vignette, grain,
and the mix/split.

- **Depth.** The probe picks the depth convention (standard or reversed) on the GPU. Distances are metres from
  `cameraClipNear/Far`.
- **AO.** Uses depth only, with pairs of opposite samples in inverse depth. Inverse depth is linear across any plane,
  so roads and walls at a grazing angle don't turn grey; only creases darken.
- **Neural.** Anime4K Restore CNN Soft (S), about 1,000 MIT weights, converted by `tools/anime4k_to_hlsl.py`. On game
  frames the net's residual is an edge-aware smoothing step, so Pitwall subtracts it as a learned unsharp mask
  (gain = intensity × 3.5, per-pixel clamp).
- **Other grading apps.** Dream Realism and ExilitayFX are detected through `ac.getAppWindows()`. Pitwall stays on top
  but drops its inverse tonemap and filmic curve.

## Settings bridge

| Source | API | When it applies |
|---|---|---|
| CSP modules (`cfg/extension/<module>.ini`) | `ac.INIConfig.cspModule(id)`, `:setAndSave()` | live (CSP reloads the module), or restart where marked |
| Control types | parsed from `extension/config/<module>.ini`, CSP's schema (same as CM) | — |
| AC video settings (`cfg/video.ini`) | `ac.INIConfig.videoConfig()` | next launch |
| Audio | `ac.getAudioVolume` / `ac.setAudioVolume` | live, saved once a slider settles |
| Time of day / speed | `ac.setWeatherTimeOffset` / `ac.setWeatherTimeMultiplier` | live, offline only |
| Field of view | `ac.setFirstPersonCameraFOV` | live |
| Pure | WeatherFX config, style options in `cfg/extension/state/lua/wfx_impl/<style>__settings.ini`, Pure's own app windows | live, or on weather reload |

- **Debounced writes.** Slider writes wait until the value has been still for about 0.35 s, so a drag doesn't make CSP
  reload a module every frame.
- **Staying in sync with CM.** `ac.onCSPConfigChanged` and `ac.onFileChanged` drop cached configs, so CM edits show up
  in Pitwall.

## UI

The window is a portrait 540×900, with no title bar, no IMGUI background and no scrollbar. `glass.hlsl` blurs the frame
behind the window, tints it and adds a sheen, a hairline border and rounded corners. All text is DWrite
Space Grotesk. Pages scroll with the mouse wheel when they overflow, and rows outside the view are neither drawn nor
clickable. A ten-item nav rail (icons in blue, orange, yellow, green and red) switches pages. Graphics and Effects have
section switches, so every page fits without scrolling at the default size.

## Checks

- `tools/hlslcheck.py` compiles every shader with `d3dcompiler_47` against a stub of CSP's template, built from each
  file's `// @textures` / `// @values` header.
- `tools/lua_mock_test.lua` runs the whole app under LuaJIT with a stubbed CSP. It checks every pass against its
  shader header and every toggle's pass graph, clicks every control on every page, and confirms where each write lands.
- `tools/check_consistency.py` checks that panel keys match `final.hlsl`, that every shader is used, and that the
  fonts and icon ship.
