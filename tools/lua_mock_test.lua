-- Runs Pitwall under LuaJIT with a stubbed CSP API (no Assetto Corsa needed). It checks:
--   1. the schema parser on every format CSP uses (bool, ranges with units/round/perc, quoted / "for" / "or" enums);
--   2. every shader pass: textures and values bound from Lua match the shader's `// @textures` / `// @values` header;
--   3. the pass graph for each effect toggle, bypass (draws nothing) and the other-grading-app rule;
--   4. every page, with every control on it clicked: no errors, and each write lands in the right place
--      (CSP module config, video.ini, audio, weather time, Pure style options) — sliders only after they settle.
-- usage (from the repo root): luajit tools/lua_mock_test.lua

package.path = 'app/Pitwall/?.lua;' .. package.path

-- ---------------------------------------------------------------------------------------------- vectors
local V2, V3, V4, RGBM = {}, {}, {}, {}
for _, m in ipairs({ V2, V3, V4, RGBM }) do m.__index = m end
V2.__add = function (a, b) return vec2(a.x + b.x, a.y + b.y) end
V2.__sub = function (a, b) return vec2(a.x - b.x, a.y - b.y) end
local function isV2(x) return getmetatable(x) == V2 end
local function isV3(x) return getmetatable(x) == V3 end
function vec2(x, y) return setmetatable({ x = x or 0, y = y or 0 }, V2) end
function vec3(x, y, z) return setmetatable({ x = x or 0, y = y or 0, z = z or 0 }, V3) end
function vec4(x, y, z, w) return setmetatable({ x = x or 0, y = y or 0, z = z or 0, w = w or 0 }, V4) end
function rgbm(r, g, b, m) return setmetatable({ r = r, g = g, b = b, mult = m }, RGBM) end

-- ---------------------------------------------------------------------------------------------- fake CSP world
local now = 0
local intervals, timeouts, buttons, storages = {}, {}, {}, {}
local hud = nil
local log = { updates = {}, finals = {}, errors = {}, texts = {}, writes = {}, calls = {} }
local function fail(msg) error(msg, 0) end
local function record(kind, ...) log.writes[#log.writes + 1] = { kind = kind, args = { ... } } end
local function wrote(kind, a, b, c)
  for _, w in ipairs(log.writes) do
    if w.kind == kind and (a == nil or w.args[1] == a) and (b == nil or w.args[2] == b) and (c == nil or w.args[3] == c) then return w end
  end
end

function setInterval(fn) intervals[#intervals + 1] = fn end
function setTimeout(fn) timeouts[#timeouts + 1] = fn end
JSON = { stringify = function () return '{}' end, parse = function () return {} end }
math.applyLag = function (v, t, lag) return t + (v - t) * lag end
os.preciseClock = function () return now end

render = {
  TextureFormat = { R16G16B16A16 = { Float = 10 } }, AntialiasingMode = { None = 0 },
  BlendMode = { Opaque = 0, AlphaBlend = 1 },
  projectPoint = function () return vec2(0.5, 0.3) end,
}

-- Synthetic schema files in CSP's format (every syntax variant the parser has to handle).
local SCHEMA = {
  graphics_adjustments = [[
[FSR]
ACTIVE=0 ; Active; 1 or 0; not available with IS_LIVE__
OLD_IMPLEMENTATION=0 ; Method; "AMD FSR (v1.0.2, any GPU)" is 0, __separator__, "NVIDIA DLSS (v310, requires NVIDIA GPU, ⏬29.4 MB)" is 3, "AMD FSR3/4 (v3.1.5, any GPU)" is 12
QUALITY_DLSS=0.58 ; Quality; "Custom (Any%)" is -1, "DLAA (100%)" is 1, "Quality (67%)" is 0.6667, "Balanced (58%)" is 0.58
SHARPEN_DLSS=0 ; Sharpness; from 0 to 1, perc.; visible with OLD_IMPLEMENTATION=3
QUALITY_FSR34=0.58 ; Quality; "Quality (67%)" is 0.6667, "Balanced (58%)" is 0.58
SHARPEN_FSR34=0.5 ; Sharpness; from 0 to 1, perc.
QUALITY2=0.77 ; Quality; "Best Quality (87%)" is 0.87, "Ultra Quality (77%)" is 0.77
SHARPEN2=0.5 ; Sharpness; from 0 to 1, perc.
[ANTIALIASING]
MODE=CMAA ;; DISABLED, Original is DEFAULT, __separator__, “CMAA 2.0” is CMAA, “FXAA 3.11” is FXAA3
QUALITY=HIGH ;; MEDIUM, HIGH or ULTRA; visible with MODE:CMAA
[RENDER_SCALE]
SCALE=1 ; Density; from 0.1 to 1, perc.
[LODS]
CARS_DISTANCE_MULT=1 ; Multiplier for car LODs; from 0.2 to 3.2, perc
TRACK_DISTANCE_MULT=1 ; Multiplier for track LODs; from 0.2 to 3.2, perc
TREES_DISTANCE_MULT=1 ; Multiplier for trees LODs; from 0.2 to 3.2, perc
HIDE_DISTANT_DRIVERS=1 ; Hide drivers for distant cars; 1 or 0
COCKPIT_LR_FIX=1 ; Force low-res cockpits; 1 or 0
[SCRIPTABLE_FILTER]
ENABLED=0 ; Active; 1 or 0
IMPLEMENTATION=tunnel ; Filter script; look for filter.lua in extension/lua/pp-filters; only with ENABLED
[DEV]
SECRET=1 ; hidden
]],
  extra_fx = [[
[BASIC]
ENABLED=0 ; Active (set to 0 to disable Extra FX); 1 or 0
[TAA]
ENABLED=1 ; Active; 1 or 0
EXTRA_SHARPEN_PASS=0.5 ; Extra sharpness; from 0 to 1, perc.
[MOTION_BLUR]
ENABLED=0 ; Active; 1 or 0
MULT=0.5 ; Amount of blur; from 0 to 1, perc.
[SSLR]
ENABLED=1 ; Active; 1 or 0
[ASSAO]
ENABLED=0 ; Active; 1 or 0
[HBAO]
ENABLED=0 ; Active; 1 or 0
[SSAO]
ENABLED2=0 ; Active; 1 or 0
[SS_LIGHTING]
ENABLED=1 ; Active; 1 or 0
[SSGI]
ENABLED2=0 ; Active; 1 or 0
[VOLUMETRIC_LIGHTS]
ENABLED=1 ; Active; 1 or 0
INTENSITY_MULT=1.5 ; Luminocity; from 0 to 2, perc.
[FOG_BLUR]
ENABLED=1 ; Active; 1 or 0
]],
  smart_shadows = "[BASIC]\nAUTOMATIC_SPLITS_DISTANCE=200 ; Shadows distance; from 50 m to 400, round to 10; visible with AUTOMATIC_SPLITS\n",
  lighting_fx = "[PERFORMANCE]\nCARS_WITH_LIGHTS=10 ; Cars casting lights; from 0 car(s) to 50, round\n[SHADOWS]\nENABLED=0 ; Active; 1 or 0\nCARS_SHADOWS=2 ; Cars with shadows; from 0 to 5, round to 1\n",
  reflections_fx = "[MAIN_CUBEMAP]\nRESOLUTION2=512 ; Main resolution; \"256×256\" is 256, \"512×512 (recommended)\" is 512, \"1024×1024\" is 1024\n[LOCAL_CUBEMAPS_CARS2]\nENABLED=1 ; Enable; 1 or 0\n",
  particles_fx = "[SMOKE]\nENABLED=1 ; Active; 1 or 0\nLONG_LASTING_SMOKE=1 ; Long-lasting smoke; 1 or 0\n[SPARKS]\nENABLED=1 ; Active; 1 or 0\n[AC_PARTICLES]\nREWORKED_HEAT_SHIMMER=1 ; Updated heat shimmer; 1 or 0\n",
  grass_fx = "[BASIC]\nQUALITY=2 ; Quality; 0 for Very low, 1 for Low, 2 for Medium, 3 for High, 4 for Very high\n[RENDERING]\nCAST_SHADOWS=0 ; Cast shadows when possible; 1 or 0\n",
  rain_fx = "[SCREEN_DROPS]\nENABLED=1 ; Active; 1 or 0\nINTENSITY_MULT=1 ; Intensity multiplier; from 0 to 2, perc.\n[VISUAL_TWEAKS]\nRAIN_MAPS_QUALITY=1 ; Rain maps quality; 0 for High, 1 for Medium, 2 for Low\n",
  weather_fx = "[BASIC]\nENABLED=1 ; Active; 1 or 0\nIMPLEMENTATION=base ; Style\n[MISCELLANEOUS]\nFORCE_HEADLIGHTS=0 ; Force headlights; 1 or 0\nSWITCH_HEADLIGHTS_WITH_AI=1 ; Switch headlights; 1 or 0\nSWITCH_WIPERS_WITH_AI=1 ; Switch wipers; 1 or 0\nUSE_TRACK_SEASONAL_ADJUSTMENTS=1 ; Seasons; 1 or 0\n[PERFORMANCE]\nEXTRA_CLOUDS_FIDELITY=1 ; Extra clouds; 1 or 0\nDETAILED_CLOUD_SHADOWS=1 ; Cloud shadows; 1 or 0\nHIGH_QUALITY_STARS=1 ; Stars; 1 or 0\n[PP_TWEAKS]\nFULL_RESOLUTION=1 ; Full resolution; 1 or 0\n",
}

-- In-memory INI files with CSP's INIConfig interface.
local files = {
  ['csp:weather_fx'] = { BASIC = { IMPLEMENTATION = 'pure', ENABLED = 1 } },
  ['csp:graphics_adjustments'] = { FSR = { ACTIVE = 1, OLD_IMPLEMENTATION = 3 }, SCRIPTABLE_FILTER = { IMPLEMENTATION = 'tunnel' } },
  video = { POST_PROCESS = { FILTER = 'Dream Realism 7.4', ENABLED = 1 } },
}
local function iniFor(name)
  files[name] = files[name] or {}
  local data = files[name]
  return {
    get = function (_, s, k, d)
      local v = data[s] and data[s][k]
      if v == nil then return d end
      if type(d) == 'number' then return tonumber(v) or d end
      return v
    end,
    set = function (_, s, k, v) data[s] = data[s] or {}; data[s][k] = v end,
    setAndSave = function (_, s, k, v) data[s] = data[s] or {}; data[s][k] = v; record(name, s, k, v); return true end,
    save = function () record(name .. ':save') end,
  }
end

local volumes = { main = 0.8, engine = 0.7, transmission = 0.5, tyres = 0.6, surfaces = 0.6, dirt = 0.5, wind = 0.4,
  opponents = 0.5, carComponents = 0.5, track = 0.5, weather = 0.5, rain = 0.5, wipers = 0.5 }

local SIM = {
  windowSize = vec2(1920, 1080), cameraClipNear = 0.1, cameraClipFar = 5000, isVRMode = false, isHDR = false,
  upscaleAppliedFactor = 0.58, isFSRActive = false, isTAAActive = true, isOnlineRace = false, isReplayActive = false,
  lightDirection = vec3(0, 0.8, 0.6), cameraLook = vec3(0, 0.3, 0.95), cameraPosition = vec3(0, 2, 0),
  weatherType = 15, timeHours = 13, timeMinutes = 5, timeTotalSeconds = 47100, ambientTemperature = 24, roadTemperature = 31,
  windSpeedKmh = 9, windDirectionDeg = 220, rainIntensity = 0, rainWetness = 0, firstPersonCameraFOV = 56,
}

local function readHeader(code)
  local h = {}
  for key, rest in code:gmatch('// @(%w+)[ \t]*([^\n]*)') do h[key] = rest end
  return h
end
local TYPES = { float = 'number', float2 = 'vec2', float3 = 'vec3', float4 = 'rgbm' }
local function kind(x)
  if type(x) == 'number' then return 'number' elseif isV2(x) then return 'vec2' elseif isV3(x) then return 'vec3'
  elseif getmetatable(x) == RGBM then return 'rgbm' end
  return type(x)
end
local function checkPass(p, where)
  assert(type(p.shader) == 'string' and p.shader:find('float4 main%(PS_IN pin%)'), where .. ': no shader main()')
  local h = readHeader(p.shader)
  local wantTex, wantVal = {}, {}
  for t in (h.textures or ''):gmatch('%S+') do wantTex[t] = true end
  for n, ty in (h.values or ''):gmatch('(%S+):(%S+)') do wantVal[n] = ty end
  for t in pairs(wantTex) do if p.textures[t] == nil or p.textures[t] == false then fail(where .. ': texture ' .. t .. ' not bound') end end
  for t in pairs(p.textures) do if not wantTex[t] then fail(where .. ': texture ' .. t .. ' not in the shader header') end end
  for n, ty in pairs(wantVal) do
    if p.values[n] == nil then fail(where .. ': value ' .. n .. ' missing') end
    if kind(p.values[n]) ~= TYPES[ty] then fail(where .. ': value ' .. n .. ' is ' .. kind(p.values[n]) .. ', shader wants ' .. ty) end
  end
  for n in pairs(p.values) do if not wantVal[n] then fail(where .. ': value ' .. n .. ' not in the shader header') end end
end
local function shaderName(code)
  -- first line of the comment block right above the shader's `// @` header (common.hlsl may be prepended)
  local before = code:sub(1, (code:find('\n// @', 1, true) or 0))
  local lines = {}
  for l in before:gmatch('[^\n]*') do lines[#lines + 1] = l end
  local first = nil
  for i = #lines, 1, -1 do
    if lines[i]:match('^//') then first = lines[i] elseif lines[i] ~= '' then break end
  end
  return first or '?'
end

-- UI: clicks are routed by widget id so a test can "click everything on one page".
local clickFilter = function () return false end
local lastId = ''
ui = setmetatable({
  Icons = setmetatable({}, { __index = function (_, k) return k end }),
  Alignment = { Start = -1, Center = 0, End = 1 }, KeyIndex = { P = 80, O = 79 },
  windowSize = function () return vec2(540, 900) end, windowPos = function () return vec2(100, 80) end,
  mouseLocalPos = function () return vec2(300, 300) end, mouseDelta = function () return vec2() end,
  mouseWheel = function () return 0 end, windowHovered = function () return false end,
  measureDWriteText = function (t, size) return vec2(#tostring(t) * (size or 13) * 0.5, (size or 13) * 1.3) end,
  invisibleButton = function (id) lastId = id; return clickFilter(id) end,
  itemHovered = function () return clickFilter(lastId) end,
  itemActive = function () return clickFilter(lastId) end,
  dwriteDrawText = function (t) log.texts[#log.texts + 1] = t end,
  dwriteDrawTextClipped = function (t) log.texts[#log.texts + 1] = t end,
  onExclusiveHUD = function (cb) hud = cb end,
  ExtraCanvas = function (size)
    local c = { sz = size }
    function c:size() return self.sz end
    function c:dispose() end
    function c:updateWithShader(p)
      checkPass(p, 'pass ' .. shaderName(p.shader))
      log.updates[#log.updates + 1] = shaderName(p.shader)
      return true
    end
    return c
  end,
  renderShader = function (p)
    checkPass(p, 'renderShader ' .. shaderName(p.shader))
    if p.textures.txPLBase then
      local copy = {}
      for k, v in pairs(p.values) do copy[k] = v end
      log.finals[#log.finals + 1] = { values = copy, base = p.textures.txPLBase }
    end
    return true
  end,
}, { __index = function () return function () end end })

local FOLDERS = { [1029] = 'app', [17] = 'X/extension/config', [16] = 'X/extension', [5] = 'X/cfg', [12] = 'X/ppfilters', [25] = 'X/cfg/extension/state' }
ac = {
  FolderID = { ACAppsLua = 1029, ExtCfgSys = 17, ExtRoot = 16, Cfg = 5, PPFilters = 12, ExtCfgState = 25 },
  CSPModuleID = { GraphicsAdjustments = 'graphics_adjustments' },
  getFolder = function (id) return FOLDERS[id] end,
  storage = function (t) storages[#storages + 1] = t; return t end,
  ControlButton = function (id) local b = {}; function b:onPressed(f) buttons[id] = f end; return b end,
  accessAppWindow = function (name)
    if name == 'IMGUI_LUA_Photolap_main' then return nil end
    return { setVisible = function () record('window', name) end, visible = function () return true end,
      position = function () return vec2() end, move = function () end }
  end,
  setAppWindowVisible = function (id) record('window', id) end,
  getSim = function () return SIM end,
  getUI = function () return { windowSize = vec2(1920, 1080), dt = 0.016 } end,
  INIConfig = {
    cspModule = function (id) return iniFor('csp:' .. id) end,
    videoConfig = function () return iniFor('video') end,
    load = function (path) return iniFor('file:' .. path) end,
  },
  isModuleActive = function () return true end,
  getAppWindows = function () return ac._windows or {} end,
  getPerformanceCPUAndGPUTime = function () return 5.0, 8.0 end,
  getPpFilter = function () return 'Dream Realism 7.4.ini' end,
  getAudioVolume = function (k) return volumes[k] or -1 end,
  setAudioVolume = function (k, v, car, save) volumes[k] = v; record('audio', k, save) end,
  setWeatherTimeOffset = function (s) record('timeOffset', s) end,
  setWeatherTimeMultiplier = function (m) record('timeSpeed', m) end,
  setFirstPersonCameraFOV = function (v) record('fov', v) end,
  resetFirstPersonCameraFOV = function () record('fovReset') end,
  onRelease = function () end, onCSPConfigChanged = function () end, onFileChanged = function () end,
  error = function (...) log.errors[#log.errors + 1] = table.concat({ ... }, ' ') end,
}
local DIRS = {
  ['X/ppfilters'] = { 'default.ini', 'Dream Realism 7.4.ini', 'natural.ini' },
  ['X/extension/lua/pp-filters'] = { 'pure', 'tunnel', 'vhs' },
  ['X/extension/weather'] = { 'base', 'pure', 'Pure LCS', 'sol' },
}
io.scanDir = function (dir) return DIRS[dir] or {} end
io.fileExists = function (p) return p:find('X/extension/', 1, true) ~= nil end
io.dirExists = function (p) return p:find('weather/pure', 1, true) ~= nil or p:find('app/Pure', 1, true) ~= nil end
local realLoad = function (p) local f = io.open(p, 'rb'); if not f then return nil end; local d = f:read('*a'); f:close(); return d end
io.load = function (p)
  local mod = p:match('^X/extension/config/(.+)%.ini$')
  if mod then return SCHEMA[mod] end
  if p == 'X/extension/weather/pure/manifest.ini' then return '[ABOUT]\nVERSION = 2.71\n' end
  return realLoad(p)
end

-- ---------------------------------------------------------------------------------------------- 1. schema parser
local S = require('src/settings')
do
  local sc = S.parseSchema(SCHEMA.graphics_adjustments)
  assert(sc.FSR.ACTIVE.kind == 'bool', 'bool')
  local m = sc.FSR.OLD_IMPLEMENTATION
  assert(m.kind == 'enum' and #m.options == 3 and m.options[2].value == 3 and m.options[1].label:find('AMD FSR', 1, true), 'quoted enum with commas inside')
  assert(sc.FSR.SHARPEN_DLSS.kind == 'range' and sc.FSR.SHARPEN_DLSS.perc and sc.FSR.SHARPEN_DLSS.max == 1, 'perc range')
  local aa = sc.ANTIALIASING.MODE
  assert(aa.kind == 'enum' and aa.options[1].value == 'DISABLED' and aa.options[2].value == 'DEFAULT' and aa.options[3].label == 'CMAA 2.0', 'bare + curly-quoted enum')
  local q = sc.ANTIALIASING.QUALITY
  assert(q.kind == 'enum' and #q.options == 3 and q.options[3].value == 'ULTRA', '"X, Y or Z" enum')
  assert(sc.DEV == nil or sc.DEV.SECRET == nil, 'hidden keys are skipped')
  local ss = S.parseSchema(SCHEMA.smart_shadows).BASIC.AUTOMATIC_SPLITS_DISTANCE
  assert(ss.kind == 'range' and ss.min == 50 and ss.max == 400 and ss.round == 10 and ss.unit == 'm', 'range with unit and rounding')
  local cl = S.parseSchema(SCHEMA.lighting_fx).PERFORMANCE.CARS_WITH_LIGHTS
  assert(cl.kind == 'range' and cl.max == 50 and cl.round == 1, 'range with "car(s)" unit and bare round')
  local cs = S.parseSchema(SCHEMA.lighting_fx).SHADOWS.CARS_SHADOWS
  assert(cs.kind == 'range' and cs.min == 0 and cs.max == 5 and cs.round == 1, '"from 0 to 5, round to 1" (no unit)')
  local rs = S.parseSchema(SCHEMA.graphics_adjustments).RENDER_SCALE.SCALE
  assert(rs.min == 0.1 and rs.max == 1 and rs.perc, '"from 0.1 to 1" keeps the decimal minimum')
  local ld = S.parseSchema(SCHEMA.graphics_adjustments).LODS.CARS_DISTANCE_MULT
  assert(ld.min == 0.2 and ld.max == 3.2, '"from 0.2 to 3.2, perc"')
  local gq = S.parseSchema(SCHEMA.grass_fx).BASIC.QUALITY
  assert(gq.kind == 'enum' and #gq.options == 5 and gq.options[5].label == 'Very high', '"0 for X" enum')
  print('schema parser: OK')
end

-- ---------------------------------------------------------------------------------------------- load the app
script = {}
dofile('app/Pitwall/Pitwall.lua')
assert(type(script.windowMain) == 'function', 'windowMain not defined')
assert(type(hud) == 'function', 'app did not register ui.onExclusiveHUD')
local store = storages[1]
assert(store and store.enabled ~= nil and store.page, 'main storage not found')

local function frame()
  log.updates, log.finals = {}, {}
  hud('game')
  assert(#log.errors == 0, 'app reported: ' .. table.concat(log.errors, '; '))
  return log.updates, log.finals[#log.finals]
end
local function has(list, pattern) for _, n in ipairs(list) do if n:find(pattern) then return true end end return false end

-- ---------------------------------------------------------------------------------------------- 2-3. passes
local u, f = frame()
assert(f, 'engaged frame drew nothing')
for _, want in ipairs({ 'Neural, layer 0', 'Neural, layer 3', 'Bloom prefilter', '1x1 probe', 'Sun shafts, step 2', 'Contact ambient occlusion', 'Clarity source' }) do
  assert(has(u, want), 'missing pass: ' .. want)
end
assert(not has(u, 'Lens flare'), 'flare is off by default')
assert(f.values.gPLShaftsOn == 1 and f.values.gPLAOOn == 1 and f.values.gPLDofOn == 0, 'add-on flags')
print('passes with defaults: ' .. #u .. ' + final')

store.flare = true; u, f = frame(); assert(has(u, 'Lens flare') and f.values.gPLFlareOn == 1, 'flare on'); store.flare = false
store.dof = 2; u, f = frame(); assert(has(u, 'Depth of field source') and f.values.gPLDofOn == 1, 'dof always'); store.dof = 0
store.dof = 1; u, f = frame(); assert(f.values.gPLDofOn == 0, 'dof replays-only stays off while driving')
SIM.isReplayActive = true; u, f = frame(); assert(f.values.gPLDofOn == 1, 'dof on in replays'); SIM.isReplayActive = false; store.dof = 0
store.neural = false; u, f = frame(); assert(f.base == 'dynamic::screen' and not has(u, 'Neural'), 'neural off'); store.neural = true
store.light = false; u, f = frame(); assert(f.values.gPLLight == 0 and not has(u, 'Bloom') and not has(u, 'Sun shafts'), 'light off'); store.light = true
store.detail = false; u, f = frame(); assert(f.values.gPLDetail == 0 and not has(u, 'Clarity'), 'detail off'); store.detail = true
store.ao = false; u, f = frame(); assert(f.values.gPLAOOn == 0 and not has(u, 'Contact'), 'ao off'); store.ao = true
store.split = true; u, f = frame(); assert(f.values.gPLSplit == 1, 'split'); store.split = false
store.enabled = false; u, f = frame(); assert(#u == 0 and f == nil, 'bypass must draw nothing')
buttons.__APP_PITWALL_MASTER(); u, f = frame(); assert(store.enabled and f, 'Alt+O re-engages')
ac._windows = { { name = 'IMGUI_LUA_DreamRealism74_dpm_main' } }
for _, fn in ipairs(intervals) do fn() end
u, f = frame(); assert(f.values.PL_FilmicStrength == 0 and f.values.PL_HighlightRecover == 0, 'other grading app: no re-tonemap')
ac._windows = { { name = 'IMGUI_LUA_Dream_DriverSwap_main' } }
for _, fn in ipairs(intervals) do fn() end
u, f = frame(); assert(f.values.PL_FilmicStrength > 0, 'unrelated Dream_* app is not a grading app')
print('pass graph: OK')

-- ---------------------------------------------------------------------------------------------- 4. pages
local function drawPage(page, clickAll)
  store.page = page
  log.texts = {}
  clickFilter = clickAll and function (id) return id:sub(1, #page + 1) == page .. '_' end or function () return false end
  script.windowMain(0.016)
  script.windowMain(0.016)
  clickFilter = function () return false end
  local all = table.concat(log.texts, '\n')
  assert(not all:find('ERROR', 1, true), page .. ': page builder failed:\n' .. all)
  assert(#log.errors == 0, page .. ': ' .. table.concat(log.errors, '; '))
  return all
end

local P = require('src/pages')
for _, item in ipairs(P.nav) do drawPage(item.id, false) end
for _, tab in ipairs({ 'upscale', 'light', 'effects', 'detail' }) do store.gfxTab = tab; drawPage('graphics', false) end
local look = drawPage('look', false)
assert(look:find('running', 1, true) and look:find('DLSS', 1, true), 'status card: shaders running + upscaler')
local realism = drawPage('realism', false)
assert(not realism:find('DLSS 5', 1, true), 'neural must not be called DLSS 5')

-- click every control on every page; then let debounced writes settle
log.writes = {}
for _, item in ipairs(P.nav) do
  if item.id == 'graphics' then
    for _, tab in ipairs({ 'upscale', 'light', 'effects', 'detail' }) do store.gfxTab = tab; drawPage('graphics', true) end
  elseif item.id == 'effects' then
    for _, tab in ipairs({ 'light', 'lens' }) do store.fxTab = tab; drawPage('effects', true) end
  else drawPage(item.id, true) end
end
now = now + 1
S.flush()
for _, fn in ipairs(timeouts) do fn() end

assert(wrote('csp:extra_fx', 'SSLR', 'ENABLED'), 'graphics: SSLR toggle wrote extra_fx')
assert(wrote('csp:graphics_adjustments', 'FSR', 'ACTIVE'), 'graphics: upscaler toggle wrote graphics_adjustments')
assert(wrote('csp:smart_shadows', 'BASIC', 'AUTOMATIC_SPLITS_DISTANCE'), 'graphics: shadow slider saved after settling')
assert(wrote('csp:grass_fx', 'BASIC', 'QUALITY'), 'graphics: grass quality')
assert(wrote('csp:extra_fx', 'ASSAO', 'ENABLED'), 'graphics: AO mode writes all three AO switches')
assert(wrote('csp:weather_fx', 'MISCELLANEOUS', 'FORCE_HEADLIGHTS'), 'weather: WeatherFX toggle')
assert(wrote('csp:rain_fx', 'SCREEN_DROPS', 'ENABLED'), 'weather: rain toggle')
assert(wrote('timeOffset') and wrote('timeSpeed'), 'weather: time controls (offline)')
assert(wrote('video', 'POST_PROCESS', 'FILTER'), 'filters: AC filter written to video.ini')
assert(wrote('video', 'POST_PROCESS', 'GLARE'), 'filters: glare level')
assert(wrote('csp:graphics_adjustments', 'SCRIPTABLE_FILTER', 'IMPLEMENTATION'), 'filters: CSP Lua filter script')
assert(wrote('video', 'ASSETTOCORSA', 'WORLD_DETAIL') and wrote('video', 'MIRROR', 'HQ'), 'video: video.ini settings')
assert(wrote('fov') and wrote('fovReset'), 'video: field of view live')
assert(wrote('audio', 'engine', false) and wrote('audio', 'engine', true), 'audio: live while dragging, saved once settled')
assert(wrote('csp:weather_fx', 'BASIC', 'IMPLEMENTATION'), 'pure: style switch / reload')
assert(wrote('file:X/cfg/extension/state/lua/wfx_impl/pure__settings.ini:save'), 'pure: style option saved')
assert(wrote('window', 'IMGUI_LUA_PureConfig_main_pure_config'), 'pure: opens Pure Config')
print('pages: OK (' .. #log.writes .. ' writes across all pages)')

-- online: time controls are locked
SIM.isOnlineRace = true
log.writes = {}
drawPage('weather', true)
assert(not wrote('timeOffset') and not wrote('timeSpeed'), 'online: no time changes')
SIM.isOnlineRace = false

print('lua mock test: OK')
