# Commercial plan ($15, single-activation key)

These are product notes, not legal advice. Have a lawyer review this before launch.

## What can actually be sold

| Part | Sellable? | Why |
|---|---|---|
| Photolap.fx, photolap.addon64, CSP app, presets, installer | **Yes** | Our code (MIT today; dual-license or relicense the paid tier, since the authors own it) |
| ReShade | Don't bundle | Download it from reshade.me at install (BSD-3 allows bundling, but a fresh download avoids stale builds) |
| DLSS5-Feeder / DLSS5oneclick code we adapted | Yes, with attribution | MIT: keep the notices (THIRD-PARTY-NOTICES.md) |
| Merserk / NODIX code | **Only with written permission** | All-rights-reserved licences. Get a signed note from each author before any of their code ships in the paid build |
| RenoDX DLSS 5 add-on, `nvngx_dlssnr.dll` | **No** | Closed source / NVIDIA proprietary, and leaked builds on top of that |
| The name "DLSS" | **No** | NVIDIA trademark. Say "works with NVIDIA DLSS 5" in descriptive copy only, never in the product name, logo or key art |

## Licensing design (for when we get there)

- Ed25519-signed licence file: `{key_id, machine_hash, issued_at}` signed by our server and verified offline in the add-on. There's no network call at game start.
- "One-time use" means one activation per key, bound to a machine hash (GPU LUID + volume serial, both hashed). Allow 2 self-service rebinds a year, or support will drown.
- The free tier is the full post stack with the Photoreal preset. The paid tier adds all presets, the neural controls, Advanced, and future Photolap Native.
- Storefront: Lemon Squeezy or Paddle (merchant of record, handles VAT). Use Patreon/Ko-fi only if we stay donation-ware.

## Risks to resolve before charging

1. Resolved in v0.2: the neural pass is now Photolap Neural, with MIT-licensed Anime4K weights shipped in our own shaders (keep the notice). Never market it as DLSS or NVIDIA.
2. CSP updates can change the Lua shader template or the `dynamic::` textures. Keep `tools/hlslcheck.py` in CI and re-test on each CSP preview.
3. Online servers: CSP Lua apps are allowed on No Hesi today. Confirm with the big server owners, and keep the Alt+O bypass prominent.
