#!/usr/bin/env python3
"""Cross-checks the app so its parts can't drift apart:
   - every PL_* key the Lua side uses is a value of shaders/final.hlsl,
   - every shader the Lua side loads exists, and every shader file is loaded by something,
   - every registry id a tab places exists as a registration (or is a known optional one),
   - the fonts, licences, brand and cluster assets the UI references ship with the app,
   - no trial fonts and no NVIDIA binaries are packaged."""
import pathlib, re, sys

root = pathlib.Path(__file__).resolve().parent.parent
app = root / 'app/Lumicorsa'
lua = '\n'.join(p.read_text(encoding='utf-8') for p in sorted(app.rglob('*.lua')))
final = (app / 'shaders/final.hlsl').read_text(encoding='utf-8')

final_pl = {n for n, _ in re.findall(r'(\w+):(\w+)', re.search(r'^// @values (.*)$', final, re.M).group(1)) if n.startswith('PL_')}
lua_keys = set(re.findall(r'\b(PL_\w+)\b', lua))
loaded = set(re.findall(r"pass\('(\w+)'", lua)) | set(re.findall(r"shader\('(\w+)'\)", lua))
on_disk = {p.stem for p in (app / 'shaders').glob('*.hlsl')} - {'common'}

tabs = (app / 'ui/tabs.lua').read_text(encoding='utf-8')
placed = set(re.findall(r"(?:S|G|TG|B)\('(\w+)'\)", tabs)) | set(re.findall(r"id = '(\w+)'", tabs))
for grp in re.findall(r"K\(([^)]*)\)", tabs) + re.findall(r"ids = \{([^}]*)\}", tabs):
    placed |= set(re.findall(r"'(\w+)'", grp))
registered = set(re.findall(r"R\.(?:csp|ac|api|state|action)\('(\w+)'", lua)) | set(re.findall(r"(?:chaseDef|lookValue|st)\('(\w+)'", lua))
registered |= {c for c in re.findall(r"\{ '(m_\w+)'", lua)}                       # audio channels
registered |= {'purePlanner', 'pureConfig', 'solPlanner'}                          # sky apps (registered when installed)

errors = []
for k in sorted(lua_keys - final_pl): errors.append(f'Lua uses {k}, not a value of final.hlsl')
for s in sorted(loaded - on_disk): errors.append(f'Lua loads shaders/{s}.hlsl, which does not exist')
for s in sorted(on_disk - loaded): errors.append(f'shaders/{s}.hlsl is never loaded')
for i in sorted(placed - registered): errors.append(f'tabs.lua places "{i}", which nothing registers')
need = ['fonts/Inter-Regular.ttf', 'fonts/Inter-Medium.ttf', 'fonts/Inter-Bold.ttf', 'fonts/JetBrainsMono-Medium.ttf',
        'fonts/OFL-Inter.txt', 'fonts/OFL-JetBrainsMono.txt', 'icon.png', 'brand/dotgrid.png']
need += ['hud/cluster_assets/' + f for f in ('hood.png', 'speedo_kmh.png', 'speedo_mph.png', 'tach_c.png', 'tach_f.png', 'needle.png',
         'needle_orange.png', 'needle_white.png', 'subneedle.png', 'overlay.png', 'lamps_on.png', 'lamps_off.png', 'turn_on.png',
         'turn_off.png', 'lcd_overlay.png')]
for f in need:
    if not (app / f).exists(): errors.append(f'missing {f}')
for p in app.rglob('*'):
    n = p.name.lower()
    if 'trial' in n or n.endswith('.otf'): errors.append(f'trial/unlicensed font packaged: {p.relative_to(root)}')
    if n.startswith('nvngx') or n.endswith('.dll'): errors.append(f'binary packaged: {p.relative_to(root)}')

print(f'PL_ values={len(final_pl)} lua keys={len(lua_keys)} shaders loaded={len(loaded)}/{len(on_disk)} '
      f'controls placed={len(placed)} registered={len(registered)}')
if errors:
    print('\n'.join(errors)); sys.exit(1)
print('consistency: OK')
