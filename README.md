<p align="center"><img src="docs/img/icon.png" width="96"></p>

<h1 align="center">PHOTOLAP</h1>
<p align="center"><b>Neural photoreal for Assetto Corsa.</b><br>
DLSS 5 neural rendering + an HDR light / atmosphere / detail / lens stack, controlled live from an in-game panel,<br>
in any session you launch from Content Manager: No Hesi, other online servers, practice, replays.</p>

---

## What it does

| Layer | What you get | Needs |
|---|---|---|
| **Neural** (DLSS 5 neural rendering) | NVIDIA's generative lighting/material pass on top of CSP's DLSS, with intensity, style, tone and structure adjustable live | RTX 50, CSP Preview 338+ with DLSS on, a DLSS 5 neural backend ([Neural setup](docs/NEURAL-SETUP.md)) |
| **Light** | Highlight recovery from the LDR frame, 5-octave HDR bloom, film halation around headlights and street lamps, filmic re-tonemap, split-tone grade | any GPU |
| **Atmosphere** | Depth-aware aerial perspective: distance haze and desaturation that leave the sky alone | any GPU, ReShade depth |
| **Detail** | Midtone clarity plus contrast-adaptive sharpening that keeps tyre walls, kerbs and signage crisp without halos | any GPU |
| **Lens** | Radial chromatic aberration, natural cos⁴ vignette, luma-aware animated grain | any GPU |
| **HUD-safe** | Effects render after CSP's final composite and before the UI, so apps, chat, leaderboards and the panel itself stay untouched | ReShade 6 add-on build |

Presets: **Photoreal** · **Midnight Run** (night highway / tandem) · **Golden Hour** · **Broadcast** · **Performance**.

## In game


- **Alt+P** opens the Photolap window (it is also in the CSP apps bar on the right edge). Both keys can be rebound in CSP controls.
- **Alt+O** bypasses everything instantly, for A/B checks while driving.
- **Alt+Shift+P** opens the fallback panel, drawn by ReShade. Use it if a server blocks Lua apps.
- The status footer shows what is actually running (add-on, effects, neural backend, HUD-safe), read back from the add-on.

## Install

1. Install **Content Manager** and **Custom Shaders Patch** (Preview 338 or newer for DLSS).
2. In CM, go to **Settings → Custom Shaders Patch → Upscaler** and pick **NVIDIA DLSS** (DLAA or Quality). Turn CSP's own TAA off.
3. Download the release zip and run `Install.bat`. It finds AC through your Steam libraries, installs ReShade (add-on build, from reshade.me) as `dxgi.dll` if you don't have it, and copies the shader, add-on, in-game app and preset. Re-running is safe, and `Install.bat -Uninstall` removes only what it placed.
4. Optional: set up the neural pass by following [docs/NEURAL-SETUP.md](docs/NEURAL-SETUP.md).

## How it fits together

```
 Content Manager ──launches──► acs.exe + CSP (DLSS SR/DLAA: real motion vectors + depth)
                                   │
            ┌──────────────────────┼─────────────────────────────────────────────┐
            │ ReShade 6 (dxgi.dll) │                                             │
            │   renodx-dlss5 / DFC ◄── hooks CSP's NGX DLSS calls → DLSS 5 neural pass
            │   photolap.addon64   ── HUD-safe render point, live control, status │
            │   Photolap.fx        ── Light → Atmosphere → Detail → Lens          │
            └──────────▲───────────────────────────────┬────────────────────────┘
                       │ state/control.ini (≈150 ms)   │ state/status.ini
            ┌──────────┴───────────────────────────────▼────────────────────────┐
            │ CSP Lua app "Photolap": the in-game panel (presets, toggles, sliders)│
            └────────────────────────────────────────────────────────────────────┘
```

Details are in [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md). The research behind the decisions (AC, CM, CSP, ReShade, RHI, and the four DLSS 5 community projects) is in [docs/RESEARCH.md](docs/RESEARCH.md).

## Repository

```
shaders/Photolap.fx           ReShade FX: 4 techniques, 27 live uniforms (PL_*), standalone
addon/src/                    photolap.addon64: control bridge, HUD-safe hook, RenoDX live API, fallback panel
csp-app/Photolap/             CSP Lua app: the in-game panel
installer/                    Install-Photolap.ps1 (readable, no exe) + Install.bat
tools/fxcheck/                compiles Photolap.fx with ReShade's own compiler (HLSL SM5 + SPIR-V) on Linux
tools/lua_mock_test.lua       runs the CSP app under LuaJIT with a stubbed CSP API
tools/check_consistency.py    stops shader / app / add-on from drifting apart
vendor/                       the four community DLSS 5 projects, as submodules
```

## Build

```bash
# Linux / CI: shader compile check, Lua app test, consistency check, cross-built add-on
make all            # needs g++, mingw-w64, luajit, and ReShade source at ../ref/reshade-src (see .github/workflows/ci.yml)
```
For Windows release builds, run `addon\build.bat` (MSVC, CMake). It writes `bin\photolap.addon64`.

## Status: what is verified and what is not

| | |
|---|---|
| ✅ | `Photolap.fx` compiles with ReShade's effect compiler for D3D11 (HLSL SM5) and SPIR-V at 1080p, 1440p and 4K |
| ✅ | The add-on builds as a valid x64 PE add-on (exports `NAME`/`DESCRIPTION`, imports only kernel32/msvcrt; ImGui goes through ReShade's function table) |
| ✅ | The CSP app runs under a stubbed CSP API: every button path, both hotkeys, and the IPC write |
| ✅ | Shader uniforms, app presets and add-on keys are cross-checked in CI |
| ⏳ | **Not yet tested in a live AC session.** Next steps: the HUD-safe draw index on current CSP, the depth orientation (`PL_DEPTH_REVERSED`), and the CSP window name used by the Alt+P toggle |
| ⏳ | Neural pass with CSP DLSS + renodx-dlss5 on an RTX 50 |

## Legal

- Photolap's own code is MIT. Third-party notices are in [THIRD-PARTY-NOTICES.md](THIRD-PARTY-NOTICES.md).
- **DLSS** and **NVIDIA** are NVIDIA trademarks. Photolap is not affiliated with NVIDIA, Kunos or the CSP authors.
- Photolap **does not ship or download NVIDIA binaries** (`nvngx_dlss*.dll`). See [docs/NEURAL-SETUP.md](docs/NEURAL-SETUP.md) and [docs/COMMERCIAL.md](docs/COMMERCIAL.md).
