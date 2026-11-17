# Neural setup (DLSS 5 pass)

The post stack (Light, Atmosphere, Detail, Lens) works on any GPU. The **neural pass** needs:

1. **An RTX 50-series GPU** and a recent NVIDIA driver. Check the DLSS5-Feeder compatibility table: some driver × backend combinations fault inside `nvngx_dlssnr.dll`.
2. **CSP Preview 338+ with DLSS enabled** (CM → Settings → Custom Shaders Patch → Upscaler → NVIDIA DLSS, DLAA or Quality). CSP provides the motion vectors and depth.
3. **A neural backend loaded by ReShade.** Photolap detects and drives either of these:
   - **RenoDX DLSS 5 add-on** (`renodx-dlss5.addon64`, v10+ for live control) plus the DLSS 5 model `nvngx_dlssnr.dll` in the AC folder.
   - **Deep Fried Chicken** (dlss5-dx11-bridge lineage). It is confirmed working with AC + CSP 338+. Intensity is set on its own page, and Photolap shows it as the backend.

## Why Photolap doesn't install the backend for you

The RenoDX DLSS 5 add-on is closed source, and the `nvngx_dlssnr.dll` builds it is used with are, in the words of the community tools that fetch them, *leaked* NVIDIA builds (some patched). Photolap is meant to become a paid product, so it **will not bundle, mirror or auto-download NVIDIA binaries or leaked builds**. If it did, the whole product would be exposed to takedowns and payment-processor bans.

What Photolap does:
- detects whatever backend you have and shows it in the status footer;
- drives it live through its public control export when available;
- otherwise leaves it alone and runs the post stack.

When NVIDIA ships DLSS 5 through official channels (Streamline SDK / driver-level override) for third-party integration, Photolap will move to that path.
