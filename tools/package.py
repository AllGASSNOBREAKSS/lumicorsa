#!/usr/bin/env python3
"""Builds the release zip: apps/lua/Lumicorsa/** from app/Lumicorsa, the layout Content Manager installs when the
zip is dragged onto its window (it unpacks `apps/...` into the Assetto Corsa folder).

usage: package.py [out_dir]   ->  <out_dir>/Lumicorsa-v<version>.zip (version from app/Lumicorsa/manifest.ini)
"""
import pathlib, re, sys, zipfile

ROOT = pathlib.Path(__file__).resolve().parent.parent
APP = ROOT / 'app/Lumicorsa'


def main():
    out_dir = pathlib.Path(sys.argv[1]) if len(sys.argv) > 1 else ROOT / 'dist'
    version = re.search(r'^VERSION\s*=\s*(\S+)', (APP / 'manifest.ini').read_text(encoding='utf-8'), re.M).group(1)
    out_dir.mkdir(parents=True, exist_ok=True)
    out = out_dir / f'Lumicorsa-v{version}.zip'
    skip = {'selftest.log', 'soak.log', 'autorun.json', 'autorun.done'}
    files = sorted(p for p in APP.rglob('*') if p.is_file() and 'state' not in p.relative_to(APP).parts and p.name not in skip)
    with zipfile.ZipFile(out, 'w', zipfile.ZIP_DEFLATED) as z:
        for p in files:
            info = zipfile.ZipInfo('apps/lua/Lumicorsa/' + p.relative_to(APP).as_posix(), date_time=(2026, 1, 1, 0, 0, 0))
            info.compress_type = zipfile.ZIP_DEFLATED
            info.external_attr = 0o644 << 16
            z.writestr(info, p.read_bytes())
    print(f'{out} ({len(files)} files)')


if __name__ == '__main__':
    main()
