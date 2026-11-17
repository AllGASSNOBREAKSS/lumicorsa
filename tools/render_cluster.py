#!/usr/bin/env python3
"""Pre-renders the static layers of the analog cluster to PNG (2x) from the approved design markup.

Source: design/analog-cluster.dc.html from the Lumicorsa UI package. Static SVG/CSS is cut straight out of that file
(hood, chrome bezels, faces, numerals for km/h and mph, sub-dial scales, needles, caps, glass glare, lamps, LCD
overlay) and rendered with headless Microsoft Edge on a transparent background. Live parts (needle angles, warm-up
bands, shift LEDs, lamp state, LCD text) are drawn by hud/cluster.lua at runtime. FK Grotesk is replaced by Inter (OFL).

Windows only (needs Edge). usage: render_cluster.py <analog-cluster.dc.html> <out_dir>
"""
import pathlib, re, subprocess, sys, tempfile

EDGE = r'C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe'
ROOT = pathlib.Path(__file__).resolve().parent.parent
FONTS = (ROOT / 'app/Lumicorsa/fonts').as_uri()

src = pathlib.Path(sys.argv[1]).read_text(encoding='utf-8')
OUT = pathlib.Path(sys.argv[2]).resolve(); OUT.mkdir(parents=True, exist_ok=True)
WORK = pathlib.Path(tempfile.mkdtemp(prefix='lumi_render_', dir='D:/Lumicorsa/work'))

HEAD = f'''<!doctype html><html><head><meta charset="utf-8"><style>
@font-face{{font-family:'FK Grotesk';src:url({FONTS}/Inter-Light.ttf);font-weight:300}}
@font-face{{font-family:'FK Grotesk';src:url({FONTS}/Inter-Regular.ttf);font-weight:400}}
@font-face{{font-family:'FK Grotesk';src:url({FONTS}/Inter-Medium.ttf);font-weight:500}}
@font-face{{font-family:'FK Grotesk';src:url({FONTS}/Inter-Bold.ttf);font-weight:700}}
html,body{{margin:0;background:transparent;overflow:hidden}}
</style></head><body>'''


def render(name, w, h, body):
    html = WORK / (name + '.html')
    html.write_text(HEAD + body + '</body></html>', encoding='utf-8')
    png = OUT / (name + '.png')
    subprocess.run([EDGE, '--headless=new', '--disable-gpu', '--hide-scrollbars', f'--user-data-dir={WORK / "profile"}',
                    '--default-background-color=00000000', '--force-device-scale-factor=2', f'--window-size={w},{h}',
                    '--virtual-time-budget=1500', f'--screenshot={png}', html.as_uri()], check=True, capture_output=True)
    print(f'{png.name}: {w * 2}x{h * 2}')


def between(a, b, start=0):
    i = src.index(a, start)
    j = src.index(b, i + len(a))
    return src[i:j + len(b)], j + len(b)


# ------------------------------------------------------------------------------------------------ hood and shell
svg_hood, _ = between('<svg width="1400" height="720"', '</svg>')
render('hood', 1400, 720, svg_hood)

# ------------------------------------------------------------------------------------------------ dials
# Each dial block: bezel divs + face <svg>. Split the face svg into: static face, needle, sub-needle, overlay.
dials = [m.start() for m in re.finditer(r'<div style="position: absolute; left: (86|814)px; top: 136px">', src)]
SPEEDO, TACH = dials

def dial_parts(at):
    block, _ = between('<div style="position: relative; width: 500px', '</svg>', at)
    head = block[:block.index('<svg width="458"')]
    svg = block[block.index('<svg width="458"'):]
    defs, _ = re.search(r'<defs>.*?</defs>', svg, re.S).group(0), None
    return head, svg, defs

CLOSE = '</div></div></div></div>'

def face_static(svg, keep_group):
    """Strip live elements from a dial face svg, keep the chosen numeral group."""
    s = svg
    s = re.sub(r'<g style="transform-origin: 250px 250px;.*?</g>\s*', '', s, flags=re.S)           # main needle
    s = re.sub(r'<g style="transform-origin: 250px 404px;.*?</g>', '', s, flags=re.S)             # sub-needle
    s = re.sub(r'<circle cx="250" cy="(250|404)" r="(42|41|21)"[^>]*/>', '', s)                     # caps
    s = re.sub(r'<path d="M60 170 C110 40[^>]*/>', '', s)                                          # glare
    s = re.sub(r'<path d="\{\{warmArc2?\}\}"[^>]*/>', '', s)                                       # warm-up bands (live)
    s = re.sub(r'<rect x="-7" y="-4"[^>]*/>', '', s)                                               # shift LEDs (live)
    if keep_group == 'kmh':
        s = re.sub(r'<g opacity="\{\{mphOp\}\}".*?</g>', '', s, flags=re.S).replace('opacity="{{kmhOp}}"', '')
    elif keep_group == 'mph':
        s = re.sub(r'<g opacity="\{\{kmhOp\}\}".*?</g>', '', s, flags=re.S).replace('opacity="{{mphOp}}"', '')
    return s

def subs(s, **kw):
    for k, v in kw.items(): s = s.replace('{{' + k + '}}', v)
    return s

sp_head, sp_svg, defs = dial_parts(SPEEDO)
ta_head, ta_svg, _ = dial_parts(TACH)
render('speedo_kmh', 500, 500, sp_head + face_static(sp_svg, 'kmh') + CLOSE)
render('speedo_mph', 500, 500, sp_head + face_static(sp_svg, 'mph') + CLOSE)
render('tach_c', 500, 500, ta_head + subs(face_static(ta_svg, None), oilLo='50', oilMid='100', oilHi='150 °C') + CLOSE)
render('tach_f', 500, 500, ta_head + subs(face_static(ta_svg, None), oilLo='120', oilMid='210', oilHi='300 °F') + CLOSE)

# Needle layers in face space (458 px square, viewBox 500): rotate around the image centre in Lua.
needle = re.search(r'<g style="transform-origin: 250px 250px;[^"]*">(.*?)</g>', sp_svg, re.S).group(1)
render('needle', 458, 458, f'<svg width="458" height="458" viewBox="0 0 500 500">{defs}{needle}</svg>')
# Needle colour options from the HUD tab (Orange, White): same shape, recoloured gradient, glow and tail.
NEEDLE_COLOURS = {
    'orange': {'#8E0F08': '#8E4A08', '#FF4A33': '#FF9A33', '#FF6B52': '#FFB052', '#FF3B22': '#FF8A1A', '#B1180E': '#B15A0E'},
    'white': {'#8E0F08': '#8A8D94', '#FF4A33': '#F4F5F7', '#FF6B52': '#FFFFFF', '#FF3B22': '#FFFFFF', '#B1180E': '#9A9DA4'},
}
for cname, swap in NEEDLE_COLOURS.items():
    d2, n2 = defs, needle
    for a, b in swap.items(): d2, n2 = d2.replace(a, b), n2.replace(a, b)
    render('needle_' + cname, 458, 458, f'<svg width="458" height="458" viewBox="0 0 500 500">{d2}{n2}</svg>')
# Sub-needle, cropped square around its pivot (250, 404): viewBox 120 wide -> 110 px.
sub = re.search(r'<g style="transform-origin: 250px 404px;[^"]*">(.*?)</g>', sp_svg, re.S).group(1)
render('subneedle', 110, 110, f'<svg width="110" height="110" viewBox="190 344 120 120">{defs}{sub}</svg>')
# Overlay: caps, cap rim and glass glare, above every needle.
caps = ''.join(re.findall(r'<circle cx="250" cy="(?:250|404)" r="(?:42|41|21)"[^>]*/>', sp_svg))
glare = re.search(r'<path d="M60 170 C110 40[^>]*/>', sp_svg).group(0)
render('overlay', 458, 458, f'<svg width="458" height="458" viewBox="0 0 500 500">{defs}{caps}{glare}</svg>')

# ------------------------------------------------------------------------------------------------ lamps
# Lamp shapes from the design script, rendered lit and unlit (same colours the design uses).
RED, AMB, GRN, BLU = '#FF2A1F', '#FFA81A', '#2CDB5C', '#2F7BFF'
OFF = {RED: '#241312', AMB: '#241C10', GRN: '#10231A', BLU: '#101827'}
lamp = 'M13 4c5 0 8 3.5 8 7.5S18 19 13 19z'
LAMPS = [  # id, colour, fill path, stroke path, knock-out path, text, font size
    ('high', BLU, lamp, 'M2 6.5h8M2 9.5h8M2 12.5h8M2 15.5h8', '', '', 7),
    ('low', GRN, lamp, 'M2 8l8 1.5M2 12l8 1.5M2 16l8 1.5', '', '', 7),
    ('fog', GRN, lamp, 'M2 7h7M2 11h7M2 15h7M9.5 4.5c-2 2.4 2 4.6 0 7s2 4.6 0 7', '', '', 7),
    ('engine', AMB, 'M5 8h3V6h6v2h3l2 2.5h2.5v6H19l-2 2.5H8.5L5.5 16H3v-6h2z', '', 'M11 10v4', '', 7),
    ('belt', RED, 'M12 1.4a2.4 2.4 0 1 1 0 4.8 2.4 2.4 0 0 1 0-4.8zM8 21v-8.5a4 4 0 0 1 8 0V21z', '', 'M8.5 9l8 10', '', 7),
    ('airbag', RED, 'M6 2.6a2.2 2.2 0 1 1 0 4.4 2.2 2.2 0 0 1 0-4.4zM3 21v-8a3 3 0 0 1 6 0v8zM16.5 8a4.5 4.5 0 1 1 0 9 4.5 4.5 0 0 1 0-9z', '', '', '', 7),
    ('battery', RED, 'M2 7h20v12H2zM5 5h3v2H5zM16 5h3v2h-3z', '', 'M5.5 12.5h3M17 11v3M15.5 12.5h3', '', 7),
    ('oil', RED, 'M3 11h11l4-3 3.5 2-4.5 3v3H5z M20 14.5c.8 1.2 1.2 2 1.2 2.6a1.2 1.2 0 0 1-2.4 0c0-.6.4-1.4 1.2-2.6z', '', '', '', 7),
    ('brake', RED, '', '', '', 'BRAKE', 6.4),
    ('abs', AMB, '', 'M12 3.5a8 8 0 1 1 0 16 8 8 0 0 1 0-16zM2.5 6a11 11 0 0 0 0 11M21.5 6a11 11 0 0 1 0 11', '', 'ABS', 5.2),
    ('esc', AMB, 'M5 9l2-4h10l2 4h1v5H4V9zM6 15h3v2H6zM15 15h3v2h-3z', 'M5 20c2-1 3 1 5 0M14 20c2-1 3 1 5 0', 'M7 9h10', '', 7),
    ('tpms', AMB, '', 'M5 6c-2.5 3.5-2.5 9 0 12.5h14c2.5-3.5 2.5-9 0-12.5M12 8v5.5M12 16v.6', '', '', 7),
]
def lamp_svg(c, f, st, k, t, fs, lit):
    col = c if lit else OFF[c]
    glow = f'filter:drop-shadow(0 0 4px {c});' if lit else ''
    return (f'<svg width="34" height="30" viewBox="0 0 24 22" style="overflow:visible;{glow}">'
            f'<path d="{f}" fill="{col}"/><path d="{st}" fill="none" stroke="{col}" stroke-width="1.9" stroke-linecap="round" stroke-linejoin="round"/>'
            f'<path d="{k}" fill="none" stroke="#060607" stroke-width="1.8" stroke-linecap="round"/>'
            f'<text x="12" y="14.5" text-anchor="middle" font-size="{fs}" font-weight="700" fill="{col}" font-family="FK Grotesk">{t}</text></svg>')
for lit in (True, False):
    cells = ''.join(f'<div style="position:absolute;left:{i * 48 + 7}px;top:9px">{lamp_svg(c, f, st, k, t, fs, lit)}</div>'
                    for i, (_, c, f, st, k, t, fs) in enumerate(LAMPS))
    render('lamps_on' if lit else 'lamps_off', 48 * len(LAMPS), 48, f'<div style="position:relative;width:{48 * len(LAMPS)}px;height:48px">{cells}</div>')
for lit in (True, False):
    col = GRN if lit else '#10231A'
    glow = f'filter:drop-shadow(0 0 4px {GRN});' if lit else ''
    arrows = (f'<div style="position:absolute;left:7px;top:11px"><svg width="34" height="26" viewBox="0 0 24 18" style="{glow}"><path d="M1 9l9-8v5h13v6H10v5z" fill="{col}"/></svg></div>'
              f'<div style="position:absolute;left:55px;top:11px"><svg width="34" height="26" viewBox="0 0 24 18" style="{glow}"><path d="M23 9l-9-8v5H1v6h13v5z" fill="{col}"/></svg></div>')
    render('turn_on' if lit else 'turn_off', 96, 48, f'<div style="position:relative;width:96px;height:48px">{arrows}</div>')

# ------------------------------------------------------------------------------------------------ LCD overlay
render('lcd_overlay', 166, 128, '<div style="position:relative;width:166px;height:128px;border-radius:6px;overflow:hidden">'
       '<div style="position:absolute;inset:0;background-image:linear-gradient(rgba(0,0,0,0.22) 1px, transparent 1px),linear-gradient(90deg, rgba(0,0,0,0.22) 1px, transparent 1px);background-size:3px 3px"></div>'
       '<div style="position:absolute;left:0;right:0;top:0;height:40%;background:linear-gradient(180deg, rgba(255,255,255,0.14), transparent)"></div></div>')
print('lamp order:', ' '.join(l[0] for l in LAMPS))
