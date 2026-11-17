# Research: the Assetto Corsa graphics stack, and where DLSS 5 fits

## 1. The stack, bottom to top

**Assetto Corsa (Kunos, 2014).** A 64-bit DirectX 11 game. Its original post-processing is YEBIS, and the engine has no upscaler or motion vectors of its own.

**Content Manager (CM).** The launcher almost everyone uses. It handles cars and tracks, online server browsing (No Hesi and others connect through it) and CSP settings. It launches `acs.exe` with the session config. It does not render anything, so an in-game overlay has to live inside the game process, not in CM.

**Custom Shaders Patch (CSP, by x4fab / Ilja Jusupov).** Loads as `dwrite.dll` and replaces most of AC's renderer: lighting, shadows, reflections, weather (Pure / Sol), post-processing and VR. Two parts matter here:
- **Upscalers.** CSP 0.3.0 Preview 338 and later integrate NVIDIA DLSS (SR / DLAA) and FSR, configured in CM under Settings → Custom Shaders Patch. The runtime is `nvngx_dlss.dll` under `extension/internal/`. CSP hands NGX **real engine motion vectors and depth**, which estimated-motion injectors can't match.
- **Lua apps** (`apps/lua/<name>/manifest.ini` + script). These draw ImGui windows in-game in every session type, online included. Photolap's in-game panel is one. CSP also has Lua post-processing filters (`ac_pp_filters`); see the roadmap below.

**ReShade 6 (add-on build).** Installed as `dxgi.dll` next to `acs.exe`. It runs `.fx` effects and hosts native **add-ons** (`.addon64`) through an event API (draw calls, render-target binds, present, overlay). One add-on API call, `effect_runtime::render_effects()`, renders effects mid-frame and stops them rendering again at present. That is how Photolap keeps the HUD clean.

**DLSS 5 (NVIDIA, announced at GTC on 16 March 2026).** A real-time neural rendering model. It takes colour and motion vectors each frame and adds photoreal lighting and materials on top. It is officially for RTX 50, through NVIDIA Streamline/NGX in titles that integrate it. AC isn't one of them, so the community bridges it in.

## 2. RHI

**RHI** is RankFTW's installer (`RankFTW/RHI`) together with its distribution repo `RankFTW/rhi-repo`. That repo hosts the pieces the DLSS 5 community tools download:
- `renodx-dlss5-*`: the **RenoDX DLSS 5 add-on** (Krish), a closed-source ReShade add-on that runs the neural pass by hooking a game's NGX DLSS calls. From v10 it exports a live-control API (`RenoDX_NR_GetControlApi`), which Photolap uses.
- `dlssnr-*`: `nvngx_dlssnr.dll`, the DLSS 5 neural-rendering model. DLSS5oneclick describes these builds as leaked and community-distributed, and some tags are patched builds.
- `dlss-*`: NVIDIA DLSS SR runtimes.

## 3. The four projects

| Repo | What it is | Licence | Role in Photolap |
|---|---|---|---|
| **jlrouzies-fr/DLSS5-Feeder** | ReShade add-on (C++) that *creates* a DLSS session for games without DLSS. It estimates motion vectors in a shader, feeds NGX, and has an Alt+C ImGui panel that drives RenoDX / OptiScaler | MIT | **Code integrated:** the RenoDX live-control interface (`addon/src/renodx_bridge.hpp` is adapted from `feed_renodx_api.h`). Its panel design and HUD/overlay techniques informed ours. Its estimated-MV path is **not needed for AC**, because CSP provides real DLSS. |
| **faisalkindi/DLSS5oneclick** | Rust GUI that picks and installs the right DLSS 5 setup per game (ReShade + RenoDX + model, with fallbacks), detects the API, and keeps builds updated | MIT | Its decision logic confirms the AC path: AC (with CSP) "ships its own DLSS", so the setup is ReShade + RenoDX DLSS 5 add-on, with no Feeder. Our installer follows the same ReShade setup-zip extraction approach. |
| **Merserk/dlss5-visual-enhancer** | Qt/QML desktop app for *offline* image and video enhancement (DLSS 5 "Neuroframe", RTX Video, FSR/DLSS FG, ReShade, NIS/CAS) | Merserk Source License (all rights reserved) | Not a real-time in-game path. It is useful for **marketing**, as a before/after renderer for screenshots and clips. Kept as a submodule reference only. |
| **NODIX-TECH/DLSS-5-MANAGER** | F#/Avalonia manager and one-click installer for DLSS 5 / ReShade / OptiScaler, with obfuscated build tooling | Copyright NODIX-TECH (all rights reserved) | Generic installer UI with nothing AC-specific. Kept as a submodule reference. Its UX ideas could feed a future CM-side companion. |

Other confirmed facts:
- **Deep Fried Chicken / dlss5-dx11-bridge** (vendored inside DLSS5-Feeder) lists **Assetto Corsa with CSP Preview 338+** as confirmed working. It replays CSP's D3D11 DLSS calls on a private D3D12 device for the neural pass. This is the first proof that the AC neural path works.
- Feeder's compatibility matrix: neural-pass stability depends on the **driver × NGX runtime × consumer build** combination (e.g. renodx-dlss5 v6.1+ on driver 617.14 passed 300/300; v4.6/4.7 faulted on 616.64+). Photolap's status footer reports the backend, so users can tell which combination they are on.

## 4. Decisions

1. **Use CSP's DLSS as the neural pass's input. Don't estimate motion.** Real engine MVs and depth beat any shader estimator, and they cost nothing extra.
2. **In-game UI as a CSP Lua app.** It shows in every CM-launched session, including No Hesi, gets a native AC look and apps-bar entry, and has rebindable hotkeys through `ac.ControlButton`. The add-on's ReShade panel is the fallback.
3. **IPC through two small INI files**, polled at about 150 ms with an atomic temp-and-rename write. That is far simpler and more robust than shared memory across the Lua sandbox, and it can't crash the game.
4. **Our own post stack in one standalone `.fx`.** It has no ReShade.fxh dependency, uses manual sRGB so it renders correctly mid-frame on AC's UNORM back buffer, and keeps every parameter live-controllable.
5. **Ship no NVIDIA binaries.** See `NEURAL-SETUP.md` and `COMMERCIAL.md`.

## 5. Roadmap

- **v0.2, live validation.** Calibrate HUD-safe on current CSP builds, set depth orientation defaults, check the CSP window name, and add a performance HUD.
- **v0.3, "Photolap Native".** Port Light / Atmosphere / Detail / Lens to a **CSP Lua post-processing filter** (`ac_pp_filters` + `ui.renderShader`). That removes the ReShade dependency for the non-neural stack, works wherever CSP works (including VR), and can read CSP's own HDR buffer before tonemapping, which beats inverse-tonemapping the LDR frame.
- **v0.4.** Per-track and per-time-of-day auto presets driven by CSP's weather and sun API, wet-road and rain tuning, and a night-highway profile for No Hesi.
