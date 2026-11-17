# Third-party notices

## Shipped in the CSP app (`csp-app/Photolap`)

| Component | Where | Licence |
|---|---|---|
| Anime4K v4 "Restore CNN Soft (S)" weights (bloc97) | `csp-app/Photolap/shaders/nn_0.hlsl` … `nn_3.hlsl`, generated from `glsl/Restore/Anime4K_Restore_CNN_Soft_S.glsl` by `tools/anime4k_to_hlsl.py` | MIT, allows commercial use (text below) |

Photolap Neural uses these pretrained weights unchanged. Photolap applies the network's residual in the opposite direction, with a gain and a clamp, as a learned detail enhancer.

```
MIT License

Copyright (c) 2019-2021 bloc97
All rights reserved.

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

Source: https://github.com/bloc97/Anime4K (commit 7684e95).

## Legacy ReShade path and build tools (not shipped in the CSP app)

| Component | Where | Licence |
|---|---|---|
| ReShade add-on headers (crosire) | `third_party/reshade/include` | BSD 3-Clause, see `third_party/reshade/LICENSE.md` |
| Dear ImGui header (Omar Cornut) | `third_party/imgui` | MIT, see `third_party/imgui/LICENSE.txt` |
| ReShade effect compiler (crosire) | used by `tools/fxcheck` at build time only, not shipped | BSD 3-Clause |
| DLSS5-Feeder (Jean-Laurent ROUZIES) | `legacy/reshade/addon/src/renodx_bridge.hpp` is adapted from `src/feed_renodx_api.h`; submodule `vendor/DLSS5-Feeder` | MIT |
| DLSS5oneclick (Faisal Bahashwan) | submodule `vendor/DLSS5oneclick` (reference only) | MIT |
| dlss5-visual-enhancer (Merserk) | submodule `vendor/dlss5-visual-enhancer` (reference only, no code copied) | Merserk Source License |
| DLSS 5 MANAGER (NODIX-TECH) | submodule `vendor/DLSS-5-MANAGER` (reference only, no code copied) | Copyright NODIX-TECH |

NVIDIA, DLSS and RTX are trademarks of NVIDIA Corporation. Assetto Corsa is a trademark of Kunos Simulazioni.
Photolap is not affiliated with or endorsed by NVIDIA, Kunos Simulazioni, or the Custom Shaders Patch authors.
No NVIDIA binaries are included in this repository.
