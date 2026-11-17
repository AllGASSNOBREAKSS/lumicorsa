--[[
  Pitwall settings bridge: reads and writes the same files Content Manager and Assetto Corsa use, so every change shows
  up in CM and in game, and changes made in CM show up here.

  - CSP modules: `ac.INIConfig.cspModule(id)` + `:setAndSave()` (user config in Documents/Assetto Corsa/cfg/extension).
    Labels, ranges and option lists come from CSP's own schema files (extension/config/<module>.ini), the same metadata
    CM uses to draw its settings pages. Caches drop on `ac.onCSPConfigChanged`, so edits made in CM appear here live.
  - AC video settings: `ac.INIConfig.videoConfig()` (cfg/video.ini). AC reads it at launch: "next launch".
  - Audio: `ac.getAudioVolume` / `ac.setAudioVolume` (live, saved like AC's own audio settings).
  - Weather time: `ac.setWeatherTimeOffset` / `ac.setWeatherTimeMultiplier` (offline sessions only).
]]

local S = {}

-- ---------------------------------------------------------------------------------------------- schema parser
-- CSP schema line: KEY=default ; Label; spec; more notes
--   spec "1 or 0"                                    -> bool
--   spec "from 50 m to 400, round to 10" / ", perc." -> range
--   spec `"Label" is 3, Other is 4` / `0 for Low`     -> enum
local function trim(s) return (s:gsub('^%s+', ''):gsub('%s+$', '')) end
local function unquote(s)
  s = trim(s)
  s = s:gsub('^"', ''):gsub('"$', ''):gsub('^“', ''):gsub('”$', '')
  return trim(s)
end

-- split on commas outside quotes ("…", “…”)
local function splitItems(spec)
  local items, cur, inQ = {}, {}, false
  local i, n = 1, #spec
  while i <= n do
    local c = spec:sub(i, i)
    local c3 = spec:sub(i, i + 2)
    if c == '"' then inQ = not inQ; cur[#cur + 1] = c; i = i + 1
    elseif c3 == '“' then inQ = true; cur[#cur + 1] = c3; i = i + 3
    elseif c3 == '”' then inQ = false; cur[#cur + 1] = c3; i = i + 3
    elseif c == ',' and not inQ then items[#items + 1] = trim(table.concat(cur)); cur = {}; i = i + 1
    else cur[#cur + 1] = c; i = i + 1 end
  end
  if #cur > 0 then items[#items + 1] = trim(table.concat(cur)) end
  return items
end

local function typed(v)
  local n = tonumber(v)
  if n ~= nil then return n end
  return v
end

local function parseEnum(spec)
  local out = {}
  for _, item in ipairs(splitItems(spec)) do
    if item ~= '' and item ~= '__separator__' then
      -- "MEDIUM, HIGH or ULTRA": a trailing "X or Y"
      local a, b = item:match('^([%w_%-%.]+) or ([%w_%-%.]+)$')
      if a then
        out[#out + 1] = { label = a, value = typed(a) }
        out[#out + 1] = { label = b, value = typed(b) }
      else
        local label, value = item:match('^(.-)%s+is%s+([^%s]+)$')
        if not label then
          local v2, l2 = item:match('^([^%s]+)%s+for%s+(.+)$')
          value, label = v2, l2
        end
        if label then
          out[#out + 1] = { label = unquote(label), value = typed(unquote(value)) }
        elseif item:match('^[%w_%-%.]+$') then
          out[#out + 1] = { label = item, value = typed(item) }
        end
      end
    end
  end
  return #out > 0 and out or nil
end

function S.parseSpec(default, fields)
  for _, f in ipairs(fields) do
    if f == '1 or 0' or f:match('^1 or 0') then return { kind = 'bool', default = tonumber(default) or 0 } end
    -- optional unit is a word after the first number: "from 50 m to 400", "from 0 car(s) to 50"
    local from, unit, to = f:match('^from%s+(%-?[%d%.]+)%s+(%a[^%d]-)%s+to%s+(%-?[%d%.]+)')
    if not from then from, to = f:match('^from%s+(%-?[%d%.]+)%s+to%s+(%-?[%d%.]+)') end
    if from then
      return {
        kind = 'range', min = tonumber(from), max = tonumber(to), default = tonumber(default) or tonumber(from),
        perc = f:find('perc', 1, true) ~= nil, round = tonumber(f:match('round to%s+([%d%.]+)')) or (f:find('round', 1, true) and 1 or nil),
        unit = unit and trim(unit) ~= '' and trim(unit) or nil,
      }
    end
  end
  for _, f in ipairs(fields) do
    if f:find(' is ', 1, true) or f:find(' for ', 1, true) or f:find(' or ', 1, true) then
      local opts = parseEnum(f)
      if opts then return { kind = 'enum', options = opts, default = typed(trim(default)) } end
    end
  end
  return nil
end

function S.parseSchema(text)
  local schema, section = {}, nil
  for line in text:gmatch('[^\r\n]+') do
    local sec = line:match('^%[(.-)%]')
    if sec then section = sec; schema[section] = schema[section] or {}
    elseif section then
      local key, default, rest = line:match('^([%w_]+)%s*=%s*([^;]-)%s*;(.*)$')
      if key and not rest:find('hidden', 1, true) then
        local fields = {}
        for f in (rest .. ';'):gmatch('(.-);') do fields[#fields + 1] = trim(f) end
        local label = fields[1] ~= '' and fields[1] or nil
        if label then table.remove(fields, 1) else table.remove(fields, 1) end
        local spec = S.parseSpec(trim(default), fields)
        if spec then spec.label = label; schema[section][key] = spec end
      end
    end
  end
  return schema
end

-- ---------------------------------------------------------------------------------------------- CSP modules
local schemas, configs = {}, {}
local watched = {}

local function schemaFor(module)
  if schemas[module] == nil then
    local text = io.load(ac.getFolder(ac.FolderID.ExtCfgSys) .. '/' .. module .. '.ini')
    schemas[module] = text and S.parseSchema(text) or false
  end
  return schemas[module] or nil
end

local function configFor(module)
  if not watched[module] then
    watched[module] = true
    pcall(ac.onCSPConfigChanged, module, function () configs[module] = nil end)   -- CM edited it: re-read
  end
  if configs[module] == nil then
    local ok, cfg = pcall(ac.INIConfig.cspModule, module)
    configs[module] = ok and cfg or false
  end
  return configs[module] or nil
end

-- Describes a CSP setting: { kind, min, max, options, default, perc, unit } or nil if this CSP build doesn't have it.
function S.describe(module, section, key)
  local sc = schemaFor(module)
  return sc and sc[section] and sc[section][key] or nil
end

-- `fallback` sets the type for keys without a usable schema entry ('' for strings such as a style name).
function S.get(module, section, key, fallback)
  local d = S.describe(module, section, key)
  local cfg = configFor(module)
  local default = fallback
  if default == nil then default = d and d.default end
  if default == nil then default = 0 end
  if not cfg then return default end
  return cfg:get(section, key, default)
end

function S.set(module, section, key, value)
  local cfg = configFor(module)
  if not cfg then return false end
  if type(value) == 'boolean' then value = value and 1 or 0 end
  local ok = pcall(cfg.setAndSave, cfg, section, key, value)
  return ok
end

-- ---------------------------------------------------------------------------------------------- debounced writes
-- Sliders change every frame while dragged; saving a CSP config makes CSP reload that module, so writes wait until the
-- value has been still for a moment. `S.pending` shows the new value in the UI meanwhile.
local pending, pendingOrder = {}, {}
S.pending = {}

function S.later(id, value, commit)
  if not pending[id] then pendingOrder[#pendingOrder + 1] = id end
  pending[id] = { value = value, commit = commit, t = os.preciseClock() }
  S.pending[id] = value
end

function S.flush(force)
  local now = os.preciseClock()
  local keep = {}
  for _, id in ipairs(pendingOrder) do
    local p = pending[id]
    if p and (force or now - p.t > 0.35) then
      pending[id], S.pending[id] = nil, nil
      pcall(p.commit, p.value)
    elseif p then keep[#keep + 1] = id end
  end
  pendingOrder = keep
end

function S.setLater(module, section, key, value)
  S.later(module .. '/' .. section .. '/' .. key, value, function (v) S.set(module, section, key, v) end)
end

function S.getShown(module, section, key)
  local p = S.pending[module .. '/' .. section .. '/' .. key]
  if p ~= nil then return p end
  return S.get(module, section, key)
end

-- ---------------------------------------------------------------------------------------------- AC video.ini
local video = nil
local function videoCfg()
  if video == nil then
    local ok, cfg = pcall(ac.INIConfig.videoConfig)
    video = ok and cfg or false
    pcall(ac.onFileChanged, ac.getFolder(ac.FolderID.Cfg) .. '/video.ini', function () video = nil end)
  end
  return video or nil
end

function S.videoGet(section, key, default)
  local cfg = videoCfg()
  return cfg and cfg:get(section, key, default) or default
end

function S.videoSet(section, key, value)
  local cfg = videoCfg()
  if not cfg then return false end
  return pcall(cfg.setAndSave, cfg, section, key, value)
end

-- ---------------------------------------------------------------------------------------------- folders and lists
-- AC post-processing filters (system/cfg/ppfilters/*.ini), names without ".ini".
function S.ppFilters()
  local out = {}
  local ok, files = pcall(io.scanDir, ac.getFolder(ac.FolderID.PPFilters), '*.ini')
  if ok and type(files) == 'table' then
    for _, f in ipairs(files) do out[#out + 1] = f:gsub('%.ini$', '') end
  end
  table.sort(out, function (a, b) return a:lower() < b:lower() end)
  return out
end

function S.currentPpFilter()
  local f = ac.getPpFilter and ac.getPpFilter() or nil
  if f then f = f:gsub('%.ini$', '') end
  return f or S.videoGet('POST_PROCESS', 'FILTER', 'default')
end

-- Subfolders of `dir` that contain `marker`.
local function foldersWith(dir, marker)
  local out = {}
  local ok, entries = pcall(io.scanDir, dir, '*')
  if ok and type(entries) == 'table' then
    for _, name in ipairs(entries) do
      if io.fileExists(dir .. '/' .. name .. '/' .. marker) then out[#out + 1] = name end
    end
  end
  table.sort(out, function (a, b) return a:lower() < b:lower() end)
  return out
end

-- CSP scriptable post-processing filters (extension/lua/pp-filters/<name>/filter.lua)
function S.cspFilters() return foldersWith(ac.getFolder(ac.FolderID.ExtRoot) .. '/lua/pp-filters', 'filter.lua') end

-- WeatherFX styles (extension/weather/<name>/manifest.ini), e.g. pure, Pure LCS, sol, base.
function S.weatherStyles() return foldersWith(ac.getFolder(ac.FolderID.ExtRoot) .. '/weather', 'manifest.ini') end

-- ---------------------------------------------------------------------------------------------- Pure
local PURE_APPS = {
  config = { folder = 'PureConfig', window = 'IMGUI_LUA_PureConfig_main_pure_config', label = 'Pure Config' },
  planner = { folder = 'PurePlanner', window = 'IMGUI_LUA_PurePlanner_main_pure_planner', label = 'Pure Planner' },
  pp = { folder = 'PurePP', window = 'IMGUI_LUA_PurePP_main_pure_pp', label = 'Pure PP' },
}
S.pureApps = PURE_APPS

function S.pureInstalled() return io.dirExists(ac.getFolder(ac.FolderID.ExtRoot) .. '/weather/pure') end

function S.pureVersion()
  local text = io.load(ac.getFolder(ac.FolderID.ExtRoot) .. '/weather/pure/manifest.ini')
  return text and text:match('VERSION%s*=%s*([^\r\n;]+)') and trim(text:match('VERSION%s*=%s*([^\r\n;]+)')) or nil
end

function S.pureAppAvailable(id)
  return io.dirExists(ac.getFolder(ac.FolderID.ACAppsLua) .. '/' .. PURE_APPS[id].folder)
end

-- Opens one of Pure's own apps (its full controls live there).
function S.openPureApp(id)
  local app = PURE_APPS[id]
  local ok = pcall(function ()
    local w = ac.accessAppWindow(app.window)
    if w then w:setVisible(true) else ac.setAppWindowVisible(app.folder, '?', true) end
  end)
  return ok
end

-- Style options CM shows for the active WeatherFX style (extension/weather/<style>/settings.ini schema), stored in
-- cfg/extension/state/lua/wfx_impl/<style>__settings.ini. That folder doesn't trigger live reloads, so the caller
-- reloads WeatherFX afterwards.
local function styleSettingsPath(style)
  return ac.getFolder(ac.FolderID.ExtCfgState) .. '/lua/wfx_impl/' .. style .. '__settings.ini'
end

function S.styleOption(style, section, key, default)
  local ok, cfg = pcall(ac.INIConfig.load, styleSettingsPath(style))
  if ok and cfg then return cfg:get(section, key, default) end
  return default
end

function S.setStyleOption(style, section, key, value)
  local ok, cfg = pcall(ac.INIConfig.load, styleSettingsPath(style))
  if not ok or not cfg then return false end
  cfg:set(section, key, value)
  return pcall(cfg.save, cfg)
end

-- Re-applies the active WeatherFX style (a config change on the module makes CSP reload it).
function S.reloadWeather()
  local style = S.get('weather_fx', 'BASIC', 'IMPLEMENTATION', '')
  if type(style) ~= 'string' or style == '' then return false end
  S.set('weather_fx', 'BASIC', 'IMPLEMENTATION', 'base')
  setTimeout(function () S.set('weather_fx', 'BASIC', 'IMPLEMENTATION', style) end, 0.5)
  return true
end

-- ---------------------------------------------------------------------------------------------- audio
S.audioChannels = {
  { key = 'main', label = 'Master' }, { key = 'engine', label = 'Engine' }, { key = 'transmission', label = 'Transmission' },
  { key = 'tyres', label = 'Tyres' }, { key = 'surfaces', label = 'Surfaces' }, { key = 'dirt', label = 'Dirt' },
  { key = 'wind', label = 'Wind' }, { key = 'opponents', label = 'Opponents' }, { key = 'carComponents', label = 'Car components' },
  { key = 'track', label = 'Track' }, { key = 'weather', label = 'Weather' }, { key = 'rain', label = 'Rain' },
  { key = 'wipers', label = 'Wipers' },
}

function S.volume(key)
  if S.pending['audio/' .. key] ~= nil then return S.pending['audio/' .. key] end
  local ok, v = pcall(ac.getAudioVolume, key)
  return ok and type(v) == 'number' and v >= 0 and v or nil
end

-- Live while dragging (not saved), then saved once the slider settles.
function S.setVolume(key, v)
  v = math.min(math.max(v, 0), 1)
  pcall(ac.setAudioVolume, key, v, -1, false)
  S.later('audio/' .. key, v, function (x) pcall(ac.setAudioVolume, key, x, -1, true) end)
end

-- ---------------------------------------------------------------------------------------------- weather and time
local WEATHER_NAMES = {
  [0] = 'Light thunderstorm', 'Thunderstorm', 'Heavy thunderstorm', 'Light drizzle', 'Drizzle', 'Heavy drizzle',
  'Light rain', 'Rain', 'Heavy rain', 'Light snow', 'Snow', 'Heavy snow', 'Light sleet', 'Sleet', 'Heavy sleet', 'Clear',
  'Few clouds', 'Scattered clouds', 'Broken clouds', 'Overcast', 'Fog', 'Mist', 'Smoke', 'Haze', 'Sand', 'Dust',
  'Squalls', 'Tornado', 'Hurricane', 'Cold', 'Hot', 'Windy', 'Hail',
}
function S.weatherName(t) return WEATHER_NAMES[t] or 'Unknown' end

function S.timeEditable() return not ac.getSim().isOnlineRace end

-- Jump to a time of day (seconds from midnight). Offline only.
function S.setTimeOfDay(seconds)
  if not S.timeEditable() then return false end
  local now = ac.getSim().timeTotalSeconds or 0
  local delta = seconds - now
  return pcall(ac.setWeatherTimeOffset, delta, true)
end

function S.shiftTime(seconds)
  if not S.timeEditable() then return false end
  return pcall(ac.setWeatherTimeOffset, seconds, true)
end

function S.setTimeSpeed(mult)
  if not S.timeEditable() then return false end
  return pcall(ac.setWeatherTimeMultiplier, mult)
end

-- ---------------------------------------------------------------------------------------------- camera
function S.fov() return ac.getSim().firstPersonCameraFOV end
function S.setFov(v) return pcall(ac.setFirstPersonCameraFOV, v) end
function S.resetFov() return pcall(ac.resetFirstPersonCameraFOV) end

return S
