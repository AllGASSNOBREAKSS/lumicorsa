-- Runs the CSP app under LuaJIT with a stubbed CSP API: executes load, presets, a few frames of the window,
-- every button/toggle path, and the IPC write. Catches nil-calls and logic errors without Assetto Corsa.
-- usage: luajit tools/lua_mock_test.lua <out_dir>
local out = arg[1] or '/tmp/photolap_mock'
os.execute('mkdir -p "' .. out .. '/Photolap/state"')

local function vec2(x, y) return setmetatable({ x = x or 0, y = y or 0 }, {
  __add = function(a, b) return vec2(a.x + b.x, a.y + b.y) end }) end
_G.vec2 = vec2
_G.rgbm = function(r, g, b, m) return { r, g, b, m } end
local intervals, buttons = {}, {}
_G.setInterval = function(fn) intervals[#intervals + 1] = fn end
_G.JSON = { stringify = function() return '{}' end, parse = function() return {} end }
_G.ac = {
  FolderID = { ACAppsLua = 1029 },
  getFolder = function() return out end,
  storage = function(t) return t end,
  ControlButton = function(id) local b = { id = id }; function b:onPressed(f) buttons[id] = f end; return b end,
  accessAppWindow = function() return { setVisible = function() end, visible = function() return true end } end,
}
local files = {}
_G.io.save = function(p, d) local f = assert(io.open(p, 'w')); f:write(d); f:close(); files[p] = d end
_G.io.load = function(p) local f = io.open(p, 'r'); if not f then return nil end; local d = f:read('*a'); f:close(); return d end
_G.io.createDir = function() end

-- UI stub: every clickable returns true on the "click frame" so all branches execute.
local click = false
local noop = function() end
_G.ui = setmetatable({
  Font = { Title = 1, Small = 2 }, StyleColor = { SliderGrab = 1, Button = 2, Text = 3 }, KeyIndex = { P = 80, O = 79 },
  windowSize = function() return vec2(380, 690) end, getCursor = function() return vec2(16, 100) end,
  availableSpaceX = function() return 348 end,
  invisibleButton = function() return click end, button = function() return click end,
  itemHovered = function() return click end,
  slider = function(_, v) return v, click end,
}, { __index = function() return noop end })

script = {}
dofile('csp-app/Photolap/Photolap.lua')
assert(type(script.windowMain) == 'function', 'windowMain not defined')

for frame = 1, 4 do
  click = (frame == 2)
  script.windowMain(0.016)
  for _, f in ipairs(intervals) do f() end
end
for id, f in pairs(buttons) do f() end
for _, f in ipairs(intervals) do f() end

local ctl = io.load(out .. '/Photolap/state/control.ini')
assert(ctl and ctl:find('seq='), 'control.ini not written')
print(ctl)
print('lua mock test: OK (' .. #intervals .. ' intervals, hotkeys: ' .. (buttons.__APP_PHOTOLAP_TOGGLE and 'toggle ' or '') .. (buttons.__APP_PHOTOLAP_MASTER and 'master' or '') .. ')')
