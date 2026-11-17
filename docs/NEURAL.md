# Photolap Neural

Photolap Neural is Photolap's own neural pass. It runs entirely in CSP as four GPU shader passes and needs no extra files, no specific GPU and no setup. Turn it on with **Neural pass** in the panel and set its strength with **Intensity**.

## What it is

- A 4-layer convolutional network (3×3 kernels, CReLU) with about 1,000 weights: Anime4K v4 *Restore CNN Soft (S)* by bloc97, MIT licensed. See `THIRD-PARTY-NOTICES.md`.
- It runs at full resolution, after CSP's upscaler and before Photolap's grade, on the same frame you see.
- The network was trained to undo blur and compression. On game frames its correction is a small, edge-aware smoothing step, so Photolap applies it in reverse as a learned unsharp mask: fine detail such as lettering, badges and panel gaps comes forward, flat areas stay flat, and a per-pixel clamp limits halos. Intensity 0–1 maps to a gain of 0–3.5.

## What it is not

It's not NVIDIA DLSS 5 or any NVIDIA technology, and it doesn't relight scenes the way generative neural rendering models do. It's a small, fast detail network. For upscaling, use CSP's own DLSS, FSR or XeSS (*CM › Settings › Custom Shaders Patch › Graphics adjustments › Upscaling*). Photolap shows its state in the panel.

## Cost

Four full-resolution passes of about 9–18 texture reads each. Check **GPU cost** in the panel's status (toggle Alt+O off and on once to measure).

## Regenerating the layers

```
python tools/anime4k_to_hlsl.py <Anime4K>/glsl/Restore/Anime4K_Restore_CNN_Soft_S.glsl csp-app/Photolap/shaders nn_
python tools/hlslcheck.py
```
