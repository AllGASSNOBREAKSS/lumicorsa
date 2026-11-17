<p align="center"><img src="docs/img/logo.png" width="112"></p>

<h1 align="center">PITWALL</h1>
<p align="center"><b>All-in-one graphics, weather and settings for Assetto Corsa.</b><br>
One panel. Needs only Content Manager + Custom Shaders Patch. Works online and offline.</p>

---

## Install

1. Download `Pitwall-v1.0.0.zip` from [Releases](https://github.com/AllGASSNOBREAKSS/photolap/releases).
2. Drag it onto Content Manager and click **Install**. Or copy `apps/lua/Pitwall` into your `assettocorsa` folder.
3. In game, open **Pitwall** from the CSP apps bar, or press **Alt+P**. **Alt+O** turns the look off and on.

If you used Photolap before, delete `assettocorsa/apps/lua/Photolap`.

## What's inside

| Page | What it controls | Applies |
|---|---|---|
| **Look** | On/off, presets, before/after split, mix, quick sliders, live status | live |
| **Effects** | HDR light, bloom, halation, filmic, grade, distance haze, clarity, sharpening, lens | live |
| **Realism** | Pitwall Neural detail, sun shafts, lens flare, contact shadows, depth of field | live |
| **Pure** | WeatherFX style, Pure options, cloud and star quality, one-click Pure Config / Planner / PP | live or on reload |
| **Weather** | Conditions, time of day and time speed (offline), headlights and wipers, rain | live |
| **Graphics** | CSP upscaling (DLSS / FSR / XeSS), AA, shadows, GI, AO, reflections, Extra FX, particles, grass, LODs | live, or a restart where marked |
| **Filters** | AC post-processing filter, glare, DOF, sun rays, CSP Lua filter | next launch / live |
| **Audio** | Every AC volume channel | live |
| **Video** | Field of view (live), world detail, shadows, texture filtering, reflections, mirrors | next launch |

Every graphics setting reads and writes the same file Content Manager uses, so changes show up in CM, and CM changes show up in Pitwall. Labels, ranges and options come from CSP's own settings files.

Pitwall's look is drawn just after the game image and before the HUD, so apps, chat and leaderboards are never graded.

## Good to know

- **Pitwall Neural is not NVIDIA DLSS.** It's a small open-source CNN (Anime4K weights, MIT) that sharpens fine detail.
- **Pure's own apps hold its full controls.** Pitwall opens them for you rather than copying them.
- **Online, the server sets time and weather,** so those controls lock.
- **Dream Realism and similar apps are detected.** Pitwall stays on top and skips its own re-tonemap.
- HDR output and VR aren't supported yet.

## Repo

```
app/Pitwall/   the CSP app: Lua (panel, pages, settings, pipeline), HLSL shaders, fonts, icon
tools/         Python build checks + a LuaJIT test that runs the app against a stubbed CSP
docs/          architecture and research notes
```

CI runs the Lua test, the consistency check and packaging on Linux, and compiles every shader on Windows.

MIT licence. Third-party notices are in [THIRD-PARTY-NOTICES.md](THIRD-PARTY-NOTICES.md).
