--[[
  Lumicorsa widgets: every control type from the design, built once here and bound to registry entries.

  Each widget has height(row, w) and draw(row, p, w, ctx). Coordinates are window-local. Fills and knobs ease toward
  their value over 450 ms. A locked entry (online server rules, missing car feature) draws dimmed with its reason and
  ignores input. In Expert mode each control shows a "reset" link and its raw config key as a tooltip.
]]

local T = require('ui/theme')
local C = T.C

local W = {}

-- ---------------------------------------------------------------------------------------------- input helpers
local function hit(id, p, size)
  ui.setCursor(p)
  local clicked = ui.invisibleButton(id, size)
  return clicked, ui.itemHovered(), ui.itemActive()
end
W.hit = hit

local function mouse() return ui.mouseLocalPos() end

local function clamp(x, a, b) return math.max(a, math.min(b, x)) end
local function frac(def, v) return clamp(((v or def.min) - def.min) / math.max(def.max - def.min, 1e-6), 0, 1) end
local function fromFrac(def, t)
  local v = def.min + (def.max - def.min) * clamp(t, 0, 1)
  if def.snap then return def.snap(v) end
  if def.step and def.step > 0 then v = def.min + math.floor((v - def.min) / def.step + 0.5) * def.step end
  return v
end

-- Applies a new value: sliders write live while dragging (config writes are debounced inside set()).
local function commit(def, v) if def.set then def.set(v) end end

local APPLY = { restart = { 'Restart', C.amber }, next = { 'Next launch', C.yellow }, session = { 'Next session', C.yellow } }

-- Label line shared by most controls: label (+ apply badge), right side value text, Expert reset + tooltip.
local function header(def, p, w, ctx, valueText, lockedReason)
  local col = lockedReason and C.faint or C.text2
  T.text(def.label, p, 14, col)
  local lx = p.x + T.measure(def.label, 14).x + 8
  local badge = APPLY[def.apply]
  if badge then
    local bw = T.measure(badge[1], 10.5, 'medium').x + 12
    ui.drawRectFilled(vec2(lx, p.y + 1), vec2(lx + bw, p.y + 17), T.alpha(badge[2], 0.16), 6)
    T.text(badge[1], vec2(lx + 6, p.y + 2.5), 10.5, badge[2], 'medium')
    lx = lx + bw + 6
  end
  if ctx.mode == 'Expert' and def.default ~= nil and def.set and not lockedReason then
    local rw = T.measure('reset', 11).x
    local clicked, hovered = hit(def.id .. '_reset', vec2(lx, p.y), vec2(rw, 18))
    T.text('reset', vec2(lx, p.y + 2), 11, hovered and C.amber or C.faint)
    if clicked then commit(def, def.default) end
  end
  if valueText then T.monoRight(valueText, vec2(p.x + w, p.y + 1), 13, lockedReason and C.faint or C.text) end
end

local function tooltip(def, ctx)
  if ctx.mode == 'Expert' and def.key and ui.itemHovered() then ui.setTooltip(def.key) end
end

local function lockLine(reason, p, w)
  if reason then T.text('🔒 ' .. reason, p, 12, C.amber) end
end

local function lockedOf(def) return def and def.locked and def.locked() or nil end

-- ---------------------------------------------------------------------------------------------- slider
W.slider = {
  height = function (row) return 42 + (lockedOf(row.def) and 18 or 0) end,
  draw = function (row, p, w, ctx)
    local def = row.def
    local lock = lockedOf(def)
    local v = def.get()
    header(def, p, w, ctx, def.fmt and def.fmt(v or 0) or tostring(v), lock)
    local ty = p.y + 22
    local clicked, hovered, active = hit(def.id, vec2(p.x, ty), vec2(w, 22))
    tooltip(def, ctx)
    if active and not lock then
      local nv = fromFrac(def, (mouse().x - p.x) / w)
      if nv ~= v then commit(def, nv); v = nv end
    end
    local f = T.ease(def.id, frac(def, v), ctx.dt)
    ui.drawRectFilled(vec2(p.x, ty + 9), vec2(p.x + w, ty + 13), C.fill, 2)
    if def.default then
      local dx = p.x + w * frac(def, def.default)
      ui.drawRectFilled(vec2(dx - 1, ty + 5), vec2(dx + 1, ty + 17), rgbm(1, 1, 1, 0.25))
    end
    ui.drawRectFilledMultiColor(vec2(p.x, ty + 9), vec2(p.x + w * f, ty + 13), C.text2, C.white, C.white, C.text2)
    local kx = p.x + w * f
    if hovered or active then ui.drawCircleFilled(vec2(kx, ty + 11), 12, rgbm(1, 1, 1, 0.12), 24) end
    ui.drawCircleFilled(vec2(kx, ty + 11), 8, lock and C.faint or C.white, 24)
    lockLine(lock, vec2(p.x, p.y + 44), w)
  end,
}

-- ---------------------------------------------------------------------------------------------- knobs (270° arc)
local KNOB_COLOURS = { C.white, C.yellow, C.blue }
W.knobs = {
  height = function () return 98 end,
  draw = function (row, p, w, ctx)
    local n = #row.defs
    local cw = w / 3
    for i, def in ipairs(row.defs) do
      local cx = p.x + cw * (i - 0.5)
      local c = vec2(cx, p.y + 36)
      local lock = lockedOf(def)
      local v = def.get()
      local clicked, hovered, active = hit(def.id, c - vec2(36, 36), vec2(72, 72))
      tooltip(def, ctx)
      if active and not lock then
        local d = ui.mouseDelta()
        local nv = fromFrac(def, frac(def, v) + (d.x - d.y) / 160)
        if nv ~= v then commit(def, nv); v = nv end
      end
      local f = T.ease(def.id, frac(def, v), ctx.dt)
      local a0 = math.rad(135)
      ui.pathClear(); ui.pathArcTo(c, 30, a0, a0 + math.rad(270), 40); ui.pathStroke(rgbm(1, 1, 1, 0.10), false, 5)
      if f > 0.002 then
        ui.pathClear(); ui.pathArcTo(c, 30, a0, a0 + math.rad(270) * f, 40)
        ui.pathStroke(lock and C.faint or (row.colours and row.colours[i] or KNOB_COLOURS[i]), false, 5)
      end
      ui.drawCircleFilled(c, 21, T.hex('#1A1B1F'), 32)
      ui.drawCircle(c, 21, rgbm(1, 1, 1, (hovered or active) and 0.3 or 0.14), 32, 1)
      local ang = math.rad(-135 + 270 * f - 90)
      ui.drawLine(c + vec2(math.cos(ang), math.sin(ang)) * 9, c + vec2(math.cos(ang), math.sin(ang)) * 18, C.white, 2.6)
      T.textCentered(def.fmt and def.fmt(v or 0) or tostring(v), c + vec2(0, 4), 12, lock and C.faint or C.text, 'mono')
      T.textCentered(def.label, vec2(cx, p.y + 84), 12, C.text2)
    end
  end,
}

-- ---------------------------------------------------------------------------------------------- white balance XY pad
W.xy = {
  height = function () return 148 end,
  draw = function (row, p, w, ctx)
    local dt, dn = row.defs[1], row.defs[2]   -- temperature (-100..100), tint (-100..100)
    local tx, ty = frac(dt, dt.get()), 1 - frac(dn, dn.get())
    local kelvin = math.floor(3200 + tx * 5800)
    header({ label = row.label or 'Temperature and tint', id = dt.id .. '_xyh' }, p, w, ctx,
      string.format('%d K, tint %+d', kelvin, math.floor((0.5 - ty) * 40 + 0.5)))
    local p1, p2 = vec2(p.x, p.y + 24), vec2(p.x + w, p.y + 144)
    ui.drawRectFilledMultiColor(p1, p2, rgbm(90 / 255, 150 / 255, 1, 0.55), rgbm(1, 170 / 255, 70 / 255, 0.55), rgbm(1, 170 / 255, 70 / 255, 0.55), rgbm(90 / 255, 150 / 255, 1, 0.55))
    ui.drawRectFilledMultiColor(p1, p2, rgbm(220 / 255, 90 / 255, 220 / 255, 0.35), rgbm(220 / 255, 90 / 255, 220 / 255, 0.35), rgbm(90 / 255, 220 / 255, 120 / 255, 0.35), rgbm(90 / 255, 220 / 255, 120 / 255, 0.35))
    ui.drawRect(p1, p2, rgbm(1, 1, 1, 0.12), 12, nil, 1)
    ui.drawLine(vec2((p1.x + p2.x) / 2, p1.y), vec2((p1.x + p2.x) / 2, p2.y), rgbm(1, 1, 1, 0.18), 1)
    ui.drawLine(vec2(p1.x, (p1.y + p2.y) / 2), vec2(p2.x, (p1.y + p2.y) / 2), rgbm(1, 1, 1, 0.18), 1)
    local _, hovered, active = hit(dt.id .. '_xy', p1, p2 - p1)
    if active then
      local m = mouse()
      commit(dt, fromFrac(dt, (m.x - p1.x) / w))
      commit(dn, fromFrac(dn, 1 - (m.y - p1.y) / (p2.y - p1.y)))
    end
    local ex, ey = T.ease(dt.id .. '_x', tx, ctx.dt, 350), T.ease(dn.id .. '_y', ty, ctx.dt, 350)
    local k = vec2(p1.x + w * ex, p1.y + (p2.y - p1.y) * ey)
    ui.drawCircleFilled(k, 9, rgbm(0, 0, 0, 0.25), 20)
    ui.drawCircle(k, 9, C.white, 20, 2)
    T.text('Cool', vec2(p1.x + 8, p2.y - 18), 11, rgbm(1, 1, 1, 0.75))
    T.textRight('Warm', vec2(p2.x - 8, p2.y - 18), 11, rgbm(1, 1, 1, 0.75))
  end,
}

-- ---------------------------------------------------------------------------------------------- live tone curve
-- Mirrors the shader's display mapping for a grey ramp: filmic shoulder (highlight roll-off), contrast, shadow lift.
local function filmic(x)
  local y = x * 0.72
  y = math.max(0, math.min(1, (y * (2.51 * y + 0.03)) / (y * (2.43 * y + 0.59) + 0.14))) / 0.95
  return math.max(0, math.min(1, x + (y - x) * math.min(1, x / 0.18)))
end
function W.curveAt(x, v)
  local ldr = math.min(x, 1) + (filmic(x) - math.min(x, 1)) * v.PL_FilmicStrength
  local g = (ldr - 0.18) * (1 + v.PL_Contrast) + 0.18
  local s = math.max(0, math.min(1, g))
  g = g + v.PL_Lift * 0.08 * (1 - s) * (1 - s)
  return math.max(0, math.min(1, g))
end
local function toLin(c) return c <= 0.04045 and c / 12.92 or ((c + 0.055) / 1.055) ^ 2.4 end
local function toGam(c) c = math.max(0, math.min(1, c)); return c <= 0.0031308 and c * 12.92 or 1.055 * c ^ (1 / 2.4) - 0.055 end

W.curve = {
  height = function () return 148 end,
  draw = function (row, p, w, ctx)
    T.text(row.label or 'Response', p, 14, C.text2)
    T.textRight('Moves with the sliders', vec2(p.x + w, p.y + 2), 12, T.hex('#8A8D94'))
    local p1, p2 = vec2(p.x, p.y + 24), vec2(p.x + w, p.y + 144)
    local gh = p2.y - p1.y
    ui.drawRectFilled(p1, p2, rgbm(1, 1, 1, 0.04), 12)
    for i = 1, 3 do
      ui.drawLine(vec2(p1.x + w * i / 4, p1.y), vec2(p1.x + w * i / 4, p2.y), rgbm(1, 1, 1, 0.06), 1)
      ui.drawLine(vec2(p1.x, p1.y + gh * i / 4), vec2(p2.x, p1.y + gh * i / 4), rgbm(1, 1, 1, 0.06), 1)
    end
    ui.drawLine(vec2(p1.x, p2.y), vec2(p2.x, p1.y), rgbm(1, 1, 1, 0.18), 1)
    local v = ctx.values
    local function y(x) return toGam(W.curveAt(toLin(x), v)) end
    ui.pathClear()
    for i = 0, 40 do local x = i / 40; ui.pathLineTo(vec2(p1.x + w * x, p2.y - gh * y(x))) end
    ui.pathStroke(C.white, false, 2.4)
    ui.drawCircleFilled(vec2(p1.x + w * 0.85, p2.y - gh * y(0.85)), 4, C.yellow, 16)
    ui.drawCircleFilled(vec2(p1.x + w * 0.15, p2.y - gh * y(0.15)), 4, C.blue, 16)
  end,
}

-- ---------------------------------------------------------------------------------------------- segmented
W.seg = {
  height = function (row) return 62 + (lockedOf(row.def) and 18 or 0) end,
  draw = function (row, p, w, ctx)
    local def = row.def
    local lock = lockedOf(def)
    header(def, p, w, ctx, nil, lock)
    local opts = def.options or {}
    local y = p.y + 24
    ui.drawRectFilled(vec2(p.x, y), vec2(p.x + w, y + 38), rgbm(1, 1, 1, 0.07), 11)
    local cur = def.get()
    local sw = (w - 6) / math.max(#opts, 1)
    for i, o in ipairs(opts) do
      local sp = vec2(p.x + 3 + (i - 1) * sw, y + 3)
      local clicked, hovered = hit(def.id .. '_' .. i, sp, vec2(sw, 32))
      tooltip(def, ctx)
      local on = tostring(o.value) == tostring(cur)
      local a = T.ease(def.id .. '_' .. i, on and 1 or 0, ctx.dt, 250)
      if a > 0.01 then ui.drawRectFilled(sp, sp + vec2(sw, 32), rgbm(1, 1, 1, a * (lock and 0.4 or 1)), 9) end
      if hovered and not on and not lock then ui.drawRectFilled(sp, sp + vec2(sw, 32), rgbm(1, 1, 1, 0.06), 9) end
      local label = o.label
      local maxW = sw - 10
      if T.measure(label, 13, 'medium').x > maxW then label = label:gsub('%s*%b()', '') end
      T.textCentered(label, sp + vec2(sw / 2, 16), 13, on and C.black or (lock and C.faint or C.text2), 'medium')
      if clicked and not on and not lock then commit(def, o.value) end
    end
    lockLine(lock, vec2(p.x, y + 42), w)
  end,
}

-- ---------------------------------------------------------------------------------------------- toggle with hint
W.toggle = {
  height = function (row) return (row.def.hint and row.def.hint ~= '' and 44 or 34) + (lockedOf(row.def) and 18 or 0) end,
  draw = function (row, p, w, ctx)
    local def = row.def
    local lock = lockedOf(def)
    local on = def.get() and true or false
    local h = W.toggle.height(row) - (lock and 18 or 0)
    local clicked, hovered = hit(def.id, p, vec2(w, h))
    tooltip(def, ctx)
    T.text(def.label, vec2(p.x, p.y + (def.hint and def.hint ~= '' and 2 or 8)), 14, lock and C.faint or C.text2)
    local badge = APPLY[def.apply]
    if badge then
      local lx = p.x + T.measure(def.label, 14).x + 8
      local bw = T.measure(badge[1], 10.5, 'medium').x + 12
      local by = p.y + (def.hint and def.hint ~= '' and 3 or 9)
      ui.drawRectFilled(vec2(lx, by), vec2(lx + bw, by + 16), T.alpha(badge[2], 0.16), 6)
      T.text(badge[1], vec2(lx + 6, by + 1.5), 10.5, badge[2], 'medium')
    end
    if def.hint and def.hint ~= '' then T.text(def.hint, vec2(p.x, p.y + 22), 12, C.hint) end
    local a = T.ease(def.id, on and 1 or 0, ctx.dt, 250)
    local sx, sy = p.x + w - 42, p.y + (h - 24) / 2
    ui.drawRectFilled(vec2(sx, sy), vec2(sx + 42, sy + 24), T.mix(rgbm(1, 1, 1, 0.16), C.blue, a), 12)
    ui.drawCircleFilled(vec2(sx + 12 + 18 * a, sy + 12), 9, lock and C.faint or C.white, 20)
    if hovered and not lock then ui.drawRect(vec2(sx - 2, sy - 2), vec2(sx + 44, sy + 26), rgbm(1, 1, 1, 0.25), 13, nil, 1) end
    if clicked and not lock then commit(def, not on) end
    lockLine(lock, vec2(p.x, p.y + h), w)
  end,
}

-- ---------------------------------------------------------------------------------------------- look blender
W.mixer = {
  height = function () return 72 end,
  draw = function (row, p, w, ctx)
    local blend, pair = row.defs[1], row.defs[2]
    local v = blend.get()
    local a, b = 'Photoreal', pair.get()
    local ca, cb = T.hex('#FFE27A'), ({ ['Night run'] = T.hex('#9CC9FF'), ['Golden hour'] = T.hex('#FFB547'), ['Rain run'] = T.hex('#7CB6FF') })[b] or C.blue
    T.text(a, vec2(p.x + 22, p.y), 14, C.text)
    ui.drawCircleFilled(vec2(p.x + 8, p.y + 9), 7, ca, 16)
    T.textCentered(string.format('%d / %d', 100 - math.floor(v + 0.5), math.floor(v + 0.5)), vec2(p.x + w / 2, p.y + 9), 13, C.text2, 'mono')
    T.textRight(b, vec2(p.x + w - 22, p.y), 14, C.text)
    ui.drawCircleFilled(vec2(p.x + w - 8, p.y + 9), 7, cb, 16)
    local ty = p.y + 30
    ui.drawRectFilledMultiColor(vec2(p.x, ty + 11), vec2(p.x + w, ty + 19), T.alpha(ca, 0.75), T.alpha(cb, 0.75), T.alpha(cb, 0.75), T.alpha(ca, 0.75))
    local _, hovered, active = hit(blend.id, vec2(p.x, ty), vec2(w, 30))
    tooltip(blend, ctx)
    if active then
      local nv = math.floor(clamp((mouse().x - p.x) / w, 0, 1) * 100 + 0.5)
      if nv ~= v then commit(blend, nv); v = nv end
    end
    local f = T.ease(blend.id, v / 100, ctx.dt)
    local kx = p.x + (w - 28) * f
    ui.drawRectFilled(vec2(kx, ty + 1), vec2(kx + 28, ty + 29), C.white, 9)
    for i = -1, 1 do ui.drawLine(vec2(kx + 14 + i * 5, ty + 9), vec2(kx + 14 + i * 5, ty + 21), C.black, 2) end
  end,
}

-- ---------------------------------------------------------------------------------------------- day strip
local DAY_STOPS = { { 0, '#0B1530' }, { 0.18, '#0B1530' }, { 0.26, '#E39A5C' }, { 0.36, '#8CB4E6' }, { 0.64, '#8CB4E6' },
  { 0.74, '#E58D4E' }, { 0.82, '#22234A' }, { 1, '#0B1530' } }
W.daystrip = {
  height = function (row) return 158 + (lockedOf(row.def) and 18 or 0) end,
  draw = function (row, p, w, ctx)
    local def = row.def
    local lock = lockedOf(def)
    local t = def.get()
    local hh, mm = math.floor(t), math.floor((t % 1) * 60)
    T.text('Time of day', p, 14, lock and C.faint or C.text2)
    T.monoRight(string.format('%02d:%02d', hh, mm), vec2(p.x + w, p.y + 1), 13, C.text)
    local p1, p2 = vec2(p.x, p.y + 26), vec2(p.x + w, p.y + 136)
    for i = 1, #DAY_STOPS - 1 do
      local a, b = DAY_STOPS[i], DAY_STOPS[i + 1]
      local x1, x2 = p1.x + w * a[1], p1.x + w * b[1]
      ui.drawRectFilledMultiColor(vec2(x1, p1.y), vec2(x2, p2.y), T.hex(a[2]), T.hex(b[2]), T.hex(b[2]), T.hex(a[2]))
    end
    ui.drawRect(p1, p2, rgbm(1, 1, 1, 0.12), 14, nil, 1)
    local hgt = p2.y - p1.y
    local function el(x) return math.sin(math.pi * (x - 6) / 12) end
    ui.drawLine(vec2(p1.x, p1.y + hgt * 80 / 110), vec2(p2.x, p1.y + hgt * 80 / 110), rgbm(1, 1, 1, 0.45), 1)
    ui.pathClear()
    for i = 0, 48 do local x = i / 2; ui.pathLineTo(vec2(p1.x + w * x / 24, p1.y + hgt * (80 - el(x) * 64) / 110)) end
    ui.pathStroke(rgbm(1, 1, 1, 0.85), false, 1.6)
    local clicked, hovered, active = hit(def.id, p1, p2 - p1)
    tooltip(def, ctx)
    if (clicked or active) and not lock then
      local nt = clamp((mouse().x - p1.x) / w * 24, 0, 23.99)
      if math.abs(nt - t) > 0.02 then commit(def, nt); t = nt end
    end
    local ex = T.ease(def.id, t / 24, ctx.dt, 400)
    local e = el(ex * 24)
    local sun = vec2(p1.x + w * ex, p1.y + hgt * (80 - e * 64) / 110)
    ui.drawLine(vec2(sun.x, p1.y), vec2(sun.x, p2.y), C.white, 2)
    local sunC = e > 0.15 and T.hex('#FFE27A') or e > -0.1 and T.hex('#FF9A4A') or T.hex('#C9D6F2')
    ui.drawCircleFilled(sun, 14, T.alpha(sunC, 0.25), 20)
    ui.drawCircleFilled(sun, 9, sunC, 20)
    T.text('00:00', vec2(p1.x + 8, p2.y - 17), 11, rgbm(1, 1, 1, 0.8))
    T.textCentered('12:00', vec2(p1.x + w / 2, p2.y - 11), 11, rgbm(0, 0, 0, 0.6))
    T.textRight('24:00', vec2(p2.x - 8, p2.y - 17), 11, rgbm(1, 1, 1, 0.8))
    local elev = ctx.sunElevation and ctx.sunElevation()
    T.text(elev and (elev > 0 and string.format('Sun %d° above the horizon', math.floor(elev + 0.5)) or 'Night, moon and street lights') or '',
      vec2(p.x, p2.y + 6), 12, T.hex('#8A8D94'))
    lockLine(lock, vec2(p.x, p2.y + 22), w)
  end,
}

-- ---------------------------------------------------------------------------------------------- performance curve
W.perf = {
  height = function () return 172 end,
  draw = function (row, p, w, ctx)
    local def = row.def
    local cur = def.get()
    local fpsOf = ctx.tierFps
    local sel = cur and fpsOf(cur)
    T.text("Pick a point on your GPU's curve", p, 14, C.text2)
    T.monoRight(cur and (cur .. (sel and string.format(', %d fps', math.floor(sel + 0.5)) or ', not measured')) or 'custom', vec2(p.x + w, p.y + 1), 13, C.text)
    local p1, p2 = vec2(p.x, p.y + 26), vec2(p.x + w, p.y + 166)
    local gh = p2.y - p1.y
    ui.drawRectFilled(p1, p2, rgbm(1, 1, 1, 0.04), 14)
    ui.drawRect(p1, p2, rgbm(1, 1, 1, 0.08), 14, nil, 1)
    for i = 1, 3 do ui.drawLine(vec2(p1.x, p1.y + gh * i / 4), vec2(p2.x, p1.y + gh * i / 4), rgbm(1, 1, 1, 0.06), 1) end
    local function Y(f) return p1.y + gh - (clamp(f, 30, 260) - 30) / 230 * (gh - 16) - 8 end
    local refresh = ctx.refresh()
    ui.drawLine(vec2(p1.x, Y(refresh)), vec2(p2.x, Y(refresh)), rgbm(245 / 255, 197 / 255, 24 / 255, 0.6), 1)
    T.textRight('Your refresh rate', vec2(p2.x - 8, Y(refresh) - 16), 11, T.hex('#FFE27A'))
    local pts = {}
    for i, o in ipairs(def.options) do
      local f = fpsOf(o.value)
      pts[i] = { x = p1.x + w * (0.12 + 0.27 * (i - 1)), f = f, o = o }
    end
    ui.pathClear()
    local any = false
    for _, pt in ipairs(pts) do if pt.f then ui.pathLineTo(vec2(pt.x, Y(pt.f))); any = true end end
    if any then ui.pathStroke(T.hex('#7CB6FF'), false, 2) end
    for _, pt in ipairs(pts) do
      local on = pt.o.value == cur
      local y = pt.f and Y(pt.f) or p1.y + gh - 24
      local d = on and 10 or 7
      local clicked, hovered = hit(def.id .. '_' .. pt.o.value, vec2(pt.x - 14, y - 14), vec2(28, 28))
      tooltip(def, ctx)
      ui.drawCircleFilled(vec2(pt.x, y), d, on and C.blue or T.hex('#15161A'), 24)
      ui.drawCircle(vec2(pt.x, y), d, on and C.white or rgbm(1, 1, 1, hovered and 0.9 or 0.6), 24, 2)
      T.textCentered(pt.o.label .. (pt.f and (' ' .. math.floor(pt.f + 0.5)) or ''), vec2(pt.x, y + 22), 11, on and C.white or C.muted)
      if clicked and not on then commit(def, pt.o.value) end
    end
  end,
}

-- ---------------------------------------------------------------------------------------------- chase camera placer
W.cam = {
  height = function () return 172 end,
  draw = function (row, p, w, ctx)
    local dd, dh, dp = row.defs[1], row.defs[2], row.defs[3]   -- distance, height, pitch
    local d, hgt, pitch = dd.get(), dh.get(), dp.get()
    T.text('Click to place the camera', p, 14, C.text2)
    T.monoRight(string.format('%.1f m back, %.2f m up', d, hgt), vec2(p.x + w, p.y + 1), 13, C.text)
    local p1, p2 = vec2(p.x, p.y + 26), vec2(p.x + w, p.y + 166)
    local bw, bh = w, p2.y - p1.y
    ui.drawRectFilled(p1, p2, rgbm(1, 1, 1, 0.04), 14)
    ui.drawRect(p1, p2, rgbm(1, 1, 1, 0.12), 14, nil, 1)
    ui.drawLine(vec2(p1.x, p1.y + bh * 0.74), vec2(p2.x, p1.y + bh * 0.74), rgbm(1, 1, 1, 0.25), 1)
    local function V(x, y) return vec2(p1.x + bw * x / 240, p1.y + bh * y / 140) end
    -- car silhouette (design path, simplified to a polygon)
    ui.pathClear()
    for _, q in ipairs({ { 187, 104 }, { 187, 92 }, { 196, 82 }, { 206, 79 }, { 214, 70 }, { 224, 65 }, { 232, 66 }, { 240, 67 }, { 240, 104 } }) do ui.pathLineTo(V(q[1], q[2])) end
    ui.pathFillConvex(C.text2)
    ui.drawCircleFilled(V(196, 104), 7, T.hex('#15161A'), 16); ui.drawCircle(V(196, 104), 7, C.text2, 16, 2)
    local _, hovered, active = hit(dd.id .. '_cam', p1, p2 - p1)
    if active then
      local m = mouse()
      local px, py = (m.x - p1.x) / bw * 100, (m.y - p1.y) / bh * 100
      commit(dd, clamp((78 - px) / 70 * 9, dd.min, dd.max))
      commit(dh, clamp((70 - py) / 55 * 2 - 0.5, dh.min, dh.max))
    end
    local xp = 78 - (d / 9) * 70
    local yp = 70 - (hgt + 0.5) / 2 * 55
    local cpos = vec2(p1.x + bw * T.ease(dd.id .. '_cx', xp, ctx.dt, 350) / 100, p1.y + bh * T.ease(dh.id .. '_cy', yp, ctx.dt, 350) / 100)
    ui.drawLine(cpos, V(206, 84), C.yellow, 1.4)
    ui.drawRectFilled(cpos - vec2(15, 11), cpos + vec2(15, 11), C.yellow, 6)
    ui.drawRectFilled(cpos - vec2(10, 6), cpos + vec2(3, 6), T.hex('#15161A'), 2)
    ui.drawTriangleFilled(cpos + vec2(3, -2), cpos + vec2(10, -6), cpos + vec2(10, 6), T.hex('#15161A'))
  end,
}

-- ---------------------------------------------------------------------------------------------- HUD preview
W.preview = {
  height = function (row, w) return math.floor(w * 720 / 1400 + 0.5) end,
  draw = function (row, p, w, ctx)
    local h = W.preview.height(row, w)
    ui.drawRectFilled(p, p + vec2(w, h), T.hex('#0A0B0E'), 14)
    if ctx.drawCluster then ctx.drawCluster(p, w / 1400) end
    if not ctx.store.hudOn then
      ui.drawRectFilled(p, p + vec2(w, h), rgbm(0, 0, 0, 0.7), 14)
      T.textCentered('HUD is off', p + vec2(w / 2, h / 2), 14, C.text2)
    end
  end,
}

-- ---------------------------------------------------------------------------------------------- 3x3 position grid
local POS_IDS = { 'tl', 'tc', 'tr', 'ml', 'mc', 'mr', 'bl', 'bc', 'br' }
W.pos = {
  height = function (row, w) return math.floor(w * 9 / 16 + 0.5) end,
  draw = function (row, p, w, ctx)
    local def = row.def
    local h = W.pos.height(row, w)
    ui.drawRectFilledMultiColor(p, p + vec2(w, h), rgbm(126 / 255, 157 / 255, 194 / 255, 0.25), rgbm(126 / 255, 157 / 255, 194 / 255, 0.25), rgbm(44 / 255, 47 / 255, 52 / 255, 0.4), rgbm(44 / 255, 47 / 255, 52 / 255, 0.4))
    ui.drawRect(p, p + vec2(w, h), rgbm(1, 1, 1, 0.14), 12, nil, 1)
    local cw, ch = (w - 12 - 10) / 3, (h - 12 - 10) / 3
    local cur = def.get()
    for i, id in ipairs(POS_IDS) do
      local cx, cy = (i - 1) % 3, math.floor((i - 1) / 3)
      local cp = p + vec2(6 + cx * (cw + 5), 6 + cy * (ch + 5))
      local clicked, hovered = hit(def.id .. '_' .. id, cp, vec2(cw, ch))
      tooltip(def, ctx)
      local on = id == cur
      ui.drawRectFilled(cp, cp + vec2(cw, ch), on and rgbm(1, 1, 1, 0.22) or rgbm(1, 1, 1, hovered and 0.08 or 0.03), 7)
      ui.drawRect(cp, cp + vec2(cw, ch), on and rgbm(1, 1, 1, 0.7) or rgbm(1, 1, 1, 0.08), 7, nil, 1)
      if on then
        local c = cp + vec2(cw / 2, ch / 2)
        ui.drawCircle(c - vec2(8, 0), 6, C.white, 16, 2); ui.drawCircle(c + vec2(8, 0), 6, C.white, 16, 2)
      end
      if clicked and not on then commit(def, id) end
    end
  end,
}

-- ---------------------------------------------------------------------------------------------- lamp chips
local LAMP_CHIPS = { { 'indicators', 'Indicators', '#2CDB5C' }, { 'high', 'High beam', '#2F7BFF' }, { 'engine', 'Check engine', '#FFA81A' },
  { 'belt', 'Seat belt', '#FF2A1F' }, { 'abs', 'ABS', '#FFA81A' }, { 'brake', 'Brake', '#FF2A1F' }, { 'tpms', 'Tyre pressure', '#FFA81A' },
  { 'battery', 'Battery', '#FF2A1F' } }
W.lamps = {
  height = function () return 4 * 38 + 3 * 8 end,
  draw = function (row, p, w, ctx)
    local def = row.def
    local set = {}
    for k in tostring(def.get() or ''):gmatch('[^,]+') do set[k] = true end
    local cw = (w - 8) / 2
    for i, c in ipairs(LAMP_CHIPS) do
      local cx, cy = (i - 1) % 2, math.floor((i - 1) / 2)
      local cp = p + vec2(cx * (cw + 8), cy * 46)
      local clicked, hovered = hit(def.id .. '_' .. c[1], cp, vec2(cw, 38))
      tooltip(def, ctx)
      local on = set[c[1]] == true
      ui.drawRectFilled(cp, cp + vec2(cw, 38), on and rgbm(1, 1, 1, 0.10) or rgbm(0, 0, 0, 0), 11)
      ui.drawRect(cp, cp + vec2(cw, 38), on and rgbm(1, 1, 1, 0.22) or rgbm(1, 1, 1, hovered and 0.18 or 0.08), 11, nil, 1)
      ui.drawCircleFilled(cp + vec2(18, 19), 6, on and T.hex(c[3]) or T.hex('#5E6168'), 16)
      T.text(c[2], cp + vec2(32, 11), 13, C.text)
      if clicked then
        set[c[1]] = not on or nil
        local out = {}
        for _, x in ipairs(LAMP_CHIPS) do if set[x[1]] then out[#out + 1] = x[1] end end
        commit(def, table.concat(out, ','))
      end
    end
  end,
}

-- ---------------------------------------------------------------------------------------------- button, info, note
W.button = {
  height = function () return 38 end,
  draw = function (row, p, w, ctx)
    local def = row.def
    local lock = lockedOf(def)
    local clicked, hovered, active = hit(def.id, p, vec2(w, 38))
    tooltip(def, ctx)
    ui.drawRectFilled(p, p + vec2(w, 38), rgbm(1, 1, 1, active and 0.14 or hovered and 0.11 or 0.08), 11)
    ui.drawRect(p, p + vec2(w, 38), rgbm(1, 1, 1, 0.14), 11, nil, 1)
    T.textCentered(def.label, p + vec2(w / 2, 19), 14, lock and C.faint or C.text, 'medium')
    if clicked and not lock and def.run then def.run() end
  end,
}

W.info = {
  height = function () return 22 end,
  draw = function (row, p, w)
    T.text(row.label, p, 13, C.muted)
    local v, col = row.value()
    T.textRight(tostring(v), vec2(p.x + w, p.y), 13, col or C.text)
  end,
}

W.note = {
  height = function (row, w) return math.ceil(T.measure(row.text(), 12).x / math.max(w, 1) + 0.15) * 17 + 2 end,
  draw = function (row, p, w)
    local h = W.note.height(row, w)
    T.wrapped(row.text(), p, p + vec2(w, h), 12, row.color or C.hint)
  end,
}

-- ---------------------------------------------------------------------------------------------- scenes (preset buttons)
local SCENE_COLOURS = { Photoreal = '#FFE27A', ['Night run'] = '#9CC9FF', ['Golden hour'] = '#FFB547', ['Rain run'] = '#7CB6FF', Broadcast = '#FF8A8C' }
function W.scenes(def, p, w, ctx, costOf)
  local x = p.x
  local cur = def.get()
  for i, o in ipairs(def.options) do
    local cost = costOf and costOf(o.value)
    local label = o.label
    local bw = 8 + 36 + 10 + T.measure(label, 14, 'medium').x + (cost and (8 + T.measure(cost, 11, 'mono').x) or 0) + 16
    local cp = vec2(x, p.y)
    local clicked, hovered = hit('scene_' .. i, cp, vec2(bw, 52))
    local on = o.value == cur
    ui.drawRectFilled(cp, cp + vec2(bw, 52), on and rgbm(1, 1, 1, 0.16) or rgbm(0, 0, 0, 0.28), 16)
    ui.drawRect(cp, cp + vec2(bw, 52), on and rgbm(1, 1, 1, 0.7) or rgbm(1, 1, 1, hovered and 0.4 or 0.10), 16, nil, 1)
    ui.drawRectFilled(cp + vec2(8, 8), cp + vec2(44, 44), rgbm(1, 1, 1, 0.10), 11)
    ui.drawCircleFilled(cp + vec2(26, 26), 8, T.hex(SCENE_COLOURS[o.value] or '#FFFFFF'), 20)
    T.text(label, cp + vec2(54, 16), 14, C.text, 'medium')
    if cost then T.mono(cost, cp + vec2(54 + T.measure(label, 14, 'medium').x + 8, 19), 11, C.muted) end
    if clicked then def.set(o.value) end
    x = x + bw + 10
  end
  return 52
end

return W
