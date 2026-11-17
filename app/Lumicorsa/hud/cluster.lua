--[[
  Lumicorsa analog cluster (design: analog-cluster.dc.html, 1400 x 720 design units, drawn scaled).

  Static layers are PNGs pre-rendered at 2x from the design (tools/render_cluster.py): hood, dial faces (km/h or mph,
  oil in °C or °F), needles, caps and glass glare, lamp sprites, LCD overlay. Live parts are drawn every frame from
  cached state: needles (rotated quads), warm-up bands, shift LEDs, lamps, turn arrows and the LCD text.

  Data comes from ac.getCar(0): speedKmh, rpm, rpmLimiter, gear, fuel/maxFuel, oilTemperature (waterTemperature as a
  fallback), turningLeftLights/turningRightLights + turningLightsActivePhase (the car's own blinker), headlightsActive,
  highBeams, absInAction, tractionControlInAction, handbrake, engineLifeLeft, gearboxDamage, batteryVoltage,
  distanceDrivenTotalKm/SessionKm; the clock and outside temperature from ac.getSim().
  Lamps with no data source (fog lights, oil pressure, tyre pressure) only light during the bulb check.
]]

local M = {}

local ASSETS = 'hud/cluster_assets/'
local DESIGN = vec2(1400, 720)
local DIALS = { speedo = vec2(86, 136), tach = vec2(814, 136) }
local FACE_OFF, FACE = 19, 458 / 500                     -- face svg (viewBox 500) inside a dial
local LAMP_ORDER = { 'high', 'low', 'fog', 'engine', 'belt', 'airbag', 'battery', 'oil', 'brake', 'abs', 'esc', 'tpms' }
local CHIP_OF = { high = 'high', low = 'high', engine = 'engine', belt = 'belt', airbag = 'belt', battery = 'battery',
  brake = 'brake', abs = 'abs', esc = 'abs', tpms = 'tpms', oil = 'engine', fog = 'high' }
local LEDS = { { 278.5, 137.6, 14.2 }, { 300.1, 145.4, 25.6 }, { 319.8, 157.3, 37.0 }, { 336.7, 172.9, 48.4 },
  { 350.2, 191.5, 59.7 }, { 359.8, 212.4, 71.1 }, { 365.0, 234.8, 82.5 } }
local LCD_COLOURS = { Orange = { rgbm(0.898, 0.275, 0.11, 1), rgbm(0.725, 0.173, 0.051, 1), rgbm(1, 0.753, 0.216, 1) },
  White = { rgbm(0.85, 0.863, 0.878, 1), rgbm(0.62, 0.635, 0.66, 1), rgbm(0.1, 0.105, 0.12, 1) },
  Red = { rgbm(0.72, 0.118, 0.118, 1), rgbm(0.48, 0.06, 0.06, 1), rgbm(1, 0.82, 0.6, 1) } }
local NEEDLES = { Red = 'needle.png', Orange = 'needle_orange.png', White = 'needle_white.png' }

M.last = {}            -- what the last frame drew with (self-test readback)
local startTime = nil  -- session start (bulb check)

local function kmhFraction(v) return v <= 120 and v / 120 * 0.44 or 0.44 + (v - 120) / 210 * 0.56 end

-- Rotated square image around a pivot (design units, deg clockwise from straight up).
local function drawRotated(img, o, k, pivot, size, deg, col)
  local a = math.rad(deg)
  local ca, sa = math.cos(a), math.sin(a)
  local h = size / 2
  local function pt(x, y) return o + vec2(pivot.x + x * ca - y * sa, pivot.y + x * sa + y * ca) * k end
  ui.drawImageQuad(img, pt(-h, -h), pt(h, -h), pt(h, h), pt(-h, h), col)
end

local function faceToDesign(dial, x, y) return vec2(dial.x + FACE_OFF + x * FACE, dial.y + FACE_OFF + y * FACE) end

-- ---------------------------------------------------------------------------------------------- state from the car
local function carState(St, t)
  local car, sim = ac.getCar(0), ac.getSim()
  local s = {}
  if not car then return nil end
  local run = t - (startTime or t)
  local sweep = 0
  if St.sweep and run < 2.4 then sweep = run < 1.2 and run / 1.2 or (2.4 - run) / 1.2 end
  s.bulb = St.sweep and run < 2.4
  s.run = run
  s.mph = St.units == 'mph'
  local spd = math.max(car.speedKmh or 0, 0)
  s.speedFrac = sweep > 0 and sweep or (s.mph and math.min(spd * 0.6214, 200) / 200 or kmhFraction(math.min(spd, 330)))
  local rpm = sweep > 0 and sweep * 9000 or math.max(car.rpm or 0, 0)
  s.rpm = rpm
  s.rpmDeg = -128 + 256 * math.min(rpm, 9000) / 9000
  s.speedDeg = -128 + 256 * s.speedFrac
  s.fuel = (car.maxFuel or 0) > 0 and car.fuel / car.maxFuel or 0
  local oil = (car.oilTemperature or 0) > 1 and car.oilTemperature or car.waterTemperature or 90
  s.oil = oil
  s.warm = math.max(0, math.min(1, (oil - 55) / 45))
  local limiter = (car.rpmLimiter or 0) > 1000 and car.rpmLimiter or 9000
  local first = limiter * St.shiftAt / 100
  if sweep > 0 then s.leds = 7
  elseif rpm < first then s.leds = 0
  else s.leds = math.min(7, math.floor((rpm - first) / math.max((limiter - first) / 7, 1)) + 1) end
  s.gear = (car.gear or 0) == 0 and 'N' or car.gear < 0 and 'R' or tostring(car.gear)
  local blink = car.turningLightsActivePhase
  s.left = car.turningLeftLights and blink
  s.right = car.turningRightLights and blink
  local fault = (car.engineLifeLeft or 1000) < 300 or (car.gearboxDamage or 0) > 0.5
  s.lamps = {
    high = car.headlightsActive and car.highBeams, low = car.headlightsActive and not car.highBeams, fog = false,
    engine = fault, belt = run < 6 and math.floor(t * 2.6) % 2 == 0, airbag = run < 3,
    battery = (car.batteryVoltage or 12.5) > 0 and car.batteryVoltage < 11.5, oil = false,
    brake = (car.handbrake or 0) > 0.05 or spd < 0.5, abs = car.absInAction, esc = car.tractionControlInAction, tpms = false,
  }
  s.msg = fault and 'CHECK ENGINE' or (run < 6 and not s.bulb) and 'FASTEN BELT' or car.absInAction and 'ABS ACTIVE' or oil < 75 and 'ENGINE WARMING' or ''
  local km = car.distanceDrivenTotalKm or 0
  local trip = car.distanceDrivenSessionKm or 0
  s.odo = s.mph and string.format('%06d mls', math.floor(km * 0.6214)) or string.format('%06d km', math.floor(km))
  s.trip = string.format('%.1f', s.mph and trip * 0.6214 or trip)
  s.clock = string.format('%02d:%02d', sim.timeHours or 0, sim.timeMinutes or 0)
  local temp = sim.ambientTemperature or 0
  s.outside = s.mph and string.format('%+d °F', math.floor(temp * 1.8 + 32 + 0.5)) or string.format('%+d °C', math.floor(temp + 0.5))
  s.limiter = car.isEngineLimiterOn
  return s
end

-- ---------------------------------------------------------------------------------------------- drawing
local enabledLamps = {}
local function parseLamps(str) for k in pairs(enabledLamps) do enabledLamps[k] = nil end; for k in str:gmatch('[^,]+') do enabledLamps[k] = true end end

-- Draws the cluster with its top-left at `o` (window px), `k` px per design unit. `T` = theme (fonts).
function M.draw(St, T, o, k, now)
  local s = carState(St, now)
  if not s then return end
  parseLamps(St.lamps)
  local op = St.hudOpacity / 100
  local white = rgbm(1, 1, 1, op)
  ui.drawImage(ASSETS .. 'hood.png', o, o + DESIGN * k, white)

  -- dial faces
  local sp, ta = DIALS.speedo, DIALS.tach
  ui.drawImage(ASSETS .. (s.mph and 'speedo_mph.png' or 'speedo_kmh.png'), o + sp * k, o + (sp + vec2(500, 500)) * k, white)
  ui.drawImage(ASSETS .. (s.mph and 'tach_f.png' or 'tach_c.png'), o + ta * k, o + (ta + vec2(500, 500)) * k, white)

  -- backlight glow around the white rings
  if St.glow > 0 then
    local g = St.glow / 100 * op
    for _, d in ipairs({ sp, ta }) do
      local c = o + (d + vec2(250, 250)) * k
      for i = 1, 3 do ui.drawCircle(c, (231 + i * 2) * k, rgbm(1, 1, 1, g * 0.22 / i), 72, (3 + i * 2) * k) end
    end
  end

  -- warm-up bands on the rev counter (shrink as the oil warms), angles from straight up, clockwise
  if St.warm then
    local function band(fromRpm, toRpm, col)
      if fromRpm >= toRpm then return end
      local a0 = math.rad(-128 + 256 * fromRpm / 9000 - 90)
      local a1 = math.rad(-128 + 256 * toRpm / 9000 - 90)
      ui.pathClear()
      ui.pathArcTo(o + faceToDesign(ta, 250, 250) * k, 226 * FACE * k, a0, a1, 24)
      ui.pathStroke(col, false, 14 * FACE * k)
    end
    local yS, oS = 6000 + s.warm * 2250, 7000 + s.warm * 1250
    band(yS, math.min(oS, 8250), rgbm(0.965, 0.76, 0.1, op))
    band(oS, 8250, rgbm(1, 0.54, 0.1, op))
  end

  -- shift LEDs (inside the rev counter)
  for i, L in ipairs(LEDS) do
    local on = i <= s.leds
    local col = on and (i <= 3 and rgbm(0.965, 0.76, 0.1, op) or i <= 5 and rgbm(1, 0.54, 0.1, op) or rgbm(1, 0.165, 0.12, op)) or rgbm(0.1, 0.1, 0.114, op)
    local a = math.rad(L[3])
    local ca, sa = math.cos(a), math.sin(a)
    local function pt(x, y) return o + faceToDesign(ta, L[1] + x * ca - y * sa, L[2] + x * sa + y * ca) * k end
    ui.drawQuadFilled(pt(-7, -4), pt(7, -4), pt(7, 4), pt(-7, 4), col)
  end

  -- sub-needles (fuel on the speedometer, oil on the rev counter), then main needles, then caps and glare
  local subSize = 120 * FACE
  drawRotated(ASSETS .. 'subneedle.png', o, k, faceToDesign(sp, 250, 404), subSize, 125 + 110 * s.fuel, white)
  drawRotated(ASSETS .. 'subneedle.png', o, k, faceToDesign(ta, 250, 404), subSize, 125 + 110 * math.min(1, math.max(0, (s.oil - 40) / 110)), white)
  local needle = ASSETS .. (NEEDLES[St.needle] or 'needle.png')
  drawRotated(needle, o, k, faceToDesign(sp, 250, 250), 500 * FACE, s.speedDeg, white)
  drawRotated(needle, o, k, faceToDesign(ta, 250, 250), 500 * FACE, s.rpmDeg, white)
  for _, d in ipairs({ sp, ta }) do
    ui.drawImage(ASSETS .. 'overlay.png', o + (d + vec2(FACE_OFF, FACE_OFF)) * k, o + (d + vec2(FACE_OFF + 458, FACE_OFF + 458)) * k, white)
  end

  -- centre column: turn arrows, lamp grid, LCD
  local cx = 606
  local arrowY = 160
  local function sprite(file, idx, count, p, size, lit)
    ui.drawImage(ASSETS .. file, o + p * k, o + (p + size) * k, white, vec2((idx - 1) / count, 0), vec2(idx / count, 1))
  end
  local lft, rgt = s.bulb or s.left, s.bulb or s.right
  if not enabledLamps.indicators then lft, rgt = s.bulb, s.bulb end
  sprite(lft and 'turn_on.png' or 'turn_off.png', 1, 2, vec2(cx + 19 - 7, arrowY - 11), vec2(48, 48))
  sprite(rgt and 'turn_on.png' or 'turn_off.png', 2, 2, vec2(cx + 188 - 19 - 41, arrowY - 11), vec2(48, 48))
  local gridX, gridY = cx + 22, arrowY + 42
  for i, id in ipairs(LAMP_ORDER) do
    local col, row = (i - 1) % 3, math.floor((i - 1) / 3)
    local lit = s.bulb or (s.lamps[id] and enabledLamps[CHIP_OF[id]] and true or false)
    if id == 'belt' or id == 'airbag' then lit = s.bulb or (s.lamps[id] and enabledLamps.belt) end
    sprite(lit and 'lamps_on.png' or 'lamps_off.png', i, 12, vec2(gridX + col * 54 - 7, gridY + row * 42 - 9), vec2(48, 48))
    M.last['lamp_' .. id] = lit
  end
  local lcd = vec2(cx + 11, gridY + 4 * 42 + 6)
  local lc = LCD_COLOURS[St.lcd] or LCD_COLOURS.Orange
  local lp1, lp2 = o + lcd * k, o + (lcd + vec2(166, 128)) * k
  local top, bot = rgbm(lc[1].r, lc[1].g, lc[1].b, op), rgbm(lc[2].r, lc[2].g, lc[2].b, op)
  ui.drawRectFilledMultiColor(lp1, lp2, top, top, bot, bot)
  local tc = rgbm(lc[3].r, lc[3].g, lc[3].b, op)
  T.text(s.gear, lp1 + vec2(10, 4) * k, 64 * k, tc, 'bold')
  if s.limiter then T.mono('LIM', lp1 + vec2(118, 10) * k, 12 * k, tc) end
  for i = 1, 5 do                                              -- fuel bars
    local x = lcd.x + 118 + (i - 1) * 8
    local filled = s.fuel >= i / 5 - 0.1
    ui.drawRect(o + vec2(x, lcd.y + 32) * k, o + vec2(x + 6, lcd.y + 45) * k, tc, 0, nil, 1.5 * k)
    if filled then ui.drawRectFilled(o + vec2(x, lcd.y + 32) * k, o + vec2(x + 6, lcd.y + 45) * k, tc) end
  end
  ui.drawLine(o + vec2(lcd.x + 10, lcd.y + 66) * k, o + vec2(lcd.x + 156, lcd.y + 66) * k, rgbm(tc.r, tc.g, tc.b, 0.5 * op), 1)
  T.mono(s.bulb and '' or s.msg, o + vec2(lcd.x + 10, lcd.y + 70) * k, 12 * k, tc)
  T.mono(s.odo, o + vec2(lcd.x + 10, lcd.y + 88) * k, 13 * k, tc)
  T.monoRight(s.trip, o + vec2(lcd.x + 156, lcd.y + 88) * k, 13 * k, tc)
  T.mono(s.clock, o + vec2(lcd.x + 10, lcd.y + 106) * k, 11.5 * k, tc)
  T.monoRight(s.outside, o + vec2(lcd.x + 156, lcd.y + 106) * k, 11.5 * k, tc)
  ui.drawImage(ASSETS .. 'lcd_overlay.png', lp1, lp2, white)

  local L = M.last
  L.units, L.needle, L.lcd, L.opacity, L.sweep, L.speedDeg, L.leds, L.warm = St.units, St.needle, St.lcd, St.hudOpacity, St.sweep, s.speedDeg, s.leds, St.warm
  L.glow, L.shiftAt = St.glow, St.shiftAt
end

function M.sessionStart(now) startTime = now end

-- ---------------------------------------------------------------------------------------------- placement
M.SIZE = DESIGN
local POS = { tl = vec2(0, 0), tc = vec2(0.5, 0), tr = vec2(1, 0), ml = vec2(0, 0.5), mc = vec2(0.5, 0.5), mr = vec2(1, 0.5),
  bl = vec2(0, 1), bc = vec2(0.5, 1), br = vec2(1, 1) }
function M.scale(St) return 0.42 * St.hudScale / 100 end   -- 100% = 588 x 302 px
function M.place(St)
  local w = ac.accessAppWindow('IMGUI_LUA_Lumicorsa_hud')
  if not w then return end
  local screen = ac.getUI().windowSize
  local size = DESIGN * M.scale(St)
  local a = POS[St.hudPos] or POS.bc
  local margin = 24
  w:resize(size)
  w:move(vec2(margin + (screen.x - size.x - margin * 2) * a.x, margin + (screen.y - size.y - margin * 2) * a.y))
  M.last.pos = St.hudPos
  M.last.scale = St.hudScale
end

function M.visibleInView(St)
  if not St.hudOn then return false end
  local mode = ac.getSim().cameraMode
  if St.hudViews == 'Chase' then return mode == ac.CameraMode.Drivable end
  if St.hudViews == 'Cockpit' then return mode == ac.CameraMode.Cockpit end
  return true
end

-- ---------------------------------------------------------------------------------------------- registry: HUD tab
function M.register(R, St, actions)
  local fmt = R.fmt
  local function st(id, label, key, o)
    o.get = o.get or function () return St[key] end
    o.set = o.set or function (v) St[key] = v; if o.after then o.after() end end
    o.readback = o.readback or function () return M.last[o.lastKey or key] end
    o.frames = 2
    return R.state(id, label, o)
  end
  st('hudOn', 'Show HUD', 'hudOn', { kind = 'toggle', hint = 'Alt+H toggles it while you drive',
    readback = function () return actions.hudDrawn() end })
  st('hudShow', 'Show in', 'hudViews', { kind = 'seg', options = { { label = 'All views', value = 'All views' },
    { label = 'Chase', value = 'Chase' }, { label = 'Cockpit', value = 'Cockpit' } }, readback = function () return St.hudViews end })
  st('units', 'Speed', 'units', { kind = 'seg', options = { { label = 'km/h', value = 'km/h' }, { label = 'mph', value = 'mph' } } })
  st('hudPos', 'Position', 'hudPos', { kind = 'pos', after = function () M.place(St) end, lastKey = 'pos' })
  st('hudsc', 'Scale', 'hudScale', { kind = 'slider', min = 60, max = 160, step = 1, default = 100, fmt = fmt.pct,
    after = function () M.place(St) end, lastKey = 'scale' })
  st('hudop', 'Opacity', 'hudOpacity', { kind = 'slider', min = 20, max = 100, step = 1, default = 92, fmt = fmt.pct, lastKey = 'opacity' })
  st('lamps', 'Warning lamps', 'lamps', { kind = 'lamps', readback = function () return St.lamps end })
  st('sweep', 'Needle sweep and bulb check on start', 'sweep', { kind = 'toggle', hint = 'Like turning the key' })
  st('needle', 'Needle', 'needle', { kind = 'seg', options = { { label = 'Red', value = 'Red' }, { label = 'Orange', value = 'Orange' }, { label = 'White', value = 'White' } } })
  st('lcd', 'Display', 'lcd', { kind = 'seg', options = { { label = 'Orange', value = 'Orange' }, { label = 'White', value = 'White' }, { label = 'Red', value = 'Red' } } })
  st('shiftat', 'First light at', 'shiftAt', { kind = 'slider', min = 60, max = 95, step = 1, default = 80, fmt = fmt.pct })
  st('warm', 'Variable redline while warming up', 'warm', { kind = 'toggle', hint = 'Yellow band shrinks as the oil heats' })
  st('glow', 'Backlight glow', 'glow', { kind = 'slider', min = 0, max = 100, step = 1, default = 45, fmt = fmt.pct })
end

return M
