#!/usr/bin/env python3
"""Cross-checks the app so its parts can't drift apart:
   - every PL_* key the Lua side uses is a value of shaders/final.hlsl,
   - every shader the Lua side loads exists, and every shader file is loaded by something,
   - the fonts and icon the UI references ship with the app."""
import pathlib, re, sys

root = pathlib.Path(__file__).resolve().parent.parent
app = root / 'app/Pitwall'
lua = '\n'.join(p.read_text(encoding='utf-8') for p in sorted(app.rglob('*.lua')))
final = (app / 'shaders/final.hlsl').read_text(encoding='utf-8')

final_pl = {n for n, _ in re.findall(r'(\w+):(\w+)', re.search(r'^// @values (.*)$', final, re.M).group(1)) if n.startswith('PL_')}
lua_keys = set(re.findall(r'\b(PL_\w+)\b', lua))
loaded = set(re.findall(r"pass\('(\w+)'", lua)) | set(re.findall(r"shader\('(\w+)'\)", lua))
on_disk = {p.stem for p in (app / 'shaders').glob('*.hlsl')} - {'common'}

errors = []
for k in sorted(lua_keys - final_pl): errors.append(f'Lua uses {k}, not a value of final.hlsl')
for s in sorted(loaded - on_disk): errors.append(f'Lua loads shaders/{s}.hlsl, which does not exist')
for s in sorted(on_disk - loaded): errors.append(f'shaders/{s}.hlsl is never loaded')
for f in ('fonts/SpaceGrotesk-Regular.ttf', 'fonts/SpaceGrotesk-Medium.ttf', 'fonts/SpaceGrotesk-Bold.ttf', 'fonts/OFL.txt', 'icon.png'):
    if not (app / f).exists(): errors.append(f'missing {f}')

print(f'PL_ values={len(final_pl)} lua keys={len(lua_keys)} shaders loaded={len(loaded)}/{len(on_disk)}')
if errors:
    print('\n'.join(errors)); sys.exit(1)
print('consistency: OK')
