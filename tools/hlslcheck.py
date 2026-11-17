#!/usr/bin/env python3
"""Compiles every CSP Lua-app shader in csp-app/Photolap/shaders with the Windows HLSL compiler (d3dcompiler_47, ps_5_0).

CSP wraps `shader` code in its own template (extension/internal/shader-tpl/ui.fx, built into dwrite.dll): it declares a
Texture2D per `textures` key, a cbuffer entry per `values` key, the shared samplers and `struct PS_IN`. A compile error in
game halts the Lua script, so this check rebuilds that wrapper from each file's header and compiles it here:

    // @common                         prepend shaders/common.hlsl (the app does the same)
    // @textures txA txB               Texture2D declarations
    // @values gA:float gB:float2      cbuffer members

Windows only (needs d3dcompiler_47.dll). usage: hlslcheck.py [shader_dir]
"""
import ctypes, pathlib, re, sys

HERE = pathlib.Path(__file__).resolve().parent
SHADERS = pathlib.Path(sys.argv[1]) if len(sys.argv) > 1 else HERE.parent / 'csp-app/Photolap/shaders'

STUB = '''
SamplerState samLinear : register(s0);
SamplerState samLinearClamp : register(s1);
SamplerState samPointClamp : register(s2);
SamplerState samLinearSimple : register(s3);
struct PS_IN { float4 PosH : SV_POSITION; float2 Tex : TEXCOORD0; };
'''


def wrap(path):
    src = path.read_text(encoding='utf-8')
    head = dict(re.findall(r'^// @(\w+)[ \t]*(.*)$', src, re.M))
    code = STUB
    for i, t in enumerate(head.get('textures', '').split()):
        code += f'Texture2D {t} : register(t{i});\n'
    members = head.get('values', '').split()
    if members:
        code += 'cbuffer cbPL : register(b10) {\n' + ''.join(f'  {m.split(":")[1]} {m.split(":")[0]};\n' for m in members) + '};\n'
    if 'common' in head:
        code += (SHADERS / 'common.hlsl').read_text(encoding='utf-8') + '\n'
    # CSP's template owns the real entry point and calls the shader's main()
    return code + src + '\nfloat4 cspEntry(PS_IN pin) : SV_TARGET { return main(pin); }\n'


def compile_ps(code, name):
    d3d = ctypes.WinDLL('d3dcompiler_47.dll')
    blob, err = ctypes.c_void_p(), ctypes.c_void_p()
    src = code.encode()
    hr = d3d.D3DCompile(src, len(src), name.encode(), None, None, b'cspEntry', b'ps_5_0', 0, 0,
                        ctypes.byref(blob), ctypes.byref(err))
    msg = ''
    if err.value:
        vt = ctypes.cast(ctypes.cast(err, ctypes.POINTER(ctypes.c_void_p))[0], ctypes.POINTER(ctypes.c_void_p))
        ptr = ctypes.WINFUNCTYPE(ctypes.c_void_p, ctypes.c_void_p)(vt[3])(err)
        size = ctypes.WINFUNCTYPE(ctypes.c_size_t, ctypes.c_void_p)(vt[4])(err)
        msg = ctypes.string_at(ptr, size).decode(errors='replace').strip()
    return hr & 0xFFFFFFFF, msg


def main():
    failed = 0
    files = sorted(p for p in SHADERS.glob('*.hlsl') if p.name != 'common.hlsl')
    for f in files:
        hr, msg = compile_ps(wrap(f), f.name)
        ok = hr == 0
        failed += not ok
        print(f'{"OK  " if ok else "FAIL"} {f.name}' + (f'\n{msg}' if msg and (not ok or 'warning' in msg) else ''))
    print(f'{len(files) - failed}/{len(files)} shaders compile')
    sys.exit(1 if failed else 0)


if __name__ == '__main__':
    main()
