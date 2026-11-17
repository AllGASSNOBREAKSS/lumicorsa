#!/usr/bin/env python3
"""Fails if the app calls any CSP Lua API that the SDK doesn't define.

Scans app/Lumicorsa/**/*.lua for `ac.*`, `ui.*`, `render.*`, `physics.*`, `web.*`, `io.*` references and checks each
against the definitions in an SDK folder: either CSP's own `extension/internal/lua-sdk/ac_apps` (version-exact for the
installed CSP build) or a clone of github.com/ac-custom-shaders-patch/acc-lua-sdk.

usage: sdk_check.py <sdk_dir>
"""
import pathlib, re, sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
APP = ROOT / 'app/Lumicorsa'
MODULES = ('ac', 'ui', 'render', 'physics', 'web', 'io')


def sdk_names(sdk):
    funcs, tables = set(), set()
    if str(sdk).endswith('.txt'):                                     # committed name list (see sdk_names_csp*.txt)
        for line in pathlib.Path(sdk).read_text(encoding='utf-8').splitlines():
            if line.startswith('f '): funcs.add(line[2:])
            elif line.startswith('t '): tables.add(line[2:])
        return funcs, tables
    for p in pathlib.Path(sdk).rglob('*.lua'):
        text = p.read_text(encoding='utf-8', errors='replace')
        for m in re.finditer(r'^function ((?:%s)\.[\w.]+)\s*\(' % '|'.join(MODULES), text, re.M):
            funcs.add(m.group(1))
        for m in re.finditer(r'^((?:%s)\.[\w.]+)\s*=' % '|'.join(MODULES), text, re.M):
            tables.add(m.group(1))
    return funcs, tables


def app_refs():
    refs = {}
    for p in APP.rglob('*.lua'):
        text = p.read_text(encoding='utf-8')
        text = re.sub(r'--\[\[.*?\]\]', '', text, flags=re.S)          # block comments
        text = re.sub(r'--[^\n]*', '', text)                            # line comments
        text = re.sub(r"'(?:\\.|[^'\\])*'|\"(?:\\.|[^\"\\])*\"", '""', text)   # strings
        for m in re.finditer(r'(?<![\w.:])((?:%s)\.[A-Za-z_]\w*(?:\.[A-Za-z_]\w*)*)(\s*\()?' % '|'.join(MODULES), text):
            key = (m.group(1), bool(m.group(2)))
            refs.setdefault(key, set()).add(p.relative_to(ROOT).as_posix())
    return refs


def main():
    funcs, tables = sdk_names(sys.argv[1])
    missing = []
    refs = app_refs()
    for (ref, called), where in sorted(refs.items()):
        parts = ref.split('.')
        if called:
            ok = ref in funcs                                          # a call must hit a defined function exactly
        else:                                                          # a value: function reference, table or enum member
            ok = ref in funcs or ref in tables or any('.'.join(parts[:i]) in tables for i in range(len(parts) - 1, 1, -1))
        if not ok:
            missing.append(f'{ref}{"()" if called else ""}  ({", ".join(sorted(where))})')
    print(f'{len(refs)} distinct API references checked against {len(funcs)} SDK functions / {len(tables)} tables')
    if missing:
        print('NOT IN SDK:\n  ' + '\n  '.join(missing))
        sys.exit(1)
    print('sdk check: OK')


if __name__ == '__main__':
    main()
