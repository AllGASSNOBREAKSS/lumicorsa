#!/usr/bin/env python3
"""Cross-checks the three layers so they can't drift apart:
   every PL_* key the CSP app or the add-on panel writes must be a uniform in Photolap.fx,
   every technique the add-on toggles must exist, and a control.ini produced by the app must parse."""
import re, sys, pathlib

root = pathlib.Path(__file__).resolve().parent.parent
fx = (root / 'shaders/Photolap.fx').read_text()
lua = (root / 'csp-app/Photolap/Photolap.lua').read_text()
cpp = (root / 'addon/src/photolap_addon.cpp').read_text()

uniforms = set(re.findall(r'^uniform\s+\w+\s+(PL_\w+)', fx, re.M))
techniques = set(re.findall(r'^technique\s+(\w+)', fx, re.M))
lua_keys = set(re.findall(r'\b(PL_\w+)\b', lua))
cpp_keys = set(re.findall(r'"(PL_\w+)"', cpp))
cpp_techs = set(re.findall(r'"(Photolap_\w+)"', cpp))

errors = []
for k in sorted(lua_keys - uniforms): errors.append(f'Lua app uses {k}, not a uniform in Photolap.fx')
for k in sorted(cpp_keys - uniforms): errors.append(f'add-on uses {k}, not a uniform in Photolap.fx')
for t in sorted(cpp_techs - techniques): errors.append(f'add-on toggles {t}, not a technique in Photolap.fx')

if len(sys.argv) > 1:
    ctl = pathlib.Path(sys.argv[1]).read_text()
    kv = dict(l.split('=', 1) for l in ctl.splitlines() if '=' in l and not l.startswith(';'))
    for k in ('enabled', 'neural', 'nr_intensity', 'light', 'atmos', 'detail', 'lens', 'hud_safe', 'seq'):
        if k not in kv: errors.append(f'control.ini missing {k}')
    for k in kv:
        if k.startswith('PL_') and k not in uniforms: errors.append(f'control.ini writes unknown uniform {k}')

print(f'uniforms={len(uniforms)} techniques={sorted(techniques)} lua_keys={len(lua_keys)} cpp_keys={len(cpp_keys)}')
if errors:
    print('\n'.join(errors)); sys.exit(1)
print('consistency: OK')
