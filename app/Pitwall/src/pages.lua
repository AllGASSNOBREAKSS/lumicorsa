--[[
  Pitwall pages. Each page returns a list of cards for ui_kit.page(). Rows bind straight to their source of truth:
  Pitwall's own look (ctx.store / ctx.values), CSP module configs and AC's video.ini (settings.lua), audio channels,
  weather time. Nothing here keeps a private copy of a game setting.
]]

local K = require('src/ui_kit')
local S = require('src/settings')
local C = K.C

local P = {}

-- ---------------------------------------------------------------------------------------------- row builders
local function pct(v) return string.format('%d%%', math.floor(v * 100 + 0.5)) end
local function signed(v) return string.format('%+.2f', v) end

-- Strip CSP's long option notes: "NVIDIA DLSS (v310.9.1.0, requires NVIDIA GPU, ⏬29.4 MB)" -> "NVIDIA DLSS".
local function shortOptions(opts)
  local out = {}
  for _, o in ipairs(opts) do
    local l = o.label:gsub('%s*%b()', ''):gsub('%s+$', '')
    out[#out + 1] = { label = l ~= '' and l or o.label, value = o.value }
  end
  return out
end

-- A CSP module setting, typed from CSP's own schema. Missing in this CSP build -> a quiet info row.
local function csp(module, section, key, label, o)
  o = o or {}
  local d = S.describe(module, section, key)
  if not d then return { kind = 'info', label = label, value = 'n/a in this CSP', color = C.faint, hidden = o.hidden } end
  local row = { label = label, apply = o.apply, hidden = o.hidden, disabled = o.disabled }
  if d.kind == 'bool' then
    row.kind = 'toggle'
    row.get = function () return tonumber(S.get(module, section, key)) == 1 end
    row.set = function (v) S.set(module, section, key, v and 1 or 0) end
  elseif d.kind == 'range' then
    row.kind = 'slider'
    row.min, row.max, row.step = o.min or d.min, o.max or d.max, d.round
    row.get = function () return tonumber(S.getShown(module, section, key)) or d.default end
    row.set = function (v) S.setLater(module, section, key, v) end
    if d.perc then row.fmt = pct
    elseif d.round and d.round >= 1 then row.fmt = function (v) return string.format('%d%s', math.floor(v + 0.5), d.unit and (' ' .. d.unit) or '') end
    else row.fmt = '%.2f' end
  else
    row.kind = 'choice'
    row.options = o.options or shortOptions(d.options)
    row.get = function () return S.get(module, section, key) end
    row.set = function (v) S.set(module, section, key, v) end
  end
  return row
end

-- A Pitwall look value (PL_*), live.
local function look(ctx, key, label, min, max, fmt)
  return { kind = 'slider', label = label, min = min, max = max, fmt = fmt or '%.2f',
    get = function () return ctx.values[key] or 0 end, set = function (v) ctx.setValue(key, v) end }
end

local function storeToggle(ctx, key, label)
  return { kind = 'toggle', label = label, get = function () return ctx.store[key] end, set = function (v) ctx.store[key] = v end }
end

-- AC video.ini value (applies next launch).
local function video(section, key, label, kind, opts, default)
  local row = { label = label, apply = 'next' }
  if kind == 'toggle' then
    row.kind = 'toggle'
    row.get = function () return tonumber(S.videoGet(section, key, default or 0)) == 1 end
    row.set = function (v) S.videoSet(section, key, v and 1 or 0) end
  else
    row.kind = 'choice'
    row.options = opts
    row.get = function () return S.videoGet(section, key, default) end
    row.set = function (v) S.videoSet(section, key, v) end
  end
  return row
end

local function levels(n, names)
  local out = {}
  for i = 0, n do out[#out + 1] = { label = names and names[i + 1] or tostring(i), value = i } end
  return out
end
local function list(values, suffix)
  local out = {}
  for _, v in ipairs(values) do out[#out + 1] = { label = tostring(v) .. (suffix or ''), value = v } end
  return out
end

-- ---------------------------------------------------------------------------------------------- LOOK
function P.look(ctx)
  local st, status = ctx.store, ctx.status
  local presets = {}
  for _, p in ipairs(ctx.presets) do
    presets[#presets + 1] = { label = p.name, active = st.preset == p.id, on = function () ctx.loadPreset(p) end }
  end
  local cards = {
    { title = 'Master', icon = ui.Icons.Bulb, color = C.yellow, rows = {
      { kind = 'toggle', label = st.enabled and 'Engaged' or 'Bypassed (vanilla AC)', get = function () return st.enabled end, set = function (v) st.enabled = v end },
      storeToggle(ctx, 'split', 'Before / after split'),
      { kind = 'slider', label = 'Mix', min = 0, max = 1, fmt = pct, get = function () return st.mix end, set = function (v) st.mix = v end },
    } },
    { title = 'Presets', icon = ui.Icons.StarFull, color = C.orange, rows = { { kind = 'presets', items = presets } } },
    { title = 'Quick tune', icon = ui.Icons.Sliders, color = C.blue, rows = {
      look(ctx, 'PL_Exposure', 'Exposure', -2, 2, function (v) return string.format('%+.2f EV', v) end),
      look(ctx, 'PL_BloomIntensity', 'Bloom', 0, 1, pct),
      look(ctx, 'PL_Sharpen', 'Sharpen', 0, 1, pct),
      { kind = 'slider', label = 'Neural detail', min = 0, max = 1, fmt = pct, get = function () return st.nr_intensity end, set = function (v) st.nr_intensity = v end },
    } },
    P.statusCard(ctx),
  }
  return cards
end

function P.statusCard(ctx)
  local status, st = ctx.status, ctx.store
  local gpu = 'measuring…'
  if status.gpuOn and status.gpuOff then gpu = string.format('≈ %.1f ms', math.max(status.gpuOn - status.gpuOff, 0))
  elseif status.gpuOn then gpu = 'Alt+O twice to measure' end
  local rows = {
    { kind = 'info', label = 'Shaders', value = status.shaders, color = status.shadersOk and C.green or (st.enabled and C.orange or C.muted) },
    { kind = 'info', label = 'Neural', value = (st.enabled and st.neural and st.nr_intensity > 0) and ('on · ' .. pct(st.nr_intensity)) or 'off', color = C.blue },
    { kind = 'info', label = 'GPU cost', value = gpu, color = C.yellow },
    { kind = 'info', label = 'Upscaler', value = status.upscaler, color = status.upscalerOn and C.green or C.muted },
  }
  if not status.upscalerOn then rows[#rows + 1] = { kind = 'note', text = 'Turn on DLSS or FSR in Graphics › Upscale (or CM › Settings › Custom Shaders Patch).' } end
  if status.conflict then rows[#rows + 1] = { kind = 'note', color = C.orange, text = status.conflict .. ' is active: Pitwall stays on top and skips its own re-tonemap.' } end
  if status.notice then rows[#rows + 1] = { kind = 'note', color = C.orange, text = status.notice } end
  return { title = 'Status', icon = ui.Icons.Info, color = C.green, rows = rows }
end

-- ---------------------------------------------------------------------------------------------- EFFECTS
local FX_TABS = { { label = 'Light & grade', value = 'light' }, { label = 'Detail & lens', value = 'lens' } }

function P.effects(ctx)
  local cards = { { title = 'Pitwall look', icon = ui.Icons.Sliders, color = C.orange, rows = {
    { kind = 'choice', label = 'Section', options = FX_TABS, get = function () return ctx.store.fxTab end, set = function (v) ctx.store.fxTab = v; ctx.resetScroll() end },
  } } }
  local all = P.effectCards(ctx)
  local from, to = 1, 2
  if ctx.store.fxTab == 'lens' then from, to = 3, 5 end
  for i = from, to do cards[#cards + 1] = all[i] end
  return cards
end

function P.effectCards(ctx)
  return {
    { title = 'HDR light', icon = ui.Icons.Bulb, color = C.yellow, rows = {
      storeToggle(ctx, 'light', 'Enabled'),
      look(ctx, 'PL_HighlightRecover', 'Highlight recovery', 0, 1, pct),
      look(ctx, 'PL_Halation', 'Halation', 0, 1, pct),
      look(ctx, 'PL_FilmicStrength', 'Filmic response', 0, 1, pct),
      look(ctx, 'PL_Temperature', 'Temperature', -1, 1, signed),
      look(ctx, 'PL_Tint', 'Tint', -1, 1, signed),
    } },
    { title = 'Grade', icon = ui.Icons.Palette, color = C.blue, rows = {
      look(ctx, 'PL_Contrast', 'Contrast', -0.5, 0.5, signed),
      look(ctx, 'PL_Saturation', 'Saturation', -1, 1, signed),
      look(ctx, 'PL_Vibrance', 'Vibrance', -1, 1, signed),
    } },
    { title = 'Atmosphere', icon = ui.Icons.WeatherFog, color = C.blue, rows = {
      storeToggle(ctx, 'atmos', 'Enabled'),
      look(ctx, 'PL_HazeDensity', 'Distance haze', 0, 1, pct),
      look(ctx, 'PL_AerialDesat', 'Aerial desaturation', 0, 1, pct),
    } },
    { title = 'Detail', icon = ui.Icons.Target, color = C.orange, rows = {
      storeToggle(ctx, 'detail', 'Enabled'),
      look(ctx, 'PL_Clarity', 'Clarity', 0, 1, pct),
      look(ctx, 'PL_Sharpen', 'Adaptive sharpen', 0, 1, pct),
    } },
    { title = 'Lens', icon = ui.Icons.Lens, color = C.red, rows = {
      storeToggle(ctx, 'lens', 'Enabled'),
      look(ctx, 'PL_ChromaAb', 'Chromatic aberration', 0, 1, pct),
      look(ctx, 'PL_Vignette', 'Vignette', 0, 1, pct),
      look(ctx, 'PL_Grain', 'Film grain', 0, 1, pct),
    } },
  }
end

-- ---------------------------------------------------------------------------------------------- REALISM
function P.realism(ctx)
  local st = ctx.store
  return {
    { title = 'Pitwall Neural', icon = ui.Icons.Eye, color = C.blue, rows = {
      storeToggle(ctx, 'neural', 'Neural detail pass'),
      { kind = 'slider', label = 'Intensity', min = 0, max = 1, fmt = pct, get = function () return st.nr_intensity end, set = function (v) st.nr_intensity = v end },
      { kind = 'note', text = 'A small CNN (Anime4K restore weights, MIT) used as a learned detail enhancer. Not NVIDIA DLSS.' },
    } },
    { title = 'Sun shafts', icon = ui.Icons.WeatherClear, color = C.yellow, rows = {
      storeToggle(ctx, 'shafts', 'Light rays through gaps in the sky'),
      look(ctx, 'PL_Shafts', 'Strength', 0, 1.5, pct),
    } },
    { title = 'Lens flare', icon = ui.Icons.StarFull, color = C.orange, rows = {
      storeToggle(ctx, 'flare', 'Ghosts and halo from bright lights'),
      look(ctx, 'PL_Flare', 'Strength', 0, 1, pct),
    } },
    { title = 'Contact shadows', icon = ui.Icons.Contrast, color = C.green, rows = {
      storeToggle(ctx, 'ao', 'Ambient occlusion in creases'),
      look(ctx, 'PL_AO', 'Strength', 0, 1, pct),
    } },
    { title = 'Depth of field', icon = ui.Icons.CameraAlt, color = C.red, rows = {
      { kind = 'choice', label = 'When', options = { { label = 'Off', value = 0 }, { label = 'Replays', value = 1 }, { label = 'Always', value = 2 } },
        get = function () return st.dof end, set = function (v) st.dof = v end },
      look(ctx, 'PL_Dof', 'Background blur', 0, 1, pct),
    } },
  }
end

-- ---------------------------------------------------------------------------------------------- PURE
function P.pure(ctx)
  local installed = S.pureInstalled()
  local style = S.get('weather_fx', 'BASIC', 'IMPLEMENTATION', '')
  local styles = {}
  for _, s in ipairs(S.weatherStyles()) do styles[#styles + 1] = { label = s, value = s } end
  local isPure = type(style) == 'string' and style:lower():find('pure', 1, true) ~= nil
  local function styleToggle(section, key, label)
    return { kind = 'toggle', label = label, disabled = not isPure,
      get = function () return tonumber(S.styleOption(style, section, key, 0)) == 1 end,
      set = function (v) S.setStyleOption(style, section, key, v and 1 or 0) end }
  end
  local apps = {}
  for _, id in ipairs({ 'config', 'planner', 'pp' }) do
    apps[#apps + 1] = { label = S.pureApps[id].label, disabled = not S.pureAppAvailable(id), on = function () S.openPureApp(id) end }
  end
  return {
    { title = 'Pure', icon = ui.Icons.WeatherFewClouds, color = C.blue,
      badge = installed and { label = 'v' .. (S.pureVersion() or '?'), color = C.green } or { label = 'NOT INSTALLED', color = C.orange }, rows = {
      { kind = 'info', label = 'Active WeatherFX style', value = tostring(style), color = isPure and C.green or C.yellow },
      csp('weather_fx', 'BASIC', 'ENABLED', 'WeatherFX enabled'),
      { kind = 'choice', label = 'Style', options = styles, get = function () return style end, set = function (v) S.set('weather_fx', 'BASIC', 'IMPLEMENTATION', v) end },
    } },
    { title = 'Pure options', icon = ui.Icons.SettingsAlt, color = C.orange, rows = {
      styleToggle('POSTPROCESSING', 'LIGHTWEIGHT_REPLACEMENT', 'Lightweight YEBIS replacement'),
      styleToggle('PERFORMANCE', 'ECO', 'Economic mode'),
      { kind = 'buttons', items = { { label = 'Reload weather to apply', on = S.reloadWeather, disabled = not isPure } } },
    } },
    { title = 'Pure apps', icon = ui.Icons.Apps, color = C.green, rows = {
      { kind = 'buttons', items = apps },
      { kind = 'note', text = 'Pure’s full controls (light, exposure, sky, planner) live in its own apps. These buttons open them.' },
    } },
    { title = 'Scene', icon = ui.Icons.Landscape, color = C.yellow, rows = {
      csp('weather_fx', 'PERFORMANCE', 'EXTRA_CLOUDS_FIDELITY', 'Extra cloud fidelity'),
      csp('weather_fx', 'PERFORMANCE', 'DETAILED_CLOUD_SHADOWS', 'Detailed cloud shadows'),
      csp('weather_fx', 'PERFORMANCE', 'HIGH_QUALITY_STARS', 'High-quality stars'),
      csp('weather_fx', 'PP_TWEAKS', 'FULL_RESOLUTION', 'Full-resolution post-processing'),
    } },
  }
end

-- ---------------------------------------------------------------------------------------------- WEATHER
function P.weather(ctx)
  local sim = ac.getSim()
  local editable = S.timeEditable()
  local cond = {
    { kind = 'info', label = 'Weather', value = S.weatherName(sim.weatherType), color = C.blue },
    { kind = 'info', label = 'Time', value = string.format('%02d:%02d', sim.timeHours or 0, sim.timeMinutes or 0), color = C.yellow },
    { kind = 'info', label = 'Air / road', value = string.format('%.0f °C / %.0f °C', sim.ambientTemperature or 0, sim.roadTemperature or 0) },
    { kind = 'info', label = 'Wind', value = string.format('%.0f km/h · %.0f°', sim.windSpeedKmh or 0, sim.windDirectionDeg or 0) },
    { kind = 'info', label = 'Rain / wetness', value = string.format('%s / %s', pct(sim.rainIntensity or 0), pct(sim.rainWetness or 0)), color = C.blue },
  }
  local function jump(label, h) return { label = label, disabled = not editable, on = function () S.setTimeOfDay(h * 3600) end } end
  local function shift(label, s) return { label = label, disabled = not editable, on = function () S.shiftTime(s) end } end
  local timeRows = {
    { kind = 'buttons', items = { jump('Dawn', 6.5), jump('Noon', 12), jump('Golden', 18.5), jump('Night', 22) } },
    { kind = 'buttons', items = { shift('−1 h', -3600), shift('−15 m', -900), shift('+15 m', 900), shift('+1 h', 3600) } },
    { kind = 'choice', label = 'Time speed', disabled = not editable,
      options = { { label = 'Frozen', value = 0 }, { label = 'Real', value = 1 }, { label = '×10', value = 10 }, { label = '×60', value = 60 } },
      get = function () return ctx.store.timeSpeed end, set = function (v) ctx.store.timeSpeed = v; S.setTimeSpeed(v) end },
  }
  if not editable then timeRows[#timeRows + 1] = { kind = 'note', text = 'Online: the server controls time and weather.' } end
  return {
    { title = 'Conditions', icon = ui.Icons.Thermometer, color = C.blue, rows = cond },
    { title = 'Time of day', icon = ui.Icons.Clock, color = C.orange, badge = (not editable) and { label = 'OFFLINE ONLY', color = C.yellow } or nil, rows = timeRows },
    { title = 'Lights and wipers', icon = ui.Icons.Bulb, color = C.yellow, rows = {
      csp('weather_fx', 'MISCELLANEOUS', 'FORCE_HEADLIGHTS', 'Force headlights'),
      csp('weather_fx', 'MISCELLANEOUS', 'SWITCH_HEADLIGHTS_WITH_AI', 'Headlights follow conditions'),
      csp('weather_fx', 'MISCELLANEOUS', 'SWITCH_WIPERS_WITH_AI', 'Wipers follow rain'),
    } },
    { title = 'Rain', icon = ui.Icons.WeatherRain, color = C.green, rows = {
      csp('rain_fx', 'SCREEN_DROPS', 'ENABLED', 'Drops on screen'),
      csp('rain_fx', 'SCREEN_DROPS', 'INTENSITY_MULT', 'Drop intensity'),
      csp('rain_fx', 'VISUAL_TWEAKS', 'RAIN_MAPS_QUALITY', 'Rain maps quality'),
    } },
  }
end

-- ---------------------------------------------------------------------------------------------- GRAPHICS (CSP)
local GFX_TABS = { { label = 'Upscale', value = 'upscale' }, { label = 'Light', value = 'light' }, { label = 'Effects', value = 'effects' }, { label = 'Detail', value = 'detail' } }

local AO_MODES = { { label = 'Off', value = 'off' }, { label = 'SSAO', value = 'ssao' }, { label = 'ASSAO', value = 'assao' }, { label = 'HBAO', value = 'hbao' } }
local function aoMode()
  if tonumber(S.get('extra_fx', 'ASSAO', 'ENABLED')) == 1 then return 'assao' end
  if tonumber(S.get('extra_fx', 'HBAO', 'ENABLED')) == 1 then return 'hbao' end
  if tonumber(S.get('extra_fx', 'SSAO', 'ENABLED2')) == 1 then return 'ssao' end
  return 'off'
end
local function setAoMode(m)   -- CSP allows one AO technique at a time
  S.set('extra_fx', 'SSAO', 'ENABLED2', m == 'ssao' and 1 or 0)
  S.set('extra_fx', 'ASSAO', 'ENABLED', m == 'assao' and 1 or 0)
  S.set('extra_fx', 'HBAO', 'ENABLED', m == 'hbao' and 1 or 0)
end

function P.graphics(ctx)
  local tab = ctx.store.gfxTab
  local cards = { { title = 'Custom Shaders Patch', icon = ui.Icons.Monitor, color = C.red, rows = {
    { kind = 'choice', label = 'Section', options = GFX_TABS, get = function () return ctx.store.gfxTab end, set = function (v) ctx.store.gfxTab = v; ctx.resetScroll() end },
  } } }
  local impl = tonumber(S.get('graphics_adjustments', 'FSR', 'OLD_IMPLEMENTATION'))
  local upscOn = tonumber(S.get('graphics_adjustments', 'FSR', 'ACTIVE')) == 1
  if tab == 'upscale' then
    cards[#cards + 1] = { title = 'Upscaling', icon = ui.Icons.Speedometer, color = C.blue, rows = {
      csp('graphics_adjustments', 'FSR', 'ACTIVE', 'Upscaler', { apply = 'restart' }),
      csp('graphics_adjustments', 'FSR', 'OLD_IMPLEMENTATION', 'Method', { apply = 'restart', hidden = not upscOn }),
      csp('graphics_adjustments', 'FSR', 'QUALITY_DLSS', 'DLSS quality', { apply = 'restart', hidden = not upscOn or impl ~= 3 }),
      csp('graphics_adjustments', 'FSR', 'SHARPEN_DLSS', 'DLSS sharpness', { hidden = not upscOn or impl ~= 3 }),
      csp('graphics_adjustments', 'FSR', 'QUALITY_FSR34', 'FSR 3/4 quality', { apply = 'restart', hidden = not upscOn or impl ~= 12 }),
      csp('graphics_adjustments', 'FSR', 'SHARPEN_FSR34', 'FSR 3/4 sharpness', { hidden = not upscOn or impl ~= 12 }),
      csp('graphics_adjustments', 'FSR', 'QUALITY2', 'FSR 1 quality', { apply = 'restart', hidden = not upscOn or impl ~= 0 }),
      csp('graphics_adjustments', 'FSR', 'SHARPEN2', 'FSR 1 sharpness', { hidden = not upscOn or impl ~= 0 }),
    } }
    cards[#cards + 1] = { title = 'Anti-aliasing', icon = ui.Icons.Target, color = C.orange, rows = {
      csp('graphics_adjustments', 'ANTIALIASING', 'MODE', 'Post AA'),
      csp('extra_fx', 'TAA', 'ENABLED', 'Temporal AA (Extra FX)'),
      csp('extra_fx', 'TAA', 'EXTRA_SHARPEN_PASS', 'TAA sharpness'),
      csp('graphics_adjustments', 'RENDER_SCALE', 'SCALE', 'Render scale'),
    } }
  elseif tab == 'light' then
    cards[#cards + 1] = { title = 'Shadows', icon = ui.Icons.Contrast, color = C.blue, rows = {
      csp('smart_shadows', 'BASIC', 'AUTOMATIC_SPLITS_DISTANCE', 'Sun shadow distance'),
      csp('lighting_fx', 'SHADOWS', 'ENABLED', 'Shadows from car lights'),
      csp('lighting_fx', 'SHADOWS', 'CARS_SHADOWS', 'Cars casting light shadows'),
      csp('lighting_fx', 'PERFORMANCE', 'CARS_WITH_LIGHTS', 'Cars casting light'),
    } }
    cards[#cards + 1] = { title = 'Global illumination', icon = ui.Icons.Bulb, color = C.yellow, rows = {
      csp('extra_fx', 'SS_LIGHTING', 'ENABLED', 'Screen-space lighting'),
      csp('extra_fx', 'SSGI', 'ENABLED2', 'Screen-space GI'),
      csp('extra_fx', 'VOLUMETRIC_LIGHTS', 'ENABLED', 'Volumetric lights'),
      csp('extra_fx', 'VOLUMETRIC_LIGHTS', 'INTENSITY_MULT', 'Volumetric brightness'),
      { kind = 'choice', label = 'Ambient occlusion', options = AO_MODES, get = aoMode, set = setAoMode },
    } }
  elseif tab == 'effects' then
    cards[#cards + 1] = { title = 'Extra FX', icon = ui.Icons.StarFull, color = C.orange, rows = {
      csp('extra_fx', 'BASIC', 'ENABLED', 'Extra FX'),
      csp('extra_fx', 'MOTION_BLUR', 'ENABLED', 'Motion blur'),
      csp('extra_fx', 'MOTION_BLUR', 'MULT', 'Motion blur amount'),
      csp('extra_fx', 'FOG_BLUR', 'ENABLED', 'Distance blur and heat haze'),
    } }
    cards[#cards + 1] = { title = 'Particles', icon = ui.Icons.Wind, color = C.blue, rows = {
      csp('particles_fx', 'SMOKE', 'ENABLED', 'Tyre smoke'),
      csp('particles_fx', 'SMOKE', 'LONG_LASTING_SMOKE', 'Long-lasting smoke'),
      csp('particles_fx', 'SPARKS', 'ENABLED', 'Sparks'),
      csp('particles_fx', 'AC_PARTICLES', 'REWORKED_HEAT_SHIMMER', 'Reworked heat shimmer', { apply = 'restart' }),
    } }
    cards[#cards + 1] = { title = 'Grass', icon = ui.Icons.Landscape, color = C.green, rows = {
      csp('grass_fx', 'BASIC', 'QUALITY', 'Grass quality'),
      csp('grass_fx', 'RENDERING', 'CAST_SHADOWS', 'Grass casts shadows'),
    } }
  else
    cards[#cards + 1] = { title = 'Level of detail', icon = ui.Icons.CarFront, color = C.yellow, rows = {
      csp('graphics_adjustments', 'LODS', 'CARS_DISTANCE_MULT', 'Car detail distance'),
      csp('graphics_adjustments', 'LODS', 'TRACK_DISTANCE_MULT', 'Track detail distance'),
      csp('graphics_adjustments', 'LODS', 'TREES_DISTANCE_MULT', 'Tree detail distance', { apply = 'restart' }),
      csp('graphics_adjustments', 'LODS', 'HIDE_DISTANT_DRIVERS', 'Hide distant drivers'),
      csp('graphics_adjustments', 'LODS', 'COCKPIT_LR_FIX', 'Low-res cockpits for other cars'),
    } }
    cards[#cards + 1] = { title = 'Reflections', icon = ui.Icons.Eye, color = C.green, rows = {
      csp('extra_fx', 'SSLR', 'ENABLED', 'Screen-space reflections'),
      csp('reflections_fx', 'MAIN_CUBEMAP', 'RESOLUTION2', 'Cubemap resolution'),
      csp('reflections_fx', 'LOCAL_CUBEMAPS_CARS2', 'ENABLED', 'Local car cubemaps'),
    } }
  end
  return cards
end

-- ---------------------------------------------------------------------------------------------- FILTERS
function P.filters(ctx)
  local yebis = {}
  for _, f in ipairs(S.ppFilters()) do yebis[#yebis + 1] = { label = f, value = f } end
  local cspF = {}
  for _, f in ipairs(S.cspFilters()) do cspF[#cspF + 1] = { label = f, value = f } end
  return {
    { title = 'AC post-processing filter', icon = ui.Icons.Film, color = C.yellow, rows = {
      { kind = 'info', label = 'Running now', value = S.currentPpFilter() or '?', color = C.yellow },
      { kind = 'choice', label = 'Filter', apply = 'next', options = yebis,
        get = function () return S.videoGet('POST_PROCESS', 'FILTER', 'default') end,
        set = function (v) S.videoSet('POST_PROCESS', 'FILTER', v) end },
    } },
    { title = 'AC post-processing', icon = ui.Icons.Sliders, color = C.orange, rows = {
      video('POST_PROCESS', 'ENABLED', 'Post-processing', 'toggle', nil, 1),
      video('POST_PROCESS', 'QUALITY', 'Quality', 'choice', levels(5, { 'Off', 'Very low', 'Low', 'Medium', 'High', 'Very high' }), 5),
      video('POST_PROCESS', 'GLARE', 'Glare', 'choice', levels(5, { 'Off', 'Very low', 'Low', 'Medium', 'High', 'Very high' }), 5),
      video('POST_PROCESS', 'DOF', 'Depth of field', 'choice', levels(5, { 'Off', 'Very low', 'Low', 'Medium', 'High', 'Very high' }), 5),
      video('POST_PROCESS', 'RAYS_OF_GOD', 'Sun rays', 'toggle', nil, 1),
      video('POST_PROCESS', 'HEAT_SHIMMER', 'Heat shimmer', 'toggle', nil, 1),
    } },
    { title = 'CSP filter script', icon = ui.Icons.FilmRoll, color = C.blue, rows = {
      csp('graphics_adjustments', 'SCRIPTABLE_FILTER', 'ENABLED', 'Lua filter'),
      { kind = 'choice', label = 'Script', options = cspF,
        get = function () return S.get('graphics_adjustments', 'SCRIPTABLE_FILTER', 'IMPLEMENTATION', '') end,
        set = function (v) S.set('graphics_adjustments', 'SCRIPTABLE_FILTER', 'IMPLEMENTATION', v) end },
    } },
  }
end

-- ---------------------------------------------------------------------------------------------- AUDIO
function P.audio(ctx)
  local rows = {}
  for _, ch in ipairs(S.audioChannels) do
    rows[#rows + 1] = { kind = 'slider', label = ch.label, min = 0, max = 1, fmt = pct,
      get = function () return S.volume(ch.key) or 0 end, set = function (v) S.setVolume(ch.key, v) end,
      disabled = S.volume(ch.key) == nil }
  end
  return { { title = 'Volume', icon = ui.Icons.VolumeHigh, color = C.green, rows = rows } }
end

-- ---------------------------------------------------------------------------------------------- VIDEO (AC)
function P.video(ctx)
  local q = { 'Very low', 'Low', 'Medium', 'High', 'Very high', 'Ultra' }
  return {
    { title = 'Camera', icon = ui.Icons.CameraAlt, color = C.blue, rows = {
      { kind = 'slider', label = 'Cockpit field of view', min = 30, max = 110, step = 1, fmt = '%.0f°',
        get = function () return S.fov() or 56 end, set = function (v) S.setFov(v) end },
      { kind = 'buttons', items = { { label = 'Reset field of view', on = S.resetFov } } },
    } },
    { title = 'World', icon = ui.Icons.Monitor, color = C.orange, rows = {
      video('ASSETTOCORSA', 'WORLD_DETAIL', 'World detail', 'choice', levels(5, q), 4),
      video('VIDEO', 'SHADOW_MAP_SIZE', 'Shadow resolution', 'choice', list({ 512, 1024, 2048, 4096 }), 2048),
      video('VIDEO', 'ANISOTROPIC', 'Texture filtering', 'choice', list({ 0, 2, 4, 8, 16 }, '×'), 16),
      video('EFFECTS', 'SMOKE', 'Smoke', 'choice', levels(5, { 'Off', 'Very low', 'Low', 'Medium', 'High', 'Very high' }), 3),
    } },
    { title = 'Reflections and mirrors', icon = ui.Icons.Eye, color = C.green, rows = {
      video('CUBEMAP', 'SIZE', 'Reflection resolution', 'choice', list({ 256, 512, 1024, 2048 }), 1024),
      video('CUBEMAP', 'FACES_PER_FRAME', 'Reflection faces per frame', 'choice', list({ 1, 2, 3, 4, 5, 6 }), 6),
      video('CUBEMAP', 'FARPLANE', 'Reflection distance', 'choice', list({ 300, 600, 1000, 2000 }, ' m'), 600),
      video('MIRROR', 'HQ', 'High-quality mirrors', 'toggle', nil, 1),
      video('MIRROR', 'SIZE', 'Mirror resolution', 'choice', list({ 256, 512, 1024 }), 512),
    } },
  }
end

-- ---------------------------------------------------------------------------------------------- SYSTEM
function P.system(ctx)
  return {
    P.statusCard(ctx),
    { title = 'Shortcuts', icon = ui.Icons.Keyboard, color = C.yellow, rows = {
      { kind = 'info', label = 'Open / close Pitwall', value = 'Alt + P', color = C.yellow },
      { kind = 'info', label = 'Bypass everything', value = 'Alt + O', color = C.yellow },
      { kind = 'note', text = 'Rebind both in CSP › Controls.' },
    } },
    { title = 'Compatibility', icon = ui.Icons.Shield, color = C.blue, rows = {
      { kind = 'toggle', label = 'Skip re-tonemap when another grading app runs', get = function () return not ctx.store.ignore_conflict end, set = function (v) ctx.store.ignore_conflict = not v end },
      { kind = 'buttons', items = { { label = 'Reset look to Photoreal', on = function () ctx.loadPreset(ctx.presets[1]) end } } },
    } },
    { title = 'About', icon = ui.Icons.Info, color = C.green, rows = {
      { kind = 'info', label = 'Pitwall', value = 'v' .. ctx.version, color = C.blue },
      { kind = 'note', text = 'All-in-one graphics, weather and settings for Assetto Corsa. Needs only Content Manager + CSP. MIT licence; Space Grotesk (OFL) and Anime4K weights (MIT) included.' },
    } },
  }
end

P.nav = {
  { id = 'look', label = 'Look', icon = ui.Icons.Palette, color = C.blue },
  { id = 'effects', label = 'Effects', icon = ui.Icons.Sliders, color = C.orange },
  { id = 'realism', label = 'Realism', icon = ui.Icons.StarFull, color = C.yellow },
  { id = 'pure', label = 'Pure', icon = ui.Icons.WeatherFewClouds, color = C.blue },
  { id = 'weather', label = 'Weather', icon = ui.Icons.WeatherRain, color = C.green },
  { id = 'graphics', label = 'Graphics', icon = ui.Icons.Monitor, color = C.red },
  { id = 'filters', label = 'Filters', icon = ui.Icons.Film, color = C.orange },
  { id = 'audio', label = 'Audio', icon = ui.Icons.VolumeHigh, color = C.green },
  { id = 'video', label = 'Video', icon = ui.Icons.CameraAlt, color = C.yellow },
  { id = 'system', label = 'System', icon = ui.Icons.SettingsAlt, color = C.blue },
}

return P
