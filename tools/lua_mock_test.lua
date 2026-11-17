-- Runs Lumicorsa under LuaJIT against a stubbed CSP (no Assetto Corsa needed). Config files live in memory keyed by
-- path, so set() writes and the self-test's from-disk readbacks go through the same "files". It checks:
--   1. the CSP schema parser on every syntax CSP uses;
--   2. every shader pass: bound textures/values match the shader's `// @textures` / `// @values` header;
--   3. every tab draws in Basic, Advanced and Expert, and every control on it can be clicked without an error;
--   4. the built-in self-test runs over every control and reports no FAIL (only PASS or LOCKED);
--   5. debounced writes, palette search, quick ring, HUD in km/h and mph, proof capture and a short online soak.
-- usage (from the repo root): luajit tools/lua_mock_test.lua

package.path = 'app/Lumicorsa/?.lua;' .. package.path

-- ---------------------------------------------------------------------------------------------- vectors
local V2, V3, RGBM = {}, {}, {}
V2.__index, V3.__index, RGBM.__index = V2, V3, RGBM
function vec2(x, y) return setmetatable({ x = x or 0, y = y or 0 }, V2) end
function vec3(x, y, z) return setmetatable({ x = x or 0, y = y or 0, z = z or 0 }, V3) end
function vec4(x, y, z, w) return { x = x or 0, y = y or 0, z = z or 0, w = w or 0 } end
function rgbm(r, g, b, m) return setmetatable({ r = r, g = g, b = b, mult = m }, RGBM) end
local function num(a) return type(a) == 'number' end
V2.__add = function (a, b) return vec2(a.x + b.x, a.y + b.y) end
V2.__sub = function (a, b) return vec2(a.x - b.x, a.y - b.y) end
V2.__mul = function (a, b) if num(a) then a, b = b, a end; if num(b) then return vec2(a.x * b, a.y * b) end; return vec2(a.x * b.x, a.y * b.y) end
V2.__div = function (a, b) return vec2(a.x / b, a.y / b) end
V2.__unm = function (a) return vec2(-a.x, -a.y) end
V3.__mul = function (a, b) if num(a) then a, b = b, a end; return vec3(a.x * b, a.y * b, a.z * b) end
local function kind(x)
  if type(x) == 'number' then return 'number' end
  local mt = getmetatable(x)
  if mt == V2 then return 'vec2' elseif mt == V3 then return 'vec3' elseif mt == RGBM then return 'rgbm' end
  return type(x)
end

-- ---------------------------------------------------------------------------------------------- fake CSP world
local now = 0
local timeouts, intervals, buttons, storages = {}, {}, {}, {}
local hud, log = nil, { errors = {}, passes = {}, writes = 0, shots = 0, texts = {} }
local function fail(m) error(m, 0) end

function setInterval(fn) intervals[#intervals + 1] = fn end
function setTimeout(fn, d) timeouts[#timeouts + 1] = fn end
JSON = {
  stringify = function (t)
    local function enc(v)
      if type(v) == 'table' then
        local parts = {}
        for k, x in pairs(v) do parts[#parts + 1] = string.format('%q:%s', tostring(k), enc(x)) end
        return '{' .. table.concat(parts, ',') .. '}'
      elseif type(v) == 'string' then return string.format('%q', v)
      else return tostring(v) end
    end
    return enc(t)
  end,
  parse = function (s)   -- minimal JSON reader for what the app writes (objects, strings, numbers, booleans)
    if s == nil or s == '' then error('empty') end
    local lua = s:gsub('"([^"]-)":', '["%1"]='):gsub('%[', '{'):gsub('%]', '}')
    lua = lua:gsub('{"([^"]-)"}=', '["%1"]=')
    local f = load('return ' .. lua)
    if not f then error('bad json') end
    return f()
  end,
}
os.preciseClock = function () return now end

-- in-memory INI files keyed by path
local FILES = {}
local function iniAt(path)
  FILES[path] = FILES[path] or {}
  local data = FILES[path]
  return {
    get = function (_, s, k, d)
      local v = data[s] and data[s][k]
      if v == nil then return d end
      if type(d) == 'number' then return tonumber(v) or d end
      return v
    end,
    set = function (_, s, k, v) data[s] = data[s] or {}; data[s][k] = v end,
    setAndSave = function (_, s, k, v) data[s] = data[s] or {}; data[s][k] = v; log.writes = log.writes + 1; return true end,
    save = function () log.writes = log.writes + 1 end,
  }
end

local SCHEMA = {
  graphics_adjustments = '[FSR]\nACTIVE=0 ; Active; 1 or 0\nOLD_IMPLEMENTATION=0 ; Method; "AMD FSR (v1.0.2, any GPU)" is 0, __separator__, "NVIDIA DLSS (v310, requires NVIDIA GPU)" is 3, "AMD FSR3/4 (v3.1.5)" is 12\n' ..
    'QUALITY_DLSS=0.58 ; Quality; "DLAA (100%)" is 1, "Quality (67%)" is 0.6667, "Balanced (58%)" is 0.58\nSHARPEN_DLSS=0 ; Sharpness; from 0 to 1, perc.\n' ..
    '[RENDER_SCALE]\nSCALE=1 ; Density; from 0.1 to 1, perc.\n[LODS]\nTRACK_DISTANCE_MULT=1 ; Track; from 0.2 to 3.2, perc\nCARS_DISTANCE_MULT=1 ; Cars; from 0.2 to 3.2, perc\n' ..
    '[ANTIALIASING]\nMODE=CMAA ;; DISABLED, Original is DEFAULT, “CMAA 2.0” is CMAA\nQUALITY=HIGH ;; MEDIUM, HIGH or ULTRA\n',
  extra_fx = '[SSLR]\nENABLED=1 ; Active; 1 or 0\n[ASSAO]\nENABLED=0 ; Active; 1 or 0\n[HBAO]\nENABLED=0 ; Active; 1 or 0\n[SSAO]\nENABLED2=0 ; Active; 1 or 0\n' ..
    '[LIGHT_BOUNCE]\nENABLED=1 ; Tracks; 1 or 0\nCARS=1 ; Cars; 1 or 0\n[MOTION_BLUR]\nENABLED=0 ; Active; 1 or 0\nMULT=0.5 ; Amount; from 0 to 1, perc.\n',
  smart_shadows = '[BASIC]\nAUTOMATIC_SPLITS_DISTANCE=200 ; Distance; from 50 m to 400, round to 10\n',
  grass_fx = '[BASIC]\nQUALITY=2 ; Quality; 0 for Very low, 1 for Low, 2 for Medium, 3 for High, 4 for Very high\n',
  rain_fx = '[SCREEN_DROPS]\nENABLED=1 ; Active; 1 or 0\n',
  weather_fx = '[MISCELLANEOUS]\nSWITCH_WIPERS_WITH_AI=1 ; Wipers; 1 or 0\n[PERFORMANCE]\nEXTRA_CLOUDS_FIDELITY=1 ; Clouds; 1 or 0\nDETAILED_CLOUD_SHADOWS=1 ; Shadows; 1 or 0\nHIGH_QUALITY_STARS=1 ; Stars; 1 or 0\n',
  windscreen_fx = '[REFLECTION]\nENABLED=0 ; Active; 1 or 0\n',
  ffb_tweaks = '[CUSTOM_SOFT_LOCK]\nDAMPER=0 ; Damper; from 0 to 1, perc.\n[GYRO2]\nENABLED=0 ; Active; 1 or 0\n',
  nice_screenshots = '[ACCUMULATION_AA]\nRESOLUTION_MULTIPLIER=1 ;; From 1x to 4, round\n',
  lighting_fx = '[SHADOWS]\nCARS_SHADOWS=2 ; Cars; from 0 to 5, round to 1\n[PERFORMANCE]\nCARS_WITH_LIGHTS=10 ; Cars; from 0 car(s) to 50, round\n',
}

local FOLDER = { [1029] = 'app', [17] = 'X/extconfig', [18] = 'X/cfg/extension', [5] = 'X/cfg', [25] = 'X/cfg/extension/state',
  [16] = 'X/extension', [4] = 'X/root', [1] = 'X/docs', [12] = 'X/ppfilters' }

local SIM = {
  windowSize = vec2(1920, 1080), renderSize = vec2(1920, 1080), cameraClipNear = 0.1, cameraClipFar = 5000,
  isVRMode = false, isHDR = false, isOnlineRace = false, isReplayActive = false, upscaleAppliedFactor = 1, isFSRActive = false, isTAAActive = true,
  lightDirection = vec3(0, 0.8, 0.6), cameraLook = vec3(0, 0.3, 0.95), cameraUp = vec3(0, 1, 0), cameraSide = vec3(1, 0, 0),
  cameraPosition = vec3(0, 2, 0), cameraFOV = 56, cameraMode = 0, driveableCameraMode = 0,
  timeTotalSeconds = 47100, timeHours = 13, timeMinutes = 5, ambientTemperature = 24, rainIntensity = 0,
  firstPersonCameraFOV = 56, cpuOccupancy = 37,
}
local CAR = {
  speedKmh = 84, rpm = 5400, rpmLimiter = 8000, gear = 3, fuel = 30, maxFuel = 60, oilTemperature = 80, waterTemperature = 85,
  turningLeftLights = false, turningRightLights = false, turningLightsActivePhase = true, headlightsActive = true, highBeams = false,
  absInAction = false, tractionControlInAction = false, handbrake = 0, engineLifeLeft = 1000, gearboxDamage = 0, batteryVoltage = 12.6,
  distanceDrivenTotalKm = 13841.2, distanceDrivenSessionKm = 12.3, isEngineLimiterOn = false, ffbMultiplier = 1,
  absMode = 1, absModes = 3, tractionControlMode = 1, tractionControlModes = 4, wiperMode = 0, wiperModes = 3,
  position = vec3(0, 0.5, 0),
}
function CAR:id() return 'test_car' end

local WINDOWS = {}
local function win(name)
  WINDOWS[name] = WINDOWS[name] or { vis = true, pos = vec2(100, 60), size = vec2() }
  local w = WINDOWS[name]
  return {
    visible = function () return w.vis end, setVisible = function (_, v) w.vis = v end,
    position = function () return w.pos end, move = function (_, p) w.pos = p end, resize = function (_, s) w.size = s end,
  }
end

local volumes = { main = 0.8, engine = 0.9, transmission = 0.6, carComponents = 0.6, tyres = 0.6, surfaces = 0.7, opponents = 0.7, wind = 0.4, track = 0.5 }
local seat = { position = vec3(0, 1.0, 0.2), pitch = 0, yaw = 0 }
local timeScale = 1

-- shader header checks
local function header(code)
  local h = {}
  for key, rest in code:gmatch('// @(%w+)[ \t]*([^\n]*)') do h[key] = rest end
  return h
end
local TYPES = { float = 'number', float2 = 'vec2', float3 = 'vec3', float4 = 'rgbm' }
local function checkPass(p, where)
  assert(type(p.shader) == 'string' and p.shader:find('float4 main%(PS_IN pin%)'), where .. ': no main()')
  local h = header(p.shader)
  local wantT, wantV = {}, {}
  for t in (h.textures or ''):gmatch('%S+') do wantT[t] = true end
  for n, ty in (h.values or ''):gmatch('(%S+):(%S+)') do wantV[n] = ty end
  for t in pairs(wantT) do if p.textures[t] == nil or p.textures[t] == false then fail(where .. ': texture ' .. t .. ' not bound') end end
  for t in pairs(p.textures) do if not wantT[t] then fail(where .. ': texture ' .. t .. ' not in header') end end
  for n, ty in pairs(wantV) do
    if p.values[n] == nil then fail(where .. ': value ' .. n .. ' missing') end
    if kind(p.values[n]) ~= TYPES[ty] then fail(where .. ': value ' .. n .. ' is ' .. kind(p.values[n]) .. ', want ' .. ty) end
  end
  for n in pairs(p.values) do if not wantV[n] then fail(where .. ': value ' .. n .. ' not in header') end end
end

local clickFilter, lastId, mouseLocal = function () return false end, '', vec2(400, 300)
ui = setmetatable({
  KeyIndex = { P = 80, O = 79, H = 72, Q = 81, K = 75 }, Key = { Up = 1, Down = 2, Escape = 3, Enter = 4 },
  Alignment = { Start = -1, Center = 0, End = 1 }, MouseButton = { Left = 0, Right = 1 }, CornerFlags = { Top = 3 },
  StyleColor = { FrameBg = 7 }, InputTextFlags = { None = 0 },
  windowSize = function () return vec2(1480, 940) end, windowPos = function () return vec2(100, 60) end,
  mouseLocalPos = function () return mouseLocal end, mousePos = function () return vec2(960, 540) end, mouseDelta = function () return vec2(3, -2) end,
  mouseWheel = function () return 0 end, windowHovered = function () return false end,
  measureDWriteText = function (t, size) return vec2(#tostring(t) * (size or 13) * 0.55, (size or 13) * 1.25) end,
  invisibleButton = function (id) lastId = id; return clickFilter(id) end,
  itemHovered = function () return clickFilter(lastId) end, itemActive = function () return clickFilter(lastId) end,
  dwriteDrawText = function (t) log.texts[#log.texts + 1] = t end,
  inputText = function (_, s) return s, false, false end,
  keyPressed = function () return false end, mouseClicked = function () return false end,
  onExclusiveHUD = function (cb) hud = cb end,
  ExtraCanvas = function (size)
    local c = { sz = size }
    function c:size() return self.sz end
    function c:dispose() end
    function c:updateWithShader(p) checkPass(p, 'pass'); log.passes[#log.passes + 1] = p.shader:match('\n// @textures') and 1; return true end
    return c
  end,
  renderShader = function (p) checkPass(p, 'final'); return true end,
}, { __index = function () return function () end end })

render = { TextureFormat = { R16G16B16A16 = { Float = 10 } }, AntialiasingMode = { None = 0 }, BlendMode = { Opaque = 0 },
  projectPoint = function () return vec2(0.5, 0.3) end }

ac = {
  FolderID = { ACAppsLua = 1029, ExtCfgSys = 17, ExtCfgUser = 18, Cfg = 5, ExtCfgState = 25, ExtRoot = 16, Root = 4, Documents = 1, PPFilters = 12 },
  CameraMode = { Cockpit = 0, Car = 1, Drivable = 2, Track = 3, Helicopter = 4, Free = 6 }, DrivableCamera = { Chase = 0, Chase2 = 1 },
  ScreenshotFormat = { PNG = 3 },
  getFolder = function (id) return FOLDER[id] end,
  storage = function (t) storages[#storages + 1] = t; return t end,
  ControlButton = function (id) local b = { id = id, isDown = false }; function b:onPressed(f) buttons[id] = f end; function b:down() return self.isDown end; buttons[id .. '#obj'] = b; return b end,
  accessAppWindow = function (n) return win(n) end, setAppWindowVisible = function () end,
  getSim = function () return SIM end, getCar = function () return CAR end,
  getUI = function () return { windowSize = vec2(1920, 1080), dt = 1 / 60 } end,
  INIConfig = {
    cspModule = function (id) return iniAt('X/cfg/extension/' .. id .. '.ini') end,
    videoConfig = function () return iniAt('X/cfg/video.ini') end,
    controlsConfig = function () return iniAt('X/cfg/controls.ini') end,
    load = function (p) return iniAt(p) end,
  },
  onCSPConfigChanged = function () end, onFileChanged = function () end, onSessionStart = function () end, onRelease = function () end,
  getAppWindows = function () return {} end,
  getPerformanceCPUAndGPUTime = function () return 6, 7 end,
  getVRAMConsumption = function () return { budget = 12 * 1024 ^ 3, usage = 6 * 1024 ^ 3 } end,
  getServerName = function () return SIM.isOnlineRace and 'No Hesi | Test' or nil end,
  getAudioVolume = function (k) return volumes[k] or -1 end,
  setAudioVolume = function (k, v) volumes[k] = v end,
  setFFBMultiplier = function (v) CAR.ffbMultiplier = v end,
  setFirstPersonCameraFOV = function (v) SIM.firstPersonCameraFOV = v end,
  setWeatherTimeOffset = function (d) SIM.timeTotalSeconds = (SIM.timeTotalSeconds + d) % 86400 end,
  setWeatherTimeMultiplier = function (m) timeScale = m end, getConditionsTimeScale = function () return timeScale end,
  setABS = function (m) CAR.absMode = m end, setTractionControl = function (m) CAR.tractionControlMode = m end,
  setCurrentCamera = function (m) SIM.cameraMode = m end, setCurrentDrivableCamera = function (m) SIM.driveableCameraMode = m end,
  getCameraPositionRelativeToCar = function () return vec3(0, 1, -(_G.__chaseDist or 3.2)) end,
  applyLiveConfigEdit = function (name, data) local d = data:match('DISTANCE=([%d%.]+)'); if d then _G.__chaseDist = tonumber(d) end end,
  applyRenderingLimits = function () return { dispose = function () end } end,
  getOnboardCameraParams = function () return { position = vec3(seat.position.x, seat.position.y, seat.position.z), pitch = 0, yaw = 0 } end,
  getOnboardCameraDefaultParams = function () return { position = vec3(0, 1.0, 0.2), pitch = 0, yaw = 0 } end,
  setOnboardCameraParams = function (_, p) seat.position = p.position end,
  SeatParams = function (pos, pitch, yaw) return { position = pos, pitch = pitch, yaw = yaw } end,
  setWiperMode = function (m) CAR.wiperMode = m end, setHeadlights = function (v) CAR.headlightsActive = v end,
  makeScreenshot = function (path, fmt, cb) log.shots = log.shots + 1; if cb then cb(nil) end end,
  shutdownAssettoCorsa = function () end,
  error = function (...) log.errors[#log.errors + 1] = table.concat({ ... }, ' ') end,
}
web = { get = function (url, cb) cb(nil, { status = 200, body = 'href="downloads/ReShade_Setup_6.5.1_Addon.exe"' }) end }

local realIo = io
local SAVED = {}
io.load = function (p)
  local m = p:match('^X/extconfig/(.+)%.ini$'); if m then return SCHEMA[m] end
  if SAVED[p] then return SAVED[p] end
  local f = realIo.open(p, 'rb'); if not f then return nil end; local d = f:read('*a'); f:close(); return d
end
io.save = function (p, d) SAVED[p] = d; return true end
io.fileExists = function (p) return SAVED[p] ~= nil end
io.dirExists = function (p) return p:find('weather/pure', 1, true) ~= nil or p:find('PurePlanner', 1, true) ~= nil end
io.createDir = function () end
io.scanDir = function () return {} end
io.deleteFile = function (p) SAVED[p] = nil end
io.loadFromZip = function () return nil end

-- ---------------------------------------------------------------------------------------------- 1. schema parser
local C = require('backend/config')
do
  local sc = C.parseSchema(SCHEMA.graphics_adjustments)
  assert(sc.FSR.ACTIVE.kind == 'bool' and sc.FSR.OLD_IMPLEMENTATION.kind == 'enum' and #sc.FSR.OLD_IMPLEMENTATION.options == 3, 'enum with commas in quotes')
  assert(sc.RENDER_SCALE.SCALE.min == 0.1 and sc.LODS.TRACK_DISTANCE_MULT.min == 0.2, 'decimal minimums')
  assert(sc.ANTIALIASING.MODE.options[3].label == 'CMAA 2.0' and sc.ANTIALIASING.QUALITY.options[3].value == 'ULTRA', 'curly quotes / X or Y')
  local ls = C.parseSchema(SCHEMA.lighting_fx)
  assert(ls.SHADOWS.CARS_SHADOWS.max == 5 and ls.PERFORMANCE.CARS_WITH_LIGHTS.max == 50, 'round / unit ranges')
  assert(C.parseSchema(SCHEMA.smart_shadows).BASIC.AUTOMATIC_SPLITS_DISTANCE.unit == 'm', 'unit')
  print('schema parser: OK')
end

-- ---------------------------------------------------------------------------------------------- load the app
script = {}
dofile('app/Lumicorsa/Lumicorsa.lua')
assert(hud and script.windowDashboard and script.windowHud, 'callbacks not registered')
local R = require('backend/registry')
local St = storages[1]
local verify = require('backend/verify')
local function frame(n)   -- one game frame: the HUD callback, then the visible app windows, then timers
  for _ = 1, n or 1 do
    now = now + 1 / 60; hud('game')
    if WINDOWS.IMGUI_LUA_Lumicorsa_hud and WINDOWS.IMGUI_LUA_Lumicorsa_hud.vis then script.windowHud(1 / 60) end
    for _, f in ipairs(timeouts) do f() end; timeouts = {}
  end
end
local function check(where) if #log.errors > 0 then fail(where .. ': ' .. table.concat(log.errors, '\n')) end end
frame(3); check('first frames')
print(string.format('registry: %d controls', #R.all))

-- 2. look passes ran with valid bindings
assert(#log.passes > 10, 'look passes did not run')
print('look passes: ' .. #log.passes .. ' offscreen passes validated')

-- 3. every tab, every mode, then click everything per tab
local tabs = require('ui/tabs')
for _, mode in ipairs({ 'Basic', 'Advanced', 'Expert' }) do
  St.mode = mode
  for _, t in ipairs(tabs.ORDER) do St.tab = t; script.windowDashboard(1 / 60); check(mode .. '/' .. t) end
end
St.mode = 'Expert'
for _, t in ipairs(tabs.ORDER) do
  St.tab = t
  clickFilter = function (id) return not id:find('^hdr_') and not id:find('^tab_') and not id:find('reset$') and not id:find('^modal') end
  script.windowDashboard(1 / 60); frame(1)
  clickFilter = function () return false end
  St.tab = t; require('ui/dashboard').modal = nil
  script.windowDashboard(1 / 60); frame(1)
  check('click all on ' .. t)
end
St.master = true
print('dashboard: all tabs in all modes, every control clicked: OK')

-- 4. HUD
for _, u in ipairs({ 'km/h', 'mph' }) do St.units = u; St.hudOn = true; script.windowHud(1 / 60); frame(1); check('hud ' .. u) end
assert(require('hud/cluster').last.units == 'mph', 'cluster drew with mph')

-- 5. debounce: a slider write waits for 250 ms
local d = R.get('shdist')
d.set(250)
assert(FILES['X/cfg/extension/smart_shadows.ini'] == nil or (FILES['X/cfg/extension/smart_shadows.ini'].BASIC or {}).AUTOMATIC_SPLITS_DISTANCE ~= 250, 'written before debounce')
frame(30)
assert(FILES['X/cfg/extension/smart_shadows.ini'].BASIC.AUTOMATIC_SPLITS_DISTANCE == 250, 'not written after debounce')
print('debounce: OK')

-- 6. palette
local pal = require('ui/palette')
local found = false
for _, e in ipairs(R.all) do if e.tab and pal.score('bloom', e.label) then found = true end end
assert(found, 'palette cannot find bloom')
assert(pal.score('rscl', 'Render scale') ~= nil, 'fuzzy subsequence')

-- 7. quick ring: hold Q, release fires the hovered item
local qb = buttons['__APP_LUMICORSA_RING#obj']
qb.isDown = true; frame(2); qb.isDown = false; frame(1); check('quick ring')

-- 8. self-test over every control
verify.selftest(require('backend/verify').__env or nil)
for _ = 1, 6000 do frame(1); if not verify.running then break end end
check('self-test')
local logText = io.load('app/Lumicorsa/selftest.log')
assert(logText, 'selftest.log not written')
local fails = {}
for line in logText:gmatch('[^\r\n]+') do if line:find('^FAIL') then fails[#fails + 1] = line end end
print(logText:match('(%d+ PASS, %d+ FAIL, %d+ LOCKED[^\r\n]*)'))
assert(#fails == 0, 'self-test failures:\n' .. table.concat(fails, '\n'))

-- 9. proof and a short online soak
verify.proof(require('backend/verify').__env)
for _ = 1, 6000 do frame(1); if not verify.running then break end end
assert(log.shots >= 15, 'proof screenshots: ' .. log.shots)
SIM.isOnlineRace = true
verify.soak(require('backend/verify').__env, 4, 2)
for _ = 1, 2000 do frame(1); if not verify.running then break end end
local soak = io.load('app/Lumicorsa/soak.log')
assert(soak and soak:find('RESULT: PASS'), 'soak: ' .. tostring(soak))
check('verification')
print('proof (' .. log.shots .. ' shots) and soak: OK')
print('lua mock test: OK')
