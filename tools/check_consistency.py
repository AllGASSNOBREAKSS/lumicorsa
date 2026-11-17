#!/usr/bin/env python3
"""Cross-checks the layers so they can't drift apart:
   - every PL_* key the CSP app uses is a value of shaders/final.hlsl (the native pipeline),
   - final.hlsl's PL_* parameters all exist in the legacy ReShade Photolap.fx (same parameter set on both paths),
   - every shader the Lua pipeline loads exists, and every CSP shader file is loaded by something,
   - the legacy add-on only toggles techniques and uniforms that exist in Photolap.fx."""
import re, sys, pathlib

root = pathlib.Path(__file__).resolve().parent.parent
app = root / 'csp-app/Photolap'
lua = (app / 'Photolap.lua').read_text(encoding='utf-8') + (app / 'pl_pipeline.lua').read_text(encoding='utf-8')
final = (app / 'shaders/final.hlsl').read_text(encoding='utf-8')
fx = (root / 'legacy/reshade/Photolap.fx').read_text(encoding='utf-8')
cpp = (root / 'legacy/reshade/addon/src/photolap_addon.cpp').read_text(encoding='utf-8')

final_values = {n for n, _ in re.findall(r'(\w+):(\w+)', re.search(r'^// @values (.*)$', final, re.M).group(1))}
final_pl = {v for v in final_values if v.startswith('PL_')}
fx_uniforms = set(re.findall(r'^uniform\s+\w+\s+(PL_\w+)', fx, re.M))
fx_techniques = set(re.findall(r'^technique\s+(\w+)', fx, re.M))
lua_keys = set(re.findall(r'\b(PL_\w+)\b', lua))
cpp_keys = set(re.findall(r'"(PL_\w+)"', cpp))
cpp_techs = set(re.findall(r'"(Photolap_\w+)"', cpp))

loaded = set(re.findall(r"pass\('(\w+)'", lua)) | set(re.findall(r"shader\('(\w+)'\)", lua))
on_disk = {p.stem for p in (app / 'shaders').glob('*.hlsl')} - {'common'}

errors = []
for k in sorted(lua_keys - final_pl): errors.append(f'Lua app uses {k}, not a value of final.hlsl')
for k in sorted(final_pl - fx_uniforms): errors.append(f'final.hlsl has {k}, missing from legacy Photolap.fx')
for s in sorted(loaded - on_disk): errors.append(f'pipeline loads shaders/{s}.hlsl, which does not exist')
for s in sorted(on_disk - loaded): errors.append(f'shaders/{s}.hlsl is never loaded')
for k in sorted(cpp_keys - fx_uniforms): errors.append(f'legacy add-on uses {k}, not a uniform in Photolap.fx')
for t in sorted(cpp_techs - fx_techniques): errors.append(f'legacy add-on toggles {t}, not a technique in Photolap.fx')

print(f'final.hlsl PL_ values={len(final_pl)} lua_keys={len(lua_keys)} shaders loaded={len(loaded)}/{len(on_disk)} '
      f'legacy fx uniforms={len(fx_uniforms)}')
if errors:
    print('\n'.join(errors)); sys.exit(1)
print('consistency: OK')
