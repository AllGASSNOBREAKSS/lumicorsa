# Lumicorsa architecture

One CSP Lua app, `app/Lumicorsa`, built and checked against CSP 0.3.0-preview728 (build 4263).

```
Lumicorsa.lua        entry: registry, hotkeys, per-frame work (ui.onExclusiveHUD), the two windows, modals
manifest.ini         windows "Lumicorsa" (dashboard) and "Lumicorsa HUD" (cluster)
backend/registry     every control: get, set, readback (from the real source), apply, raw key, lock reason
backend/config       CSP module configs, video.ini, controls.ini, style options; CSP schema parser; 250 ms debounce
backend/state        app state, look values, presets, blender, auto look; Look/Light/Visibility controls
backend/look         shader pipeline (look), glass backdrop
backend/camera       chase cam (live chase_cam.ini edits, per car), FOV, seat, Neck FX head movement, replay camera
backend/weather      time of day / speed (offline), windscreen
backend/graphics     tiers, upscaler, reflections, shadows, world, frame cap
backend/drive        FFB, assists, steering lock
backend/audio        AC volume channels and mixes
backend/sky          Pure/Sol detection, planners, sky quality
backend/system       ReShade (optional), profiles, GPU budget, screenshots, replay motion blur
backend/telemetry    measured numbers only (dt, CPU load, VRAM, GPU frame time, measured effect costs)
backend/verify       self-test, proof screenshots, online soak, unattended autorun
ui/                  theme, widgets, dashboard, tabs, palette, quick ring
hud/                 cluster.lua + cluster_assets (PNG layers pre-rendered from the design SVG); drawn in the first UI
                     callback every game frame, at the HUD window's position (the window is only a drag handle)
shaders/             HLSL
```

## Rules the code follows

- **Every control is a registry entry**, with a readback from where the value really lives: the config file on disk, a CSP API getter, the values the shader received on the last frame, or what the cluster drew. The self-test sets, reads back and restores each one. A control with no API isn't in the app.
- **SDK gate:** `tools/sdk_check.py` fails if the app calls an `ac.*`, `ui.*`, `render.*`, `physics.*`, `web.*` or `io.*` function that isn't in CSP's SDK for build 4263. The names are in `tools/sdk_names_csp4263.txt`, generated from the SDK CSP ships with that build. The public acc-lua-sdk repo is incomplete for core `ui.*` functions.
- **Nothing per frame on disk:** canvases are created once per resolution. Fonts are DWrite strings cached by CSP. Slider writes wait 250 ms after the last change.
- **No popping:** preset changes crossfade over 1.5 s; sun shafts fade over 0.6 s; the depth direction is a latched
  decision voted by sky pixels; an effect whose shader is still compiling stays off instead of feeding a stale texture.
- **Glass:** one quarter-res, two-pass blur of the frame per UI frame, drawn once per window with `ui.drawImageRounded`.
- **Honest stats:** frame rate, frame time, 1% low and the histogram come from `dt`. CPU load is `cpuOccupancy`, VRAM is `ac.getVRAMConsumption`, and GPU frame time is `ac.getPerformanceCPUAndGPUTime`. Lua has no GPU-load getter, so there's no GPU donut. Effect costs come from System › Measure effect costs, which switches each group off for 1.5 s and records the GPU frame-time drop.

## Design controls removed or relabelled (no API, or the API means something else)

| Design control | What happened | Why |
|---|---|---|
| Look › Car paint (clear-coat, flake, dust) | removed | CSP material edits are per-shader uniforms that differ per car; one slider can't apply correctly to every car |
| Light › Headlights reach, colour temperature | removed | headlight range and colour come from each car's config; there's no global setting |
| Light › Night city (lamps and signs, wet streaks) | removed | no global emissive multiplier or wet-streak setting in CSP |
| Light › Interior (dashboard backlight, cabin shadows) | removed | car-defined; no global setting |
| Light › Windscreen sun glare | relabelled "Windscreen reflections" | the closest real setting is Windscreen FX reflections |
| Light › AO "GTAO" | options are Off / SSAO / ASSAO / HBAO | those are CSP's AO methods |
| Light › Bloom and glare › Glare | kept, applies next launch | AC's YEBIS glare level in video.ini |
| Weather › Conditions (type, air temperature) | removed | apps can't set the weather; the WeatherFX controller owns it |
| Weather › Rain (rain, wetness, puddles) | removed | same: apps can't set rain or wetness |
| Weather › Online › Follow server weather | removed (it was a do-nothing toggle) | online, time controls lock with "Server controls weather" |
| Graphics › Pick tier for my GPU (20 s test) | removed | tiers partly apply at launch, so testing them needs restarts; the curve shows measured fps per tier instead |
| Graphics › Frame pacing | removed | no frame-pacing setting in CSP |
| Camera › Chase side offset, follow lag, roll | removed | chase_cam.ini has only distance, height and pitch |
| Camera › Chase field of view | removed | no chase-camera FOV setting for apps |
| Drive › Damper | relabelled "Lock damper" | CSP's only damper is the soft-lock damper |
| Drive › Gyroscopic effect (slider) | toggle | CSP exposes gyro as on/off; its strength key is hidden |
| Drive › Calibrate wheel and pedals | removed | calibration lives in Content Manager; no API |
| Audio › Turbo | relabelled "Components" | AC has no turbo channel; "car components" is the real one |
| Audio › Space (reverb, Doppler) | removed | no Doppler setting; `ac.setReverbValue` has no getter or documented range |
| Sky › Detected (segmented) | shown as information | detection isn't a choice |
| Sky › Sun size | removed | not exposed by Pure or Sol config |
| Sky › Sol Planner | only shown when Sol Planner is installed | |
| Photo › Open photo mode | replaced by "Take screenshot" (`ac.makeScreenshot`) | CSP ships no photo-mode app |
| Photo › Shutter angle | removed | duplicate of motion-blur amount; no separate setting |
| Photo › Screenshot size 4K / 8K | Native / 2× / 4× | Nice Screenshots resolution multiplier |
| System › Load ReShade presets | removed | Lua can't drive ReShade |
| System › Hotkey pickers | replaced by a list | hotkeys are rebound in CSP › Controls (ac.ControlButton) |
| Quick ring › Rain | "Rain look" (Rain run preset) | apps can't make it rain |
| Quick ring › Photo mode | "Free camera" (F7) | no photo-mode app |
| Stats rail › GPU % donut | removed | not readable from Lua |

## Settings that need a restart or apply later

- **AC restart (CSP):** upscaler and quality (`graphics_adjustments [FSR]`).
- **Next launch (`video.ini`):** quality tier (partly), cubemap resolution, faces per frame, shadow resolution, mirror resolution, glare. The frame cap applies now through `ac.applyRenderingLimits` and is saved for next launch.
- **Next session (`controls.ini`):** FFB minimum force, kerb rumble, road texture, steering lock.
- **Restart AC after installing or removing ReShade.**
- Everything else applies live.
