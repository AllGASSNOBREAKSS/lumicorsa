--[[
  Lumicorsa state: what the app owns (look values, effect switches, HUD options, UI mode) and its persistence.
  ac.storage keeps the switches; look values live in one JSON blob written 250 ms after the last change, so slider
  drags never write per frame.
]]

local C = require('backend/config')
local look = require('backend/look')

local M = {}

M.store = ac.storage({
  master = true, mode = 'Basic', tab = 'look', preset = 'Photoreal',
  neural = true, nr = 0.6, light = true, atmos = true, detail = true, lens = true,
  shafts = true, flare = true, ao = true, adapt = 40, mist = true, autoLook = false, blendWith = 'Night run', blend = 0,
  cockpitDof = false, replayDof = 0.6, photoDof = false, focus = 12, aperture = 2.8, bokeh = 40,
  hudOn = true, hudViews = 'All views', units = 'km/h', hudPos = 'bc', hudScale = 100, hudOpacity = 92,
  sweep = true, needle = 'Red', lcd = 'Orange', shiftAt = 80, warm = true, glow = 45,
  lamps = 'indicators,high,engine,belt,abs,brake,tpms,battery',
  autoWipers = false, overlay = false, budget = 3.0, budgetOn = false, timeSpeed = 1,
  measured = '', tierFps = '', mix = 'Onboard', ver = 200,
})
local S = M.store

-- 2.0.1: "Show in" was easy to leave on Chase, which hides the HUD in every other view. Reset it once.
if S.ver < 201 then S.hudViews = 'All views'; S.ver = 201 end

-- ---------------------------------------------------------------------------------------------- look values
M.values = {}
for k, v in pairs(look.DEFAULTS) do M.values[k] = v end

local blob = ac.storage({ json = '' }, 'look_')
do
  local ok, t = pcall(JSON.parse, blob.json or '')
  if ok and type(t) == 'table' then for k, v in pairs(t) do if type(v) == 'number' and M.values[k] ~= nil then M.values[k] = v end end end
end

local function saveLook()
  local out = {}
  for k, v in pairs(M.values) do if type(v) == 'number' then out[k] = v end end
  C.later('state/look', out, function (t) blob.json = JSON.stringify(t) end)
end

local fade = nil   -- preset crossfade in progress (see M.applyPreset)
-- A value set directly (slider, profile import) takes effect at once, even during a crossfade.
function M.setValue(k, v) M.values[k] = v; if fade then fade.from[k] = v end; saveLook() end

-- ---------------------------------------------------------------------------------------------- presets
-- The five looks from the design. Each sets every look value (blending needs complete sets).
local base = {
  PL_Exposure = 0.0, PL_HighlightRecover = 0.55, PL_BloomIntensity = 0.18, PL_Halation = 0.15, PL_FilmicStrength = 0.75,
  PL_Contrast = 0.08, PL_Lift = 0.1, PL_Saturation = -0.04, PL_Vibrance = 0.12, PL_HazeDensity = 0.30, PL_Mist = 0.15,
  PL_Clarity = 0.22, PL_Sharpen = 0.35, PL_ChromaAb = 0.10, PL_Vignette = 0.25, PL_Grain = 0.08, PL_Temperature = 0.0,
  PL_Tint = 0.0, PL_Shafts = 0.4, PL_Flare = 0.25, PL_AO = 0.6,
}
local function preset(over) local p = {}; for k, v in pairs(base) do p[k] = v end; for k, v in pairs(over) do p[k] = v end; return p end
M.PRESETS = {
  { name = 'Photoreal', values = preset({}), nr = 0.6 },
  { name = 'Night run', values = preset({ PL_Exposure = 0.25, PL_HighlightRecover = 0.8, PL_BloomIntensity = 0.38, PL_Halation = 0.55,
      PL_FilmicStrength = 0.9, PL_Contrast = 0.12, PL_Lift = 0.05, PL_Vibrance = 0.18, PL_HazeDensity = 0.18, PL_Temperature = -0.15,
      PL_Tint = 0.05, PL_ChromaAb = 0.18, PL_Vignette = 0.4, PL_Grain = 0.14, PL_Flare = 0.45, PL_Shafts = 0.0 }), nr = 0.7 },
  { name = 'Golden hour', values = preset({ PL_Exposure = 0.1, PL_HighlightRecover = 0.65, PL_BloomIntensity = 0.3, PL_Halation = 0.35,
      PL_FilmicStrength = 0.85, PL_Contrast = 0.06, PL_Saturation = 0.04, PL_Vibrance = 0.2, PL_HazeDensity = 0.45, PL_Temperature = 0.35,
      PL_Tint = 0.04, PL_Vignette = 0.35, PL_Shafts = 0.7 }), nr = 0.55 },
  { name = 'Rain run', values = preset({ PL_Exposure = 0.05, PL_HighlightRecover = 0.6, PL_BloomIntensity = 0.28, PL_Halation = 0.3,
      PL_Contrast = 0.1, PL_Saturation = -0.12, PL_Vibrance = 0.05, PL_HazeDensity = 0.55, PL_Mist = 0.45, PL_Temperature = -0.2,
      PL_Clarity = 0.15, PL_Shafts = 0.0, PL_Flare = 0.35 }), nr = 0.6 },
  { name = 'Broadcast', values = preset({ PL_HighlightRecover = 0.45, PL_BloomIntensity = 0.1, PL_Halation = 0.0, PL_FilmicStrength = 0.6,
      PL_Contrast = 0.14, PL_Saturation = 0.08, PL_Vibrance = 0.1, PL_HazeDensity = 0.2, PL_Clarity = 0.3, PL_Sharpen = 0.45,
      PL_ChromaAb = 0.0, PL_Vignette = 0.1, PL_Grain = 0.0, PL_Flare = 0.1 }), nr = 0.45 },
}
function M.presetByName(n) for _, p in ipairs(M.PRESETS) do if p.name == n then return p end end return M.PRESETS[1] end

-- Preset changes crossfade over 1.5 s instead of snapping (no visible jump, no flicker when auto look switches).
local function startFade()
  local from = {}
  for k, v in pairs(M.values) do from[k] = v end
  fade = { from = from, t = 0, dur = 1.5 }
end

function M.applyPreset(name)
  local p = M.presetByName(name)
  startFade()
  for k, v in pairs(p.values) do M.values[k] = v end
  S.preset, S.nr, S.blend = p.name, p.nr, 0
  saveLook()
end

-- Look blender: Photoreal crossfaded with a second look (0..100).
function M.applyBlend(t, other)
  fade = nil                                                  -- the blender is a live slider
  S.blend, S.blendWith = t, other or S.blendWith
  local a, b = M.PRESETS[1], M.presetByName(S.blendWith)
  local k = t / 100
  for key, va in pairs(a.values) do M.values[key] = va + (b.values[key] - va) * k end
  S.nr = a.nr + (b.nr - a.nr) * k
  saveLook()
end

-- Auto look by time of day (and rain), with hysteresis so values near a boundary don't flip the look back and forth:
-- rain switches on above 15% and off below 5%, time boundaries move 15 minutes away from the current look, and a look
-- is held for at least 60 s.
local autoHeld, autoSince = nil, -1e9
function M.autoLookPick(now)
  local sim = ac.getSim()
  local rain = sim.rainIntensity or 0
  local h = (sim.timeTotalSeconds or 43200) / 3600
  local cur = autoHeld
  local m = 0.25
  local function night(x) return x < 6 or x >= 20.5 end
  local function golden(x) return (x >= 6 and x < 8) or (x >= 17.5 and x < 20.5) end
  local pick
  if rain > 0.15 or (cur == 'Rain run' and rain > 0.05) then pick = 'Rain run'
  elseif cur == 'Night run' and (night(h - m) or night(h + m)) then pick = 'Night run'
  elseif cur == 'Golden hour' and (golden(h - m) or golden(h + m)) and not night(h) then pick = 'Golden hour'
  elseif night(h) then pick = 'Night run'
  elseif golden(h) then pick = 'Golden hour'
  else pick = 'Photoreal' end
  if pick ~= cur and now - autoSince < 60 and cur ~= nil then return cur end
  if pick ~= cur then autoHeld, autoSince = pick, now end
  return pick
end

-- Frame state for look.render(), rebuilt from the store each frame without allocating.
local frame = { values = {}, off = {} }
function M.frameState(conflict, off, dt)
  local sim = ac.getSim()
  if fade then
    fade.t = fade.t + (dt or 0.016)
    local x = math.min(fade.t / fade.dur, 1)
    x = x * x * (3 - 2 * x)
    for k, v in pairs(M.values) do
      local a = fade.from[k]
      frame.values[k] = (type(v) == 'number' and type(a) == 'number') and a + (v - a) * x or v
    end
    if fade.t >= fade.dur then fade = nil end
  else
    for k, v in pairs(M.values) do frame.values[k] = v end
  end
  frame.light, frame.atmos, frame.detail, frame.lens = S.light, S.atmos, S.detail, S.lens
  frame.neural, frame.nrGain = S.neural, S.nr * 3.5
  frame.shafts, frame.flare, frame.ao, frame.mist = S.shafts, S.flare, S.ao, S.mist
  frame.adaptRate = S.adapt / 100
  local cam = sim.cameraMode
  local freeCam = cam == ac.CameraMode.Free
  if S.photoDof and freeCam then
    frame.dof, frame.focus = true, S.focus
    frame.values.PL_Dof = math.min(1, (16 - S.aperture) / 14.6 * 0.6 + S.bokeh / 100 * 0.4)
  elseif sim.isReplayActive and S.replayDof > 0 then
    frame.dof, frame.focus = true, 0
    frame.values.PL_Dof = S.replayDof
  elseif S.cockpitDof and cam == ac.CameraMode.Cockpit then
    frame.dof, frame.focus = true, 0.8                        -- gauges sharp, far road soft
    frame.values.PL_Dof = 0.45
  else
    frame.dof, frame.focus = false, 0
  end
  frame.split = false
  frame.conflict = conflict
  frame.off = off or frame.off
  return frame
end

-- ---------------------------------------------------------------------------------------------- registry: Look, Light, Visibility
-- Look values read back from look.sent: the values the final shader actually received on the last frame.
function M.register(R)
  local fmt = R.fmt
  local sent = look.sent
  local function lookValue(id, label, key, min, max, scale, f, o)
    o = o or {}
    return R.state(id, label, { kind = o.kind or 'slider', min = min, max = max, step = o.step, default = (look.DEFAULTS[key] or 0) * scale,
      fmt = f, key = 'shader value ' .. key, cost = o.cost,
      get = function () return M.values[key] * scale end,
      set = function (v) M.setValue(key, v / scale) end,
      readback = function () return (sent[key] or 0) * scale end, frames = 2 })
  end
  local signed = function (v) return string.format('%+d', math.floor(v + 0.5)) end

  -- Look tab
  R.state('preset', 'Look preset', { kind = 'scenes', options = {}, key = 'all shader values',
    get = function () return S.blend == 0 and S.preset or nil end,
    set = function (v) M.applyPreset(v) end, frames = 110,          -- waits out the 1.5 s crossfade
    readback = function ()
      for _, p in ipairs(M.PRESETS) do
        local ok = true
        for k, v in pairs(p.values) do if k ~= 'PL_HighlightRecover' and k ~= 'PL_FilmicStrength' and math.abs((sent[k] or 0) - v) > 1e-3 then ok = false; break end end
        if ok then return p.name end
      end
      return nil
    end,
    testValue = function (cur) return cur == 'Broadcast' and 'Golden hour' or 'Broadcast' end })
  for _, p in ipairs(M.PRESETS) do R.byId.preset.options[#R.byId.preset.options + 1] = { label = p.name, value = p.name } end
  R.state('blend', 'Blend two looks', { kind = 'mixer', min = 0, max = 100, step = 1, default = 0, key = 'crossfade of two presets',
    get = function () return S.blend end, set = function (v) M.applyBlend(v) end, frames = 2,
    readback = function ()   -- recover the blend amount from the temperature the shader received
      local a, b = M.PRESETS[1].values.PL_Temperature, M.presetByName(S.blendWith).values.PL_Temperature
      if math.abs(b - a) < 1e-6 then return S.blend end
      return ((sent.PL_Temperature or 0) - a) / (b - a) * 100
    end, tolerance = 0.5 })
  R.state('blendPair', 'Second look', { kind = 'seg', key = 'second preset of the blend',
    options = { { label = 'Night run', value = 'Night run' }, { label = 'Golden hour', value = 'Golden hour' }, { label = 'Rain run', value = 'Rain run' } },
    get = function () return S.blendWith end, set = function (v) M.applyBlend(S.blend, v) end,
    readback = function () return S.blendWith end })
  lookValue('contrast', 'Contrast', 'PL_Contrast', -50, 50, 100, signed)
  lookValue('hl', 'Highlight roll-off', 'PL_FilmicStrength', 0, 100, 100, fmt.pct)
  lookValue('lift', 'Shadow lift', 'PL_Lift', -20, 20, 20, signed)
  lookValue('wb_temp', 'Temperature', 'PL_Temperature', -100, 100, 100, signed)
  lookValue('wb_tint', 'Tint', 'PL_Tint', -100, 100, 100, signed)
  lookValue('sat', 'Saturation', 'PL_Saturation', -50, 50, 100, signed)
  lookValue('sharpen', 'Sharpen', 'PL_Sharpen', 0, 100, 100, fmt.pct, { kind = 'knob' })
  lookValue('clarity', 'Clarity', 'PL_Clarity', 0, 100, 100, fmt.pct, { kind = 'knob' })
  R.state('neural', 'Neural', { kind = 'knob', min = 0, max = 100, step = 1, default = 60, fmt = fmt.pct, key = 'neural gain (×3.5)',
    get = function () return S.nr * 100 end, set = function (v) S.nr = v / 100 end, frames = 2,
    readback = function () return look.active.neural and S.nr * 100 or 0 end })
  R.state('neuralOn', 'Neural detail pass', { kind = 'toggle', hint = 'Runs after DLSS or FSR', frames = 2,
    get = function () return S.neural end, set = function (v) S.neural = v end,
    readback = function () return look.active.neural == true end })
  lookValue('exposure', 'Exposure', 'PL_Exposure', -2, 2, 1, function (v) return string.format('%+.2f EV', v) end, { step = 0.05 })
  R.state('adapt', 'Eye adaptation speed', { kind = 'slider', min = 0, max = 100, step = 1, default = 40, fmt = fmt.pct,
    key = 'auto-exposure rate (0 = off)', frames = 2,
    get = function () return S.adapt end, set = function (v) S.adapt = v end,
    readback = function () return (sent.gPLAdaptOn or 0) > 0.5 and S.adapt or 0 end })
  R.state('autoLook', 'Switch look with time of day', { kind = 'toggle', hint = 'Night look after sunset, golden at dusk',
    get = function () return S.autoLook end, set = function (v) S.autoLook = v end, readback = function () return S.autoLook end })
  lookValue('vig', 'Vignette', 'PL_Vignette', 0, 100, 100, fmt.pct, { kind = 'knob' })
  lookValue('grain', 'Grain', 'PL_Grain', 0, 100, 100, fmt.pct, { kind = 'knob' })
  lookValue('ca', 'Fringing', 'PL_ChromaAb', 0, 100, 100, fmt.pct, { kind = 'knob' })

  -- Light tab
  lookValue('bloom', 'Bloom', 'PL_BloomIntensity', 0, 100, 100, fmt.pct, { kind = 'knob' })
  R.ac('glare', 'Glare', 'video', 'POST_PROCESS', 'GLARE', { kind = 'knob', min = 0, max = 100, step = 20, default = 100, fmt = fmt.pct,
    fallback = 5, map = { to = function (x) return math.floor(x / 20 + 0.5) end, from = function (x) return x * 20 end } })
  lookValue('hal', 'Halation', 'PL_Halation', 0, 100, 100, fmt.pct, { kind = 'knob' })
  lookValue('shafts', 'Sun shafts', 'PL_Shafts', 0, 100, 100, fmt.pct)
  lookValue('flare', 'Lens flare', 'PL_Flare', 0, 100, 100, fmt.pct)
  R.csp('wsrefl', 'Windscreen reflections', 'windscreen_fx', 'REFLECTION', 'ENABLED', { hint = 'Dashboard reflected in the glass' })
  R.api('ao', 'Method', { kind = 'seg', key = 'extra_fx.ini [SSAO]/[ASSAO]/[HBAO]',
    options = { { label = 'Off', value = 'Off' }, { label = 'SSAO', value = 'SSAO' }, { label = 'ASSAO', value = 'ASSAO' }, { label = 'HBAO', value = 'HBAO' } },
    get = function () return M.aoMode(C.get) end, set = M.setAoMode, readback = function () return M.aoMode(C.readback) end })
  lookValue('contact', 'Contact shadows', 'PL_AO', 0, 100, 100, fmt.pct)
  R.csp('bounce', 'Bounce light from cars', 'extra_fx', 'LIGHT_BOUNCE', 'CARS', { hint = 'Lights the road and walls around you' })
  R.csp('bounceTrack', 'Bounce light from the track', 'extra_fx', 'LIGHT_BOUNCE', 'ENABLED', { hint = 'Configured tracks only' })

  -- Weather tab, visibility
  lookValue('haze', 'Haze', 'PL_HazeDensity', 0, 100, 100, fmt.pct)
  lookValue('mist', 'Ground mist', 'PL_Mist', 0, 100, 100, fmt.pct)
end

-- CSP allows one ambient-occlusion technique at a time.
function M.aoMode(read)
  if tonumber(read('csp:extra_fx', 'ASSAO', 'ENABLED', 0)) == 1 then return 'ASSAO' end
  if tonumber(read('csp:extra_fx', 'HBAO', 'ENABLED', 0)) == 1 then return 'HBAO' end
  if tonumber(read('csp:extra_fx', 'SSAO', 'ENABLED2', 0)) == 1 then return 'SSAO' end
  return 'Off'
end
function M.setAoMode(m)
  C.set('csp:extra_fx', 'SSAO', 'ENABLED2', m == 'SSAO' and 1 or 0)
  C.set('csp:extra_fx', 'ASSAO', 'ENABLED', m == 'ASSAO' and 1 or 0)
  C.set('csp:extra_fx', 'HBAO', 'ENABLED', m == 'HBAO' and 1 or 0)
end

return M
