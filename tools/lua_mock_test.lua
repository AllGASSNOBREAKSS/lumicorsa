-- Runs the CSP app under LuaJIT with a stubbed CSP API. It loads the app, renders frames through the HUD callback and
-- checks, for every shader pass, that the textures/values passed from Lua match the `// @textures` / `// @values`
-- header of the shader (names and types). A mismatch would recompile or break the shader in game.
-- Then it flips every toggle (engaged, each effect, neural, split, other-PP-app conflict) and checks the pass graph.
-- usage (from the repo root): luajit tools/lua_mock_test.lua

package.path = 'csp-app/Photolap/?.lua;' .. package.path

-- ---------------------------------------------------------------------------------------------- vector stubs
local V2, V3 = {}, {}
V2.__index, V3.__index = V2, V3
V2.__add = function (a, b) return vec2(a.x + b.x, a.y + b.y) end
local function isV2(x) return getmetatable(x) == V2 end
local function isV3(x) return getmetatable(x) == V3 end
function vec2(x, y) return setmetatable({ x = x or 0, y = y or 0 }, V2) end
function vec3(x, y, z) return setmetatable({ x = x or 0, y = y or 0, z = z or 0 }, V3) end
function rgbm(r, g, b, m) return { r, g, b, m } end

-- ---------------------------------------------------------------------------------------------- CSP stubs
local intervals, buttons, storages = {}, {}, {}
local hud = nil
local log = { updates = {}, finals = {}, errors = {}, texts = {} }
local appWindows = {}
local function fail(msg) error(msg, 0) end

function setInterval(fn) intervals[#intervals + 1] = fn end
JSON = { stringify = function () return '{}' end, parse = function () return {} end }
math.applyLag = function (v, t, lag, dt) return t + (v - t) * lag end

render = {
  TextureFormat = { R16G16B16A16 = { Float = 10 } },
  AntialiasingMode = { None = 0 },
  BlendMode = { Opaque = 0 },
}

local SIM = {
  windowSize = vec2(1920, 1080), cameraClipNear = 0.1, cameraClipFar = 5000,
  isVRMode = false, isHDR = false, upscaleAppliedFactor = 0.58, isFSRActive = false, isTAAActive = true,
}
local function readHeader(code)
  local h = {}
  for key, rest in code:gmatch('// @(%w+)[ \t]*([^\n]*)') do h[key] = rest end
  return h
end

local TYPES = { float = 'number', float2 = 'vec2', float3 = 'vec3' }
local function kind(x)
  if type(x) == 'number' then return 'number' elseif isV2(x) then return 'vec2' elseif isV3(x) then return 'vec3' end
  return type(x)
end

local canvasId = 0
local function checkPass(p, where)
  assert(type(p.shader) == 'string' and p.shader:find('float4 main%(PS_IN pin%)'), where .. ': no shader main()')
  local h = readHeader(p.shader)
  local wantTex = {}
  for t in (h.textures or ''):gmatch('%S+') do wantTex[t] = true end
  for t in pairs(wantTex) do
    local v = p.textures[t]
    if v == nil or v == false then fail(where .. ': texture ' .. t .. ' not bound') end
  end
  for t in pairs(p.textures) do if not wantTex[t] then fail(where .. ': texture ' .. t .. ' is not in the shader header') end end
  local wantVal = {}
  for name, ty in (h.values or ''):gmatch('(%S+):(%S+)') do wantVal[name] = ty end
  for name, ty in pairs(wantVal) do
    local v = p.values[name]
    if v == nil then fail(where .. ': value ' .. name .. ' missing') end
    if kind(v) ~= TYPES[ty] then fail(where .. ': value ' .. name .. ' is ' .. kind(v) .. ', shader wants ' .. ty) end
  end
  for name in pairs(p.values) do if not wantVal[name] then fail(where .. ': value ' .. name .. ' is not in the shader header') end end
  return h
end

ui = setmetatable({
  Font = { Title = 1, Small = 2 }, StyleColor = { SliderGrab = 1, Button = 2, Text = 3 }, KeyIndex = { P = 80, O = 79 },
  windowSize = function () return vec2(380, 690) end, getCursor = function () return vec2(16, 100) end,
  availableSpaceX = function () return 348 end,
  invisibleButton = function () return false end, button = function () return false end,
  itemHovered = function () return false end,
  slider = function (_, v) return v, false end,
  textColored = function (t) log.texts[#log.texts + 1] = t end,
  textWrapped = function (t) log.texts[#log.texts + 1] = t end,
  onExclusiveHUD = function (cb) hud = cb end,
  ExtraCanvas = function (size)
    canvasId = canvasId + 1
    local c = { id = canvasId, sz = size }
    function c:size() return self.sz end
    function c:dispose() end
    function c:updateWithShader(p)
      checkPass(p, 'canvas ' .. self.id)
      log.updates[#log.updates + 1] = { canvas = self, name = p.shader:match('// @textures ([^\n]*)'), textures = p.textures }
      return true
    end
    return c
  end,
  renderShader = function (p)
    checkPass(p, 'final')
    local copy = {}
    for k, v in pairs(p.values) do copy[k] = v end
    log.finals[#log.finals + 1] = { values = copy, base = p.textures.txPLBase }
    return true
  end,
}, { __index = function () return function () end end })

ac = {
  FolderID = { ACAppsLua = 1029 },
  CSPModuleID = { GraphicsAdjustments = 'graphics_adjustments' },
  getFolder = function () return 'csp-app' end,
  storage = function (t) storages[#storages + 1] = t; return t end,
  ControlButton = function (id) local b = {}; function b:onPressed(f) buttons[id] = f end; return b end,
  accessAppWindow = function () return { setVisible = function () end, visible = function () return true end } end,
  getSim = function () return SIM end,
  getUI = function () return { windowSize = vec2(1920, 1080), dt = 0.016 } end,
  INIConfig = { cspModule = function () return { get = function (_, s, k, d)
    if s == 'FSR' and k == 'ACTIVE' then return 1 elseif s == 'FSR' and k == 'OLD_IMPLEMENTATION' then return 3 end
    return d end } end },
  isModuleActive = function () return true end,
  getAppWindows = function () return appWindows end,
  getPerformanceCPUAndGPUTime = function () return 5.0, 8.0 end,
  onRelease = function () end,
  error = function (...) log.errors[#log.errors + 1] = table.concat({ ... }, ' ') end,
}
io.load = function (p) local f = io.open(p, 'rb'); if not f then return nil end; local d = f:read('*a'); f:close(); return d end
os.preciseClock = os.clock

-- ---------------------------------------------------------------------------------------------- load the app
script = {}
dofile('csp-app/Photolap/Photolap.lua')
assert(type(script.windowMain) == 'function', 'windowMain not defined')
assert(type(hud) == 'function', 'app did not register ui.onExclusiveHUD')
local store = storages[1]
assert(store and store.enabled ~= nil, 'main storage not found')

local function frame()
  log.updates, log.finals = {}, {}
  hud('game')
  for _, f in ipairs(intervals) do f() end
  assert(#log.errors == 0, 'app reported: ' .. table.concat(log.errors, '; '))
  return #log.updates, log.finals[#log.finals]
end

-- 1. everything on
local n, f = frame()
assert(f, 'engaged frame drew nothing')
assert(n == 17, 'expected 17 offscreen passes with everything on, got ' .. n)
assert(type(f.base) == 'table', 'neural on: final pass should read the neural output canvas')
assert(f.values.gPLLight == 1 and f.values.gPLAtmos == 1 and f.values.gPLDetail == 1 and f.values.gPLLens == 1, 'effect flags')
print('all on: ' .. n .. ' passes + final')

-- 2. each toggle changes what is drawn
store.neural = false; n, f = frame()
assert(f.base == 'dynamic::screen' and n == 13, 'neural off: expected 13 passes reading the raw frame, got ' .. n)
store.neural = true

store.light = false; n, f = frame()
assert(f.values.gPLLight == 0 and f.values.gPLBloomOn == 0 and n == 8, 'light off: expected no bloom chain, got ' .. n)
store.light = true

store.detail = false; n, f = frame()
assert(f.values.gPLDetail == 0 and f.values.PL_Clarity == 0 and n == 14, 'detail off: expected no clarity passes, got ' .. n)
store.detail = true

store.atmos = false; n, f = frame()
assert(f.values.gPLAtmos == 0 and n == 16, 'atmos off: expected no depth probe, got ' .. n)
store.atmos = true

store.lens = false; n, f = frame()
assert(f.values.gPLLens == 0, 'lens off')
store.lens = true

store.split = true; n, f = frame()
assert(f.values.gPLSplit == 1, 'split view flag')
store.split = false

-- 3. bypass: nothing drawn at all, instantly
store.enabled = false; n, f = frame()
assert(n == 0 and f == nil, 'bypass must draw nothing')
buttons.__APP_PHOTOLAP_MASTER(); n, f = frame()
assert(store.enabled and f, 'Alt+O did not re-engage')

-- 4. another PP app: stay on top, no double tonemap
appWindows = { { name = 'IMGUI_LUA_DreamRealism74_dpm_main', visible = true } }
for _, fn in ipairs(intervals) do fn() end
n, f = frame()
assert(f.values.PL_HighlightRecover == 0 and f.values.PL_FilmicStrength == 0, 'conflict: re-tonemap must be off')
appWindows = { { name = 'IMGUI_LUA_Dream_DriverSwap_main', visible = true } }
for _, fn in ipairs(intervals) do fn() end
n, f = frame()
assert(f.values.PL_FilmicStrength > 0, 'unrelated Dream_* app must not count as a PP filter')

-- 5. panel draws, status reads back the native pipeline
log.texts = {}
script.windowMain(0.016)
local all = table.concat(log.texts, '\n')
assert(all:find('running', 1, true), 'status should say Shaders: running')
assert(all:find('DLSS', 1, true), 'upscaler row should show DLSS')
assert(not all:lower():find('backend', 1, true), 'no neural-backend warning any more')
for _, t in ipairs(log.texts) do
  local s = tostring(t)
  assert(not s:find('NVIDIA', 1, true) and not s:find('DLSS 5', 1, true), 'UI must not name NVIDIA / DLSS 5: ' .. s)
end

-- 6. every UI branch with clicks on
ui.invisibleButton = function () return true end
ui.button = function () return true end
ui.slider = function (_, v) return v, true end
store.advanced = true
script.windowMain(0.016); script.windowMain(0.016)
n, f = frame()

print('lua mock test: OK (' .. #intervals .. ' intervals, hotkeys: ' .. (buttons.__APP_PHOTOLAP_TOGGLE and 'toggle ' or '') .. (buttons.__APP_PHOTOLAP_MASTER and 'master' or '') .. ')')
