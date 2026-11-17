--[[
  Graphics: quality tiers, upscaler, reflections, shadows, world detail, frame cap. Everything writes the files CM uses.

  - Tiers write CSP and video.ini settings as one batch. The performance curve only shows frame rates Lumicorsa measured
    on this PC while that tier was actually running (a tier picked this session is measured from the next session,
    because part of it applies at launch). The design's "pick tier for my GPU" auto-test isn't in the app: it would need
    restarts between tiers.
  - Upscaler: CSP's own DLSS / FSR (graphics_adjustments [FSR]); needs an AC restart.
  - Frame cap: ac.applyRenderingLimits({ fpsLimit }) applies it now, and video.ini keeps it for the next launch.
  - There's no frame-pacing switch in CSP, so the design's Frame pacing toggle isn't in the app.
]]

local C = require('backend/config')

local M = {}

local GA = 'csp:graphics_adjustments'

-- ---------------------------------------------------------------------------------------------- upscaler
M.UPSCALERS = {
  { label = 'DLAA', impl = 3, key = 'QUALITY_DLSS', q = 1 },
  { label = 'DLSS Q', impl = 3, key = 'QUALITY_DLSS', q = 0.6667 },
  { label = 'DLSS B', impl = 3, key = 'QUALITY_DLSS', q = 0.58 },
  { label = 'FSR', impl = 12, key = 'QUALITY_FSR34', q = 0.6667 },
}
local function upscalerFrom(read)
  if tonumber(read(GA, 'FSR', 'ACTIVE', 0)) ~= 1 then return 'Off' end
  local impl = tonumber(read(GA, 'FSR', 'OLD_IMPLEMENTATION', 0))
  for _, u in ipairs(M.UPSCALERS) do
    if u.impl == impl and math.abs((tonumber(read(GA, 'FSR', u.key, 0)) or 0) - u.q) < 0.01 then return u.label end
  end
  return 'Other'
end
function M.upscaler() return upscalerFrom(C.get) end
function M.setUpscaler(label)
  for _, u in ipairs(M.UPSCALERS) do
    if u.label == label then
      C.set(GA, 'FSR', 'ACTIVE', 1); C.set(GA, 'FSR', 'OLD_IMPLEMENTATION', u.impl); C.set(GA, 'FSR', u.key, u.q)
      return
    end
  end
end

-- Running upscaler for the stats rail (what CSP is doing now, not what's configured).
local NAMES = { [0] = 'FSR 1', [2] = 'NIS', [3] = 'DLSS', [5] = 'FSR 2', [7] = 'FSR 3', [10] = 'XeSS', [11] = 'XeSS', [12] = 'FSR 3/4' }
function M.runningUpscaler()
  local sim = ac.getSim()
  if tonumber(C.get(GA, 'FSR', 'ACTIVE', 0)) ~= 1 then return 'Off', false end
  local impl = tonumber(C.get(GA, 'FSR', 'OLD_IMPLEMENTATION', 0))
  local f = sim.upscaleAppliedFactor or 1
  local name = NAMES[impl] or 'Upscaler'
  if impl == 3 and f >= 0.99 then return 'DLSS, DLAA', true end
  if f < 0.99 then return string.format('%s, %d%%', name, math.floor(f * 100 + 0.5)), true end
  return name .. ' (restart AC)', true
end

local function sharpenKey()
  local impl = tonumber(C.get(GA, 'FSR', 'OLD_IMPLEMENTATION', 0))
  return impl == 12 and 'SHARPEN_FSR34' or impl == 0 and 'SHARPEN2' or 'SHARPEN_DLSS'
end

-- ---------------------------------------------------------------------------------------------- tiers
M.TIERS = {
  Low = { video = { { 'ASSETTOCORSA', 'WORLD_DETAIL', 2 }, { 'VIDEO', 'SHADOW_MAP_SIZE', 1024 }, { 'CUBEMAP', 'SIZE', 256 }, { 'CUBEMAP', 'FACES_PER_FRAME', 1 }, { 'MIRROR', 'SIZE', 256 } },
    csp = { { 'extra_fx', 'SSLR', 'ENABLED', 0 }, { 'extra_fx', 'ASSAO', 'ENABLED', 0 }, { 'extra_fx', 'VOLUMETRIC_LIGHTS', 'ENABLED', 0 }, { 'grass_fx', 'BASIC', 'QUALITY', 1 }, { 'smart_shadows', 'BASIC', 'AUTOMATIC_SPLITS_DISTANCE', 120 } } },
  High = { video = { { 'ASSETTOCORSA', 'WORLD_DETAIL', 4 }, { 'VIDEO', 'SHADOW_MAP_SIZE', 2048 }, { 'CUBEMAP', 'SIZE', 512 }, { 'CUBEMAP', 'FACES_PER_FRAME', 2 }, { 'MIRROR', 'SIZE', 512 } },
    csp = { { 'extra_fx', 'SSLR', 'ENABLED', 1 }, { 'extra_fx', 'ASSAO', 'ENABLED', 0 }, { 'extra_fx', 'VOLUMETRIC_LIGHTS', 'ENABLED', 1 }, { 'grass_fx', 'BASIC', 'QUALITY', 2 }, { 'smart_shadows', 'BASIC', 'AUTOMATIC_SPLITS_DISTANCE', 200 } } },
  Ultra = { video = { { 'ASSETTOCORSA', 'WORLD_DETAIL', 5 }, { 'VIDEO', 'SHADOW_MAP_SIZE', 4096 }, { 'CUBEMAP', 'SIZE', 1024 }, { 'CUBEMAP', 'FACES_PER_FRAME', 3 }, { 'MIRROR', 'SIZE', 1024 } },
    csp = { { 'extra_fx', 'SSLR', 'ENABLED', 1 }, { 'extra_fx', 'ASSAO', 'ENABLED', 1 }, { 'extra_fx', 'VOLUMETRIC_LIGHTS', 'ENABLED', 1 }, { 'grass_fx', 'BASIC', 'QUALITY', 3 }, { 'smart_shadows', 'BASIC', 'AUTOMATIC_SPLITS_DISTANCE', 300 } } },
  Super = { video = { { 'ASSETTOCORSA', 'WORLD_DETAIL', 5 }, { 'VIDEO', 'SHADOW_MAP_SIZE', 4096 }, { 'CUBEMAP', 'SIZE', 2048 }, { 'CUBEMAP', 'FACES_PER_FRAME', 6 }, { 'MIRROR', 'SIZE', 2048 } },
    csp = { { 'extra_fx', 'SSLR', 'ENABLED', 1 }, { 'extra_fx', 'ASSAO', 'ENABLED', 1 }, { 'extra_fx', 'VOLUMETRIC_LIGHTS', 'ENABLED', 1 }, { 'grass_fx', 'BASIC', 'QUALITY', 4 }, { 'smart_shadows', 'BASIC', 'AUTOMATIC_SPLITS_DISTANCE', 400 } } },
}
M.TIER_ORDER = { 'Low', 'High', 'Ultra', 'Super' }

function M.applyTier(name)
  local t = M.TIERS[name]
  if not t then return end
  for _, v in ipairs(t.video) do C.set('ac:video', v[1], v[2], v[3]) end
  for _, v in ipairs(t.csp) do C.set('csp:' .. v[1], v[2], v[3], v[4]) end
end

-- The tier the current files describe (nil if they've been edited by hand).
function M.currentTier(read)
  read = read or C.get
  for _, name in ipairs(M.TIER_ORDER) do
    local t, match = M.TIERS[name], true
    for _, v in ipairs(t.video) do if tonumber(read('ac:video', v[1], v[2], 0)) ~= v[3] then match = false end end
    for _, v in ipairs(t.csp) do if tonumber(read('csp:' .. v[1], v[2], v[3], 0)) ~= v[4] then match = false end end
    if match then return name end
  end
  return nil
end

-- Measured frame rate per tier: recorded only while the tier that was active at session start is still active.
local measured = {}
local startTier = nil
function M.loadTierFps(json) local ok, t = pcall(JSON.parse, json or ''); measured = ok and type(t) == 'table' and t or {} end
function M.tierFps(name) return measured[name] end
function M.recordTierFps(fps, St)
  startTier = startTier or (M.currentTier() or 'none')
  local now = M.currentTier()
  if not now or now ~= startTier or not fps or fps <= 0 then return end
  local m = measured[now]
  measured[now] = m and (m + (fps - m) * 0.02) or fps
  C.later('state/tierfps', measured, function (t) St.tierFps = JSON.stringify(t) end)
end

-- ---------------------------------------------------------------------------------------------- frame cap
local limit = nil
function M.frameCap()
  local ms = tonumber(C.get('ac:video', 'VIDEO', 'FPS_CAP_MS', 0)) or 0
  return ms > 0 and 1000 / ms or 240
end
function M.setFrameCap(fps, now)
  if limit then pcall(function () limit:dispose() end); limit = nil end
  local ok, l = pcall(ac.applyRenderingLimits, { fpsLimit = fps })
  if ok then limit = l end
  if now then C.set('ac:video', 'VIDEO', 'FPS_CAP_MS', 1000 / fps)
  else C.setLater('ac:video', 'VIDEO', 'FPS_CAP_MS', 1000 / fps) end
end

-- ---------------------------------------------------------------------------------------------- registry
local function snap(list) return function (v) local best = list[1]; for _, x in ipairs(list) do if math.abs(x - v) < math.abs(best - v) then best = x end end; return best end end

function M.register(R, St)
  local fmt = R.fmt
  M.loadTierFps(St.tierFps)
  R.api('tier', 'Quality tier', { kind = 'perf', options = { { label = 'Low', value = 'Low' }, { label = 'High', value = 'High' },
      { label = 'Ultra', value = 'Ultra' }, { label = 'Super', value = 'Super' } }, apply = 'next', key = 'video.ini + CSP batch',
    get = function () return M.currentTier() end, set = M.applyTier,
    readback = function () return M.currentTier(C.readback) end })
  R.api('up', 'Upscaler', { kind = 'seg', apply = 'restart', key = 'graphics_adjustments.ini [FSR]',
    options = { { label = 'DLAA', value = 'DLAA' }, { label = 'DLSS Q', value = 'DLSS Q' }, { label = 'DLSS B', value = 'DLSS B' }, { label = 'FSR', value = 'FSR' } },
    get = M.upscaler, set = M.setUpscaler, readback = function () return upscalerFrom(C.readback) end })
  R.csp('rscale', 'Render scale', 'graphics_adjustments', 'RENDER_SCALE', 'SCALE',
    { kind = 'slider', min = 50, max = 100, step = 1, default = 100, fmt = fmt.pct, map = { to = function (x) return x / 100 end, from = function (x) return x * 100 end } })
  R.api('upsharp', 'Upscaler sharpness', { kind = 'slider', min = 0, max = 100, step = 1, default = 30, fmt = fmt.pct,
    key = 'graphics_adjustments.ini [FSR] SHARPEN_*',
    get = function () return (tonumber(C.get(GA, 'FSR', sharpenKey(), 0)) or 0) * 100 end,
    set = function (v, now) if now then C.set(GA, 'FSR', sharpenKey(), v / 100) else C.setLater(GA, 'FSR', sharpenKey(), v / 100) end end,
    readback = function () return (tonumber(C.readback(GA, 'FSR', sharpenKey(), 0)) or 0) * 100 end })

  local cube = snap({ 256, 512, 1024, 2048 })
  R.ac('cube', 'Cubemap resolution', 'video', 'CUBEMAP', 'SIZE', { kind = 'slider', min = 256, max = 2048, default = 1024,
    fmt = fmt.unit(' px'), fallback = 1024, map = { to = cube, from = function (x) return x end }, snap = cube })
  R.ac('faces', 'Faces per frame', 'video', 'CUBEMAP', 'FACES_PER_FRAME', { kind = 'slider', min = 1, max = 6, step = 1, default = 3, fmt = fmt.int, fallback = 3 })
  R.csp('sslr', 'Screen-space reflections', 'extra_fx', 'SSLR', 'ENABLED')
  local shres = snap({ 1024, 2048, 4096 })
  R.ac('shres', 'Resolution', 'video', 'VIDEO', 'SHADOW_MAP_SIZE', { kind = 'slider', min = 1024, max = 4096, default = 2048,
    fmt = fmt.unit(' px'), fallback = 2048, map = { to = shres, from = function (x) return x end }, snap = shres })
  R.csp('shdist', 'Distance', 'smart_shadows', 'BASIC', 'AUTOMATIC_SPLITS_DISTANCE', { kind = 'slider', fmt = fmt.unit(' m') })
  R.csp('grass', 'Grass density', 'grass_fx', 'BASIC', 'QUALITY', { kind = 'slider', min = 0, max = 100, step = 25, default = 50,
    fmt = fmt.pct, map = { to = function (x) return math.floor(x / 25 + 0.5) end, from = function (x) return x * 25 end } })
  R.api('lod', 'Detail distance', { kind = 'slider', min = 50, max = 200, step = 5, default = 100, fmt = fmt.pct,
    key = 'graphics_adjustments.ini [LODS] TRACK_/CARS_DISTANCE_MULT',
    get = function () return (tonumber(C.get(GA, 'LODS', 'TRACK_DISTANCE_MULT', 1)) or 1) * 100 end,
    set = function (v, now)
      local f = now and C.set or C.setLater
      f(GA, 'LODS', 'TRACK_DISTANCE_MULT', v / 100); f(GA, 'LODS', 'CARS_DISTANCE_MULT', v / 100)
    end,
    readback = function () return (tonumber(C.readback(GA, 'LODS', 'TRACK_DISTANCE_MULT', 1)) or 1) * 100 end })
  local mir = snap({ 256, 512, 1024, 2048 })
  R.ac('mirror', 'Mirror resolution', 'video', 'MIRROR', 'SIZE', { kind = 'slider', min = 256, max = 2048, default = 512,
    fmt = fmt.unit(' px'), fallback = 512, map = { to = mir, from = function (x) return x end }, snap = mir })
  R.api('fpscap', 'Frame cap', { kind = 'slider', min = 30, max = 240, step = 1, default = 144, fmt = fmt.unit(' fps'),
    key = 'ac.applyRenderingLimits + video.ini [VIDEO] FPS_CAP_MS', get = M.frameCap, set = M.setFrameCap,
    readback = function () local ms = tonumber(C.readback('ac:video', 'VIDEO', 'FPS_CAP_MS', 0)) or 0; return ms > 0 and 1000 / ms or 240 end,
    tolerance = 0.6 })
end

return M
