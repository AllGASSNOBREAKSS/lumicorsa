--[[
  Lumicorsa dashboard window (design/dashboard.dc.html): 1480 x 940, radius 28, glass, dot grid, 1 px border.
  Header 78 px (search pill, animated mark + wordmark, quick ring, Basic/Advanced/Expert, Enhancing/Vanilla), an amber
  light sweeping the header line every 6 s, text-only tabs, a 324 px stats rail with measured numbers only, a 3-column
  card grid, and the version in the footer. Everything is drawn from cached state each frame; nothing here writes files.
]]

local T = require('ui/theme')
local W = require('ui/widgets')
local palette = require('ui/palette')
local ring = require('ui/quickring')
local tabs = require('ui/tabs')
local C = T.C

local D = {}

local WIDTH, HEIGHT = 1480, 940
D.SIZE = vec2(WIDTH, HEIGHT)
local PAD, RAIL, GAP = 26, 324, 20
local scroll = { rail = 0, grid = {} }
local flash = nil          -- { tab, card, t0 }
D.modal = nil              -- { title, body(fn), buttons = {{label, on}} }
D.ringOpen = false

local function now() return os.preciseClock() end

-- ---------------------------------------------------------------------------------------------- animated mark
-- Mark from brand/lumicorsa-mark.svg (viewBox 120): racing-line sweep 2.8 s, apex pulse, dashed ring every 14 s.
local LINE = {}   -- sampled racing line with cumulative length
do
  local function bez(p0, p1, p2, p3, t)
    local u = 1 - t
    return p0 * (u * u * u) + p1 * (3 * u * u * t) + p2 * (3 * u * t * t) + p3 * (t * t * t)
  end
  local segs = { { vec2(22, 94), vec2(44, 92), vec2(50, 62), vec2(60, 56) }, { vec2(60, 56), vec2(70, 50), vec2(86, 30), vec2(100, 26) } }
  local len, prev = 0, nil
  for _, s in ipairs(segs) do
    for i = 0, 24 do
      local p = bez(s[1], s[2], s[3], s[4], i / 24)
      if prev then local d = p - prev; len = len + math.sqrt(d.x * d.x + d.y * d.y) end
      LINE[#LINE + 1] = { p = p, l = len }
      prev = p
    end
  end
  LINE.total = len
end

local function easeSweep(t)   -- cubic-bezier(.7,0,.2,1) approximated by a smootherstep with a slow start
  return t * t * t * (t * (t * 6 - 15) + 10)
end

function D.drawMark(o, size, t)
  local k = size / 120
  local function P(v) return o + v * k end
  ui.drawRectFilled(P(vec2(2, 2)), P(vec2(118, 118)), T.hex('#0B0B0E'), 30 * k)
  ui.drawRect(P(vec2(2, 2)), P(vec2(118, 118)), T.hex('#2C2C34'), 30 * k, nil, 1)
  local rot = (t % 14) / 14 * math.pi * 2
  local circ = 2 * math.pi * 40
  for i = 0, math.floor(circ / 12) - 1 do       -- dash 4, gap 8
    local a0 = rot + i * 12 / 40
    ui.pathClear(); ui.pathArcTo(P(vec2(60, 60)), 40 * k, a0, a0 + 4 / 40, 3); ui.pathStroke(T.hex('#33333B'), false, 2 * k)
  end
  for _, l in ipairs({ { 60, 20, 86, 46 }, { 100, 60, 74, 86 }, { 60, 100, 34, 74 }, { 20, 60, 46, 34 } }) do
    ui.drawLine(P(vec2(l[1], l[2])), P(vec2(l[3], l[4])), T.hex('#3B3B45'), 2 * k)
  end
  local ph = (t % 2.8) / 2.8
  local draw = LINE.total * easeSweep(math.min(ph / 0.55, 1))
  ui.pathClear()
  for _, pt in ipairs(LINE) do
    if pt.l > draw then break end
    ui.pathLineTo(P(pt.p))
  end
  ui.pathStroke(C.amber, false, 7 * k)
  local pulse = 0.5 - 0.5 * math.cos(ph * math.pi * 2)
  ui.drawCircleFilled(P(vec2(60, 56)), 7 * k * (1 + 0.22 * pulse), T.alpha(T.hex('#FFF3D6'), 0.6 + 0.4 * pulse), 20)
end

-- ---------------------------------------------------------------------------------------------- header
local function header(env, t, dt)
  local St = env.store
  ui.drawRectFilled(vec2(0, 0), vec2(WIDTH, 78), C.header, T.R.window, ui.CornerFlags and ui.CornerFlags.Top or nil)
  ui.drawLine(vec2(0, 78), vec2(WIDTH, 78), rgbm(1, 1, 1, 0.06), 1)
  -- search pill
  local sp = vec2(PAD, 19)
  local clicked, hovered = W.hit('hdr_search', sp, vec2(300, 40))
  ui.drawRectFilled(sp, sp + vec2(300, 40), rgbm(1, 1, 1, hovered and 0.1 or 0.07), 20)
  ui.drawRect(sp, sp + vec2(300, 40), rgbm(1, 1, 1, 0.10), 20, nil, 1)
  ui.drawCircle(sp + vec2(21, 19), 6, C.muted, 16, 2); ui.drawLine(sp + vec2(25, 23), sp + vec2(29, 27), C.muted, 2)
  T.text('Find any setting or action', sp + vec2(40, 11), 14, C.muted)
  for i, key in ipairs({ 'Ctrl', 'K' }) do
    local kx = sp.x + 300 - 12 - (i == 1 and 52 or 22)
    ui.drawRectFilled(vec2(kx, sp.y + 10), vec2(kx + (i == 1 and 34 or 18), sp.y + 30), rgbm(1, 1, 1, 0.10), 5)
    T.text(key, vec2(kx + 5, sp.y + 12.5), 11, C.text2)
  end
  if clicked then palette.show() end
  -- mark + wordmark (centred)
  local wm = T.measure('Lumicorsa', 26, 'bold').x
  local cx = WIDTH / 2 - (48 + 14 + wm) / 2
  D.drawMark(vec2(cx, 15), 48, t)
  T.text('Lumicorsa', vec2(cx + 62, 14), 26, C.text, 'bold')
  T.text('Light for Assetto Corsa', vec2(cx + 63, 46), 12, C.muted)
  -- right: quick ring, mode, master
  local x = WIDTH - PAD
  local mLabel = St.master and 'Enhancing' or 'Vanilla'
  local mw = T.measure(mLabel, 14, 'medium').x + 16 + 10 + 46 + 6
  x = x - mw
  local mc, mh = W.hit('hdr_master', vec2(x, 19), vec2(mw, 40))
  ui.drawRectFilled(vec2(x, 19), vec2(x + mw, 59), rgbm(1, 1, 1, mh and 0.09 or 0.06), 20)
  ui.drawRect(vec2(x, 19), vec2(x + mw, 59), rgbm(1, 1, 1, 0.10), 20, nil, 1)
  T.text(mLabel, vec2(x + 16, 29), 14, C.text, 'medium')
  local a = T.ease('master', St.master and 1 or 0, dt, 250)
  local sx = x + mw - 6 - 46
  ui.drawRectFilled(vec2(sx, 25), vec2(sx + 46, 53), T.mix(rgbm(1, 1, 1, 0.18), C.ok, a), 14)
  ui.drawCircleFilled(vec2(sx + 14 + 18 * a, 39), 11, C.white, 20)
  if mc then St.master = not St.master end
  x = x - 10
  local modes = { 'Basic', 'Advanced', 'Expert' }
  local widths = {}
  local segW = 6
  for i, m in ipairs(modes) do widths[i] = T.measure(m, 13, 'medium').x + 28; segW = segW + widths[i] end
  x = x - segW
  ui.drawRectFilled(vec2(x, 22), vec2(x + segW, 56), rgbm(1, 1, 1, 0.07), 20)
  ui.drawRect(vec2(x, 22), vec2(x + segW, 56), rgbm(1, 1, 1, 0.08), 20, nil, 1)
  local bx = x + 3
  for i, m in ipairs(modes) do
    local on = St.mode == m
    local c2 = W.hit('hdr_mode_' .. m, vec2(bx, 25), vec2(widths[i], 28))
    local s = T.ease('mode_' .. m, on and 1 or 0, dt, 250)
    if s > 0.01 then ui.drawRectFilled(vec2(bx, 25), vec2(bx + widths[i], 53), rgbm(1, 1, 1, s), 16) end
    T.textCentered(m, vec2(bx + widths[i] / 2, 39), 13, on and C.black or C.text2, 'medium')
    if c2 then St.mode = m end
    bx = bx + widths[i]
  end
  x = x - 10
  local rw = 8 + 18 + 8 + T.measure('Quick ring', 13, 'medium').x + 8 + 50
  x = x - rw
  local rc, rh = W.hit('hdr_ring', vec2(x, 19), vec2(rw, 40))
  ui.drawRectFilled(vec2(x, 19), vec2(x + rw, 59), rgbm(1, 1, 1, rh and 0.09 or 0.06), 20)
  ui.drawRect(vec2(x, 19), vec2(x + rw, 59), rgbm(1, 1, 1, 0.10), 20, nil, 1)
  local ic = vec2(x + 21, 39)
  ui.drawCircle(ic, 8, C.yellow, 20, 2); ui.drawCircle(ic, 3, C.yellow, 12, 2)
  T.text('Quick ring', vec2(x + 34, 30), 13, C.text, 'medium')
  local hx = x + 34 + T.measure('Quick ring', 13, 'medium').x + 8
  ui.drawRectFilled(vec2(hx, 29), vec2(hx + 44, 49), rgbm(1, 1, 1, 0.10), 5)
  T.text('Hold Q', vec2(hx + 5, 31.5), 11, C.text2)
  if rc then D.ringOpen = true; ring.reset() end
  -- drag zones in the empty parts of the header (no title bar)
  for i, z in ipairs({ { PAD + 310, cx - 12 }, { cx + 62 + wm + 12, x - 12 } }) do
    if z[2] > z[1] then
      local _, _, dragging = W.hit('hdr_drag' .. i, vec2(z[1], 8), vec2(z[2] - z[1], 62))
      if dragging then
        local w = ac.accessAppWindow('IMGUI_LUA_Lumicorsa_dashboard')
        if w then w:move(w:position() + ui.mouseDelta()) end
      end
    end
  end
  -- the line under the header with one amber light sweeping every 6 s
  ui.drawLine(vec2(0, 79), vec2(WIDTH, 79), rgbm(1, 1, 1, 0.05), 1)
  local ph = (t % 6) / 6
  local e = ph < 0.5 and 2 * ph * ph or 1 - (-2 * ph + 2) ^ 2 / 2
  local lx = (-0.3 + 1.6 * e) * WIDTH
  local lw = WIDTH * 0.3
  ui.drawRectFilledMultiColor(vec2(lx, 79), vec2(lx + lw / 2, 80), rgbm(1, 181 / 255, 71 / 255, 0), rgbm(1, 181 / 255, 71 / 255, 0.9), rgbm(1, 181 / 255, 71 / 255, 0.9), rgbm(1, 181 / 255, 71 / 255, 0))
  ui.drawRectFilledMultiColor(vec2(lx + lw / 2, 79), vec2(lx + lw, 80), rgbm(1, 181 / 255, 71 / 255, 0.9), rgbm(1, 181 / 255, 71 / 255, 0), rgbm(1, 181 / 255, 71 / 255, 0), rgbm(1, 181 / 255, 71 / 255, 0.9))
end

-- ---------------------------------------------------------------------------------------------- tabs strip
local function tabStrip(env, dt)
  local St = env.store
  local widths, total = {}, 8
  for i, id in ipairs(tabs.ORDER) do widths[i] = T.measure(tabs.LABELS[id], 15, 'medium').x + 40; total = total + widths[i] + 2 end
  local x = (WIDTH - total) / 2
  local y = 94
  ui.drawRectFilled(vec2(x, y), vec2(x + total, y + 50), rgbm(1, 1, 1, 0.05), 16)
  ui.drawRect(vec2(x, y), vec2(x + total, y + 50), rgbm(1, 1, 1, 0.08), 16, nil, 1)
  x = x + 4
  for i, id in ipairs(tabs.ORDER) do
    local on = St.tab == id
    local clicked, hovered = W.hit('tab_' .. id, vec2(x, y + 4), vec2(widths[i], 42))
    local a = T.ease('tab_' .. id, on and 1 or 0, dt, 300)
    if a > 0.01 then ui.drawRectFilled(vec2(x, y + 4), vec2(x + widths[i], y + 46), rgbm(1, 1, 1, 0.14 * a), 12) end
    T.textCentered(tabs.LABELS[id], vec2(x + widths[i] / 2, y + 25), 15, on and C.text or (hovered and C.text2 or C.muted), 'medium')
    if a > 0.01 then ui.drawRectFilled(vec2(x + 20, y + 38), vec2(x + widths[i] - 20, y + 40), T.alpha(C.amber, a), 1) end
    if clicked and not on then St.tab = id; scroll.grid[id] = scroll.grid[id] or 0 end
    x = x + widths[i] + 2
  end
end

-- ---------------------------------------------------------------------------------------------- stats rail
local function railCard(y, h) ui.drawRectFilled(vec2(PAD, y), vec2(PAD + RAIL, y + h), C.rail, 20); ui.drawRect(vec2(PAD, y), vec2(PAD + RAIL, y + h), C.line, 20, nil, 1) end

local function statsRail(env, top, bottom)
  local tel = env.telemetry
  ui.pushClipRect(vec2(PAD - 6, top), vec2(PAD + RAIL + 6, bottom), true)
  local y = top - scroll.rail
  -- FPS ring + 1% low + frame time + sparkline
  railCard(y, 144)
  local fps = tel.fps()
  local refresh = env.refresh()
  local c = vec2(PAD + 18 + 56, y + 16 + 56)
  local a0 = math.rad(135)
  ui.pathClear(); ui.pathArcTo(c, 46, a0, a0 + math.rad(270), 48); ui.pathStroke(rgbm(1, 1, 1, 0.08), false, 9)
  local f = T.ease('fpsring', math.min(1, fps / math.max(refresh * 1.15, 1)), env.dt)
  if f > 0.002 then ui.pathClear(); ui.pathArcTo(c, 46, a0, a0 + math.rad(270) * f, 48); ui.pathStroke(C.white, false, 9) end
  T.textCentered(string.format('%d', math.floor(fps + 0.5)), c - vec2(0, 6), 32, C.text, 'mono')
  T.textCentered('fps', c + vec2(0, 20), 12, C.muted)
  local rx, rw = PAD + 18 + 112 + 14, RAIL - 18 - 112 - 14 - 18
  local low = tel.low1()
  T.text('1% low', vec2(rx, y + 22), 13, C.muted); T.monoRight(low and string.format('%d fps', math.floor(low)) or '…', vec2(rx + rw, y + 22), 13, C.text)
  T.text('Frame time', vec2(rx, y + 44), 13, C.muted); T.monoRight(string.format('%.1f ms', tel.frameTime()), vec2(rx + rw, y + 44), 13, C.text)
  local sp = tel.sparkline()
  if #sp > 1 then
    local mn, mx = math.huge, -math.huge
    for _, v in ipairs(sp) do mn, mx = math.min(mn, v), math.max(mx, v) end
    if mx - mn < 4 then mx = mn + 4 end
    local sy0, sh = y + 72, 42
    ui.pathClear()
    for i, v in ipairs(sp) do ui.pathLineTo(vec2(rx + rw * (i - 1) / 59, sy0 + sh - (v - mn) / (mx - mn) * (sh - 2))) end
    ui.pathStroke(T.hex('#9CC9FF'), false, 1.6)
  end
  y = y + 144 + 12
  -- frame time histogram, last 15 s
  railCard(y, 96)
  local target = 1000 / refresh
  T.text('Frame time, last 15 s', vec2(PAD + 18, y + 14), 13, C.text2)
  T.textRight(string.format('target %.1f ms', target), vec2(PAD + RAIL - 18, y + 14), 13, T.hex('#6E7178'))
  local bars = tel.histogram()
  local bx0, bw, by1, bh = PAD + 18, (RAIL - 36) / 40, y + 86, 52
  local scale = target * 2
  ui.drawLine(vec2(bx0, by1 - bh * target / scale), vec2(bx0 + RAIL - 36, by1 - bh * target / scale), rgbm(245 / 255, 197 / 255, 24 / 255, 0.5), 1)
  for i, ms in ipairs(bars) do
    local h = math.min(1, ms / scale) * bh
    ui.drawRectFilled(vec2(bx0 + (i - 1) * bw, by1 - h), vec2(bx0 + i * bw - 2, by1), ms > target * 1.04 and C.yellow or rgbm(1, 1, 1, 0.5), 2)
  end
  y = y + 96 + 12
  -- donuts: only what Lua can read (CPU load, VRAM). There's no GPU-load getter, so no GPU donut.
  local cpu = tel.cpuLoad()
  local vu, vb = tel.vram()
  local donuts = {}
  if cpu then donuts[#donuts + 1] = { 'CPU', cpu / 100, string.format('%d%%', math.floor(cpu + 0.5)), C.text2 } end
  if vu then donuts[#donuts + 1] = { 'VRAM', vu / vb, string.format('%.1fG', vu / 1024 ^ 3), C.blue } end
  if #donuts > 0 then
    railCard(y, 112)
    for i, d in ipairs(donuts) do
      local dc = vec2(PAD + RAIL * (i - 0.5) / #donuts, y + 14 + 37)
      ui.drawCircle(dc, 30, rgbm(1, 1, 1, 0.08), 40, 7)
      local fr = T.ease('donut' .. i, math.max(0, math.min(1, d[2])), env.dt)
      if fr > 0.002 then ui.pathClear(); ui.pathArcTo(dc, 30, -math.pi / 2, -math.pi / 2 + fr * math.pi * 2, 40); ui.pathStroke(d[4], false, 7) end
      T.textCentered(d[3], dc, 15, C.text, 'mono')
      T.textCentered(d[1], dc + vec2(0, 47), 12, C.muted)
    end
    y = y + 112 + 12
  end
  -- where the frame time goes: measured effect costs plus Lumicorsa's own UI/HUD CPU time
  local items = {}
  local COL = { neural = C.blue, exposure = C.text2, bloom = C.yellow, sun = T.hex('#FFB547'), ao = C.white, detail = T.hex('#7CB6FF'),
    dof = T.hex('#C9D6F2'), mist = T.hex('#9CC9FF'), grade = C.red }
  if tel.costs.measuredAt then
    for _, g in ipairs(tel.GROUPS) do
      if tel.costs[g] and tel.costs[g] > 0.005 then items[#items + 1] = { tel.GROUP_LABELS[g], tel.costs[g], COL[g] } end
    end
  end
  items[#items + 1] = { 'Panel (CPU)', tel.ui.avg, T.hex('#6B6E75') }
  items[#items + 1] = { 'HUD (CPU)', tel.hud.avg, T.hex('#4A4C52') }
  local total = 0
  for _, it in ipairs(items) do total = total + it[2] end
  local rows = math.ceil(#items / 2)
  local ch = 14 + 20 + 10 + 10 + 10 + rows * 18 + (tel.costs.measuredAt and 0 or 18) + 10
  railCard(y, ch)
  T.text('Where the frame time goes', vec2(PAD + 18, y + 14), 13, C.text2)
  T.monoRight(string.format('%.2f ms', total), vec2(PAD + RAIL - 18, y + 14), 13, C.text)
  local barW = RAIL - 36
  local bx = PAD + 18
  for _, it in ipairs(items) do
    local w = barW * it[2] / math.max(total, 1e-6)
    if w > 1 then ui.drawRectFilled(vec2(bx, y + 44), vec2(bx + w - 2, y + 54), it[3], 2); bx = bx + w end
  end
  for i, it in ipairs(items) do
    local col, row = (i - 1) % 2, math.floor((i - 1) / 2)
    local ix = PAD + 18 + col * (barW / 2 + 5)
    local iy = y + 64 + row * 18
    ui.drawRectFilled(vec2(ix, iy + 3), vec2(ix + 8, iy + 11), it[3], 2)
    T.text(it[1], vec2(ix + 14, iy), 12, C.text2)
    T.monoRight(string.format('%.2f', it[2]), vec2(ix + barW / 2 - 5, iy), 12, C.text)
  end
  if not tel.costs.measuredAt then T.text('Effects not measured yet: System › Measure effect costs', vec2(PAD + 18, y + 64 + rows * 18), 11, C.faint) end
  y = y + ch + 12
  -- running
  local run = env.running()
  local rh = 14 + #run * 22 + 10
  railCard(y, rh)
  for i, r in ipairs(run) do
    local ry = y + 14 + (i - 1) * 22
    T.text(r[1], vec2(PAD + 18, ry), 13, C.muted)
    local vw = T.measure(r[2], 13).x
    ui.drawCircleFilled(vec2(PAD + RAIL - 18 - vw - 11, ry + 8), 3.5, r[3], 10)
    T.textRight(r[2], vec2(PAD + RAIL - 18, ry), 13, C.text)
  end
  y = y + rh + 12
  ui.popClipRect()
  return y + scroll.rail - top
end

-- ---------------------------------------------------------------------------------------------- cards
local CARD_PAD_X, CARD_PAD_Y, ROW_GAP = 18, 16, 13
local function rowsFor(card, mode)
  if mode == 'Basic' then return { card.rows[1], card.rows[2] } end
  return card.rows
end

local function cardHeight(card, w, mode)
  local h = CARD_PAD_Y * 2 + 22
  for _, r in ipairs(rowsFor(card, mode)) do h = h + ROW_GAP + W[r.w].height(r, w - CARD_PAD_X * 2) end
  return h
end

local function costChip(env, card)
  local tel = env.telemetry
  local groups = type(card.cost) == 'table' and card.cost or { card.cost }
  if groups[1] == 'free' then return 'free', 0 end
  if groups[1] == 'csp' then return 'CSP', nil end
  if not tel.costs.measuredAt then return '— ms', nil end
  local sum = 0
  for _, g in ipairs(groups) do sum = sum + (tel.costs[g] or 0) end
  return string.format('%.2f ms', sum), sum
end

local function drawCard(env, card, p, w, h, ctx)
  local t = now()
  ui.drawRectFilled(p, p + vec2(w, h), C.card, 20)
  local fl = flash and flash.tab == card.tab and flash.card == card.title and (t - flash.t0) < 2.8
  local border = rgbm(1, 1, 1, 0.08)
  if fl then
    local ph = ((t - flash.t0) % 1.4) / 1.4
    local a = ph < 0.3 and ph / 0.3 or 1 - (ph - 0.3) / 0.7
    border = rgbm(245 / 255, 197 / 255, 24 / 255, 0.9 * a)
    ui.drawRect(p - vec2(3, 3), p + vec2(w + 3, h + 3), border, 23, nil, 3)
  end
  ui.drawRect(p, p + vec2(w, h), border, 20, nil, 1)
  T.text(card.title, p + vec2(CARD_PAD_X, CARD_PAD_Y), 16, C.text, 'medium')
  local label, ms = costChip(env, card)
  local cw = T.measure(label, 12, 'mono').x + 16
  local cbg, cfg = rgbm(1, 1, 1, 0.07), C.text2
  if ms and ms > 0.6 then cbg, cfg = rgbm(229 / 255, 56 / 255, 59 / 255, 0.18), T.hex('#FF8A8C')
  elseif ms and ms > 0.3 then cbg, cfg = rgbm(245 / 255, 197 / 255, 24 / 255, 0.16), T.hex('#FFE27A') end
  local cp = p + vec2(w - CARD_PAD_X - cw, CARD_PAD_Y)
  ui.drawRectFilled(cp, cp + vec2(cw, 20), cbg, 8)
  T.mono(label, cp + vec2(8, 3), 12, cfg)
  local y = p.y + CARD_PAD_Y + 22
  local rw = w - CARD_PAD_X * 2
  for _, r in ipairs(rowsFor(card, env.store.mode)) do
    y = y + ROW_GAP
    W[r.w].draw(r, vec2(p.x + CARD_PAD_X, y), rw, ctx)
    y = y + W[r.w].height(r, rw)
  end
end

local function cardGrid(env, cards, top, bottom, ctx)
  local St = env.store
  local x0 = PAD + RAIL + GAP
  local gw = WIDTH - PAD - x0
  local cw = (gw - 28) / 3
  local sc = scroll.grid[St.tab] or 0
  ui.pushClipRect(vec2(x0 - 6, top), vec2(WIDTH - PAD + 6, bottom), true)
  local y = top - sc
  if St.tab == 'look' then
    local def = env.R.get('preset')
    if def then W.scenes(def, vec2(x0, y), gw, ctx, env.presetCost); y = y + 52 + 14 end
  end
  for i = 1, #cards, 3 do
    local rowH = 0
    for j = 0, 2 do local c = cards[i + j]; if c then rowH = math.max(rowH, cardHeight(c, cw, St.mode)) end end
    if y + rowH > top and y < bottom then
      for j = 0, 2 do
        local c = cards[i + j]
        if c then drawCard(env, c, vec2(x0 + j * (cw + 14), y), cw, cardHeight(c, cw, St.mode), ctx) end
      end
    end
    y = y + rowH + 14
  end
  ui.popClipRect()
  return y + sc - top
end

-- Scroll a region with the mouse wheel (no scrollbars, as designed).
local function wheel(key, sub, p1, p2, content)
  local m = ui.mouseLocalPos()
  local view = p2.y - p1.y
  local cur = sub and scroll.grid[sub] or scroll.rail
  if ui.windowHovered() and m.x >= p1.x and m.x <= p2.x and m.y >= p1.y and m.y <= p2.y then cur = cur - ui.mouseWheel() * 80 end
  cur = math.max(0, math.min(cur, math.max(content - view, 0)))
  if sub then scroll.grid[sub] = cur else scroll.rail = cur end
end

-- ---------------------------------------------------------------------------------------------- modal
local function drawModal(env, dt)
  local m = D.modal
  if not m then return end
  ui.drawRectFilled(vec2(), D.SIZE, rgbm(0, 0, 0, 0.35), 28)
  local w, h = 560, m.height or 300
  local p1 = vec2((WIDTH - w) / 2, (HEIGHT - h) / 2)
  ui.drawRectFilled(p1, p1 + vec2(w, h), rgbm(16 / 255, 17 / 255, 20 / 255, 0.96), 22)
  ui.drawRect(p1, p1 + vec2(w, h), rgbm(1, 1, 1, 0.16), 22, nil, 1)
  T.text(m.title, p1 + vec2(24, 22), 20, C.text, 'medium')
  if m.body then m.body(p1 + vec2(24, 62), w - 48, dt) end
  local bx = p1.x + w - 24
  for i = #m.buttons, 1, -1 do
    local b = m.buttons[i]
    local bw = T.measure(b.label, 14, 'medium').x + 36
    bx = bx - bw
    local clicked, hovered = W.hit('modal_b' .. i, vec2(bx, p1.y + h - 62), vec2(bw, 42))
    local primary = i == #m.buttons
    ui.drawRectFilled(vec2(bx, p1.y + h - 62), vec2(bx + bw, p1.y + h - 20), primary and (hovered and T.hex('#E6E7EA') or C.white) or rgbm(1, 1, 1, hovered and 0.1 or 0.06), 12)
    T.textCentered(b.label, vec2(bx + bw / 2, p1.y + h - 41), 14, primary and C.black or C.text, 'medium')
    if clicked then local keep = b.on and b.on(); if not keep then D.modal = nil end end
    bx = bx - 10
  end
end

function D.flash(tab, card) flash = { tab = tab, card = card, t0 = now() } end

-- ---------------------------------------------------------------------------------------------- frame
function D.draw(env, built)
  local St = env.store
  local dt = env.dt
  local t = now()
  -- glass: one blurred backdrop of the game frame, tint, dot grid, border
  local pos = ui.windowPos()
  local screen = ac.getUI().windowSize
  ui.drawImageRounded(env.glass(), vec2(), D.SIZE, C.white, vec2(pos.x / screen.x, pos.y / screen.y),
    vec2((pos.x + WIDTH) / screen.x, (pos.y + HEIGHT) / screen.y), T.R.window)
  ui.drawRectFilled(vec2(), D.SIZE, C.glass, T.R.window)
  ui.drawImage(env.dotgrid, vec2(), D.SIZE, C.white)
  ui.drawRect(vec2(), D.SIZE, C.border, T.R.window, nil, 1)
  header(env, t, dt)
  tabStrip(env, dt)
  local top, bottom = 160, HEIGHT - 32
  local ctx = { dt = dt, mode = St.mode, values = env.values, store = St, drawCluster = env.drawClusterPreview, sunElevation = env.sunElevation,
    refresh = env.refresh, tierFps = env.tierFps }
  local railH = statsRail(env, top, bottom)
  wheel('rail', nil, vec2(PAD, top), vec2(PAD + RAIL, bottom), railH)
  local gridH = cardGrid(env, built[St.tab] or {}, top, bottom, ctx)
  wheel('grid', St.tab, vec2(PAD + RAIL + GAP, top), vec2(WIDTH - PAD, bottom), gridH)
  T.monoRight('v' .. env.version, vec2(WIDTH - PAD, HEIGHT - 24), 12, C.faint)
  if D.ringOpen then
    ui.drawRectFilled(vec2(), D.SIZE, rgbm(0, 0, 0, 0.45), 28)
    ring.draw(env.ringItems, D.SIZE / 2, ui.mouseLocalPos(), dt, true)
    if ui.mouseClicked(ui.MouseButton.Right) or ui.keyPressed(ui.Key.Escape) then D.ringOpen = false end
    local m = ui.mouseLocalPos() - D.SIZE / 2
    if ui.mouseClicked(ui.MouseButton.Left) and math.sqrt(m.x * m.x + m.y * m.y) > 230 then D.ringOpen = false end
  end
  palette.draw(env.paletteEntries, D.SIZE, dt, function (e)
    St.tab = e.tab
    D.flash(e.tab, e.card)
    if e.action and e.action.run then e.action.run() end
  end)
  drawModal(env, dt)
end

return D
