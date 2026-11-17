--[[
  Lumicorsa config bridge: reads and writes the same files Content Manager and Assetto Corsa use, so a change shows
  up in CM and in game, and a change made in CM shows up here.

  Sources (a "src" string):
    'csp:<module>'   CSP module config via ac.INIConfig.cspModule() (cfg/extension/<module>.ini). CSP reloads the module
                     when the file changes, so most of these apply live. Control types come from CSP's own schema files
                     (extension/config/<module>.ini), the metadata CM draws its pages from.
    'ac:video'       cfg/video.ini     (AC reads it at launch: "next launch")
    'ac:controls'    cfg/controls.ini  (AC reads it when a session starts: "next session")
    'style:<name>'   WeatherFX style options, cfg/extension/state/lua/wfx_impl/<name>__settings.ini
  Writes from sliders wait 250 ms after the last change (S.setLater). S.readback() re-reads the file from disk, which
  is what the self-test compares against.
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
        table.remove(fields, 1)
        local spec = S.parseSpec(trim(default), fields)
        if spec then spec.label = label; schema[section][key] = spec end
      end
    end
  end
  return schema
end

-- ---------------------------------------------------------------------------------------------- sources
local schemas, configs, watched = {}, {}, {}

function S.path(src)
  local kind, name = src:match('^(%w+):(.+)$')
  if kind == 'csp' then return ac.getFolder(ac.FolderID.ExtCfgUser) .. '/' .. name .. '.ini' end
  if kind == 'ac' then return ac.getFolder(ac.FolderID.Cfg) .. '/' .. name .. '.ini' end
  if kind == 'style' then return ac.getFolder(ac.FolderID.ExtCfgState) .. '/lua/wfx_impl/' .. name .. '__settings.ini' end
  return nil
end

local function open(src)
  if configs[src] ~= nil then return configs[src] or nil end
  local kind, name = src:match('^(%w+):(.+)$')
  local ok, cfg
  if kind == 'csp' then
    ok, cfg = pcall(ac.INIConfig.cspModule, name)
    if not watched[src] then
      watched[src] = true
      pcall(ac.onCSPConfigChanged, name, function () configs[src] = nil end)   -- CM edited it: re-read
    end
  elseif kind == 'ac' then
    ok, cfg = pcall(name == 'video' and ac.INIConfig.videoConfig or ac.INIConfig.controlsConfig)
    if not watched[src] then
      watched[src] = true
      pcall(ac.onFileChanged, S.path(src), function () configs[src] = nil end)
    end
  else
    ok, cfg = pcall(ac.INIConfig.load, S.path(src))
  end
  configs[src] = ok and cfg or false
  return configs[src] or nil
end

-- Describes a CSP setting from its schema: { kind, min, max, options, default, perc, unit } or nil when this CSP build
-- doesn't have it. Only 'csp:' sources have schemas.
function S.describe(src, section, key)
  local module = src:match('^csp:(.+)$')
  if not module then return nil end
  if schemas[module] == nil then
    local text = io.load(ac.getFolder(ac.FolderID.ExtCfgSys) .. '/' .. module .. '.ini')
    schemas[module] = text and S.parseSchema(text) or false
  end
  local sc = schemas[module]
  return sc and sc[section] and sc[section][key] or nil
end

local function defaultFor(src, section, key, fallback)
  if fallback ~= nil then return fallback end
  local d = S.describe(src, section, key)
  if d and d.default ~= nil then return d.default end
  return 0
end

function S.get(src, section, key, fallback)
  local p = S.pending[src .. '/' .. section .. '/' .. key]
  if p ~= nil then return p end
  local cfg = open(src)
  local default = defaultFor(src, section, key, fallback)
  if not cfg then return default end
  return cfg:get(section, key, default)
end

function S.set(src, section, key, value)
  local cfg = open(src)
  if not cfg then return false end
  if type(value) == 'boolean' then value = value and 1 or 0 end
  local kind = src:match('^(%w+):')
  if kind == 'style' then cfg:set(section, key, value); return pcall(cfg.save, cfg) end
  return pcall(cfg.setAndSave, cfg, section, key, value)
end

-- Re-reads the value from the file on disk (not from any cache): what the self-test checks.
function S.readback(src, section, key, fallback)
  local ok, cfg = pcall(ac.INIConfig.load, S.path(src))
  if not ok or not cfg then return nil end
  return cfg:get(section, key, defaultFor(src, section, key, fallback))
end

-- ---------------------------------------------------------------------------------------------- debounced writes
-- Sliders change every frame while dragged. Saving a CSP config makes CSP reload that module, so writes wait until the
-- value has been still for 250 ms. S.pending shows the new value in the UI meanwhile. Nothing is written per frame.
local pending, order = {}, {}
S.pending = {}
S.DEBOUNCE = 0.25

function S.later(id, value, commit)
  if not pending[id] then order[#order + 1] = id end
  pending[id] = { value = value, commit = commit, t = os.preciseClock() }
  S.pending[id] = value
end

function S.flush(force)
  if #order == 0 then return end
  local now = os.preciseClock()
  local keep = {}
  for _, id in ipairs(order) do
    local p = pending[id]
    if p and (force or now - p.t >= S.DEBOUNCE) then
      pending[id], S.pending[id] = nil, nil
      pcall(p.commit, p.value)
    elseif p then keep[#keep + 1] = id end
  end
  order = keep
end

function S.setLater(src, section, key, value)
  S.later(src .. '/' .. section .. '/' .. key, value, function (v) S.set(src, section, key, v) end)
end

-- ---------------------------------------------------------------------------------------------- folders and lists
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

function S.weatherStyles() return foldersWith(ac.getFolder(ac.FolderID.ExtRoot) .. '/weather', 'manifest.ini') end

function S.appInstalled(folder) return io.dirExists(ac.getFolder(ac.FolderID.ACAppsLua) .. '/' .. folder) end

function S.manifestVersion(path)
  local text = io.load(path)
  local v = text and text:match('VERSION%s*=%s*([^\r\n;]+)')
  return v and trim(v) or nil
end

-- Opens another Lua app's window (Pure Config, Pure Planner, Sol Planner...).
function S.openApp(folder, windowId)
  return pcall(function ()
    local w = ac.accessAppWindow('IMGUI_LUA_' .. folder .. '_' .. windowId)
    if w then w:setVisible(true) else ac.setAppWindowVisible(folder, '?', true) end
  end)
end

return S
