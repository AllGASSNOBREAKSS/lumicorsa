# Architecture

## Frame timeline (one AC frame with Photolap)

1. CSP renders the 3D scene into its HDR targets.
2. **CSP DLSS (SR/DLAA)** runs with engine motion vectors and depth. If a neural backend (renodx-dlss5 or Deep Fried Chicken) is loaded, it hooks this NGX evaluate and runs the **DLSS 5 neural pass** on the result.
3. CSP's final composite draws to the back buffer. This is the first draw on the back buffer.
4. **HUD-safe point.** Before the next back-buffer draw, `photolap.addon64` calls `effect_runtime::render_effects()`, which runs `Photolap_Light → Atmos → Detail → Lens`. ReShade then skips its usual present-time pass for that frame.
5. AC and CSP draw the UI: apps, chat, leaderboards and the Photolap panel. The UI never goes through the effects.
6. Present.

`hud_draw_index` (Advanced → Compatibility) picks which back-buffer draw the effects go before. The default is 1. If a CSP build splits its composite into more draws, raise it. If the hook never fires, the add-on falls back to normal present-time rendering, and the footer shows `HUD-safe: fallback`.

## Control flow

```
CSP app (Lua) ──io.save──► apps/lua/Photolap/state/control.ini ──poll 150ms──► photolap.addon64
                                                                              ├─ set_technique_state(Photolap_*)
                                                                              ├─ set_uniform_value_*(PL_*)
                                                                              └─ RenoDX_NR_GetControlApi(1)->set(NR*)
photolap.addon64 ──every 500ms──► state/status.ini ──poll 500ms──► CSP app footer
```

- Writes go to a temp file, then `MoveFileEx(REPLACE_EXISTING)`, so the reader never sees a half-written file.
- `writer=app|addon` plus `seq` lets either panel be the last editor. The Lua app adopts edits made in the ReShade fallback panel.
- Any `PL_*` key is applied generically to the uniform of the same name. A new shader parameter needs only a slider in the app.

## Neural controls

RenoDX 10.x accepts only some keys at runtime. Photolap maps them like this:

| Panel | RenoDX key | Live? |
|---|---|---|
| Neural pass on/off | `NRIntensity` = 0 when off (`NeuralUplift` is start-time only) | yes |
| Intensity | `NRIntensity` | yes |
| Style / preset | `NRStyle`, `NRPreset` | yes |
| Tone / Structure | `NRLocalTone`, `NRLocalStructure` | yes |
| Keep HUD | `NRUICorrection` | yes |
| Character mask | `NRAutoMask` forced 0 (no characters to mask in a car sim) | yes |

## Shader notes (`Photolap.fx`)

- **Manual sRGB** (`ToLin`/`ToGam`) instead of `SRGBTexture`/`SRGBWriteEnable`. AC's back buffer is `R8G8B8A8_UNORM` and isn't typeless, so you can't create an sRGB view of it mid-frame. Doing the conversion by hand keeps both render paths identical.
- **Inverse tonemap.** It rebuilds scene-referred highlights from the LDR frame, peak-weighted so mid-tones are untouched (0.18 → 0.181).
- **Filmic.** It uses the Narkowicz ACES fit, scaled so scene mid-grey maps to about 0.18, normalised so whites reach 1.0, and blended linear in the toe so cockpits and tunnels don't crush.
- **Bloom.** A 13-tap Jimenez downsample over 5 octaves (½ to 1/32) with tent upsampling and a soft-knee threshold. **Halation** is a red-orange tint taken from the wide octave.
- **Atmosphere.** Linearised depth, exponential haze, aerial desaturation, with the skybox masked (`z ≥ 0.999`).
- **Detail.** A contrast-adaptive sharpen (original implementation) plus midtone clarity against a quarter-resolution Gaussian luma.
- **Cost.** Every technique can be switched off on its own. The Performance preset disables Atmosphere and Lens and the neural pass.
