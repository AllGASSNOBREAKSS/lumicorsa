<p align="center"><img src="docs/img/icon.png" width="96"></p>

<h1 align="center">PHOTOLAP</h1>
<p align="center"><b>Photoreal post-processing for Assetto Corsa, native to Custom Shaders Patch.</b><br>
HDR light, atmosphere, detail, lens and a small neural detail pass, controlled live from an in-game panel,<br>
in any session you launch from Content Manager: No Hesi and other online servers, practice, replays.</p>

---

**Needs only Content Manager + Custom Shaders Patch.** There's no ReShade, no DLL and nothing to download from third parties. Photolap is one CSP Lua app.

## Install

**Content Manager (easiest):** download `Photolap-v0.2.0.zip` from [Releases](https://github.com/AllGASSNOBREAKSS/photolap/releases) and drag it onto the Content Manager window, then click **Install**. CM places it in `assettocorsa\apps\lua\Photolap`.

**By hand:** unzip it and copy `apps\lua\Photolap` into your `assettocorsa` folder. From a clone of this repo, run `installer\Install.bat` instead. It finds AC through your Steam libraries and copies `csp-app\Photolap` there. That's all it does.

Then start any session from CM and open **Photolap** from the CSP apps bar on the right edge of the screen, or press **Alt+P**.

## In game

- **ENGAGED / BYPASSED** at the top, or **Alt+O** from anywhere, switches the whole stack on and off instantly.
- **Look** presets: Photoreal · Midnight Run (night highway / tandem) · Golden Hour · Broadcast · Performance.
- **Effects:** HDR Light, Atmosphere, Detail and Lens can each be toggled. Exposure, Bloom, Sharpen and Mix sliders sit below them, with everything else under **Advanced**.
- **Before / after split:** the left half is the untouched game and the right half is Photolap.
- **Status** shows what is actually running: Shaders (running / compiling / bypassed), Neural (on/off), GPU cost, and Upscaler (CSP's DLSS/FSR state, with a hint if it's off).

## What runs, and how

| Layer | What you get |
|---|---|
| **Light** | Highlight recovery from the LDR frame, 5-octave HDR bloom, film halation around headlights and street lamps, filmic re-tonemap, white balance, split-tone grade |
| **Atmosphere** | Depth-aware aerial perspective: distance haze and desaturation in real metres from CSP's camera planes, sky-safe |
| **Detail** | Contrast-adaptive sharpening plus midtone clarity, crisp tyre walls, kerbs and signage without halos |
| **Lens** | Radial chromatic aberration, natural cos⁴ vignette, luma-aware animated grain |
| **Photolap Neural** | A small pretrained CNN (4 convolution layers) run as GPU shaders. It uses the Anime4K restore network (MIT) as a learned, edge-aware detail enhancer |
| **HUD-safe** | Drawn in CSP's first UI callback, so it applies to the finished scene, after CSP's post-processing and upscaler, and before the HUD, chat, leaderboards and every app window |

All of it is HLSL compiled by CSP at runtime (`csp-app/Photolap/shaders`). The panel sets shader values directly; nothing is exchanged through files. Details are in [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md), and why it is built this way is in [docs/RESEARCH.md](docs/RESEARCH.md).

**Upscaling** is not Photolap's job. CSP already ships DLSS, FSR, XeSS and others under *CM › Settings › Custom Shaders Patch › Graphics adjustments › Upscaling*. Photolap reads that setting and shows it in the panel.

**Other post-processing apps** (Dream Realism, for example) already grade the frame inside CSP. When Photolap detects one, it stays on top but skips its own inverse-tonemap and filmic curve so the image isn't tonemapped twice. *Advanced › Compatibility* turns that off.

## Honest notes

- **Photolap Neural is not NVIDIA DLSS 5** or any NVIDIA technology. It's a 4-layer convolutional network with about 1,000 weights, from the open-source Anime4K project, running in your own shaders. It sharpens and restores fine detail. It doesn't relight the scene the way generative neural rendering does.
- **It needs CSP's Graphics adjustments module enabled** (on by default), because Photolap reads the frame through it.
- HDR output and VR aren't supported yet. The panel says so and leaves the image alone.
- **GPU cost** is measured, not guessed. It's the difference in GPU frame time between engaged and bypassed, so toggle Alt+O off and on once to get a reading.

## Repository

```
csp-app/Photolap/             the product: CSP Lua app (panel + pipeline) and its HLSL shaders
installer/                    Install-Photolap.ps1 (copies the app folder) + Install.bat
tools/hlslcheck.py            compiles every CSP shader with d3dcompiler_47 against a stub of CSP's template (Windows)
tools/lua_mock_test.lua       runs the app under LuaJIT with a stubbed CSP API; checks every pass against its shader header
tools/check_consistency.py    keeps app keys, shaders and the legacy path in sync
tools/anime4k_to_hlsl.py      regenerates the Photolap Neural layers from Anime4K's GLSL
tools/package.py              builds the drag-into-CM zip (apps/lua/Photolap/...)
legacy/reshade/               optional v0.1 ReShade path (Photolap.fx + add-on), not installed by default
vendor/                       community DLSS 5 projects from the v0.1 research, as submodules (reference only)
```

CI runs the Lua mock test, the consistency check and packaging on Linux, and compiles every CSP shader on Windows.

## Legal

- Photolap's own code is MIT. Third-party notices, including the Anime4K weights (MIT), are in [THIRD-PARTY-NOTICES.md](THIRD-PARTY-NOTICES.md).
- Photolap is not affiliated with NVIDIA, Kunos or the CSP authors, and it ships no NVIDIA binaries.
