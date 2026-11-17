# Third-party notices

| Component | Where | Licence |
|---|---|---|
| Space Grotesk (The Space Grotesk Project Authors) | `app/Pitwall/fonts/SpaceGrotesk-*.ttf` | SIL Open Font License 1.1, see `app/Pitwall/fonts/OFL.txt` |
| Anime4K v4 "Restore CNN Soft (S)" weights (bloc97) | `app/Pitwall/shaders/nn_0.hlsl` … `nn_3.hlsl`, generated from `glsl/Restore/Anime4K_Restore_CNN_Soft_S.glsl` by `tools/anime4k_to_hlsl.py` | MIT (text below) |

Pitwall Neural uses the Anime4K weights unchanged. Pitwall applies the network's residual in the opposite direction, with a gain and a clamp, as a learned detail enhancer. Source: https://github.com/bloc97/Anime4K (commit 7684e95).

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

Pitwall works with, but doesn't include, Custom Shaders Patch, Content Manager and Pure. Pure's apps are opened, not copied.
NVIDIA and DLSS are trademarks of NVIDIA Corporation. Assetto Corsa is a trademark of Kunos Simulazioni.
Pitwall is not affiliated with NVIDIA, Kunos Simulazioni, the CSP authors or the Pure author.
