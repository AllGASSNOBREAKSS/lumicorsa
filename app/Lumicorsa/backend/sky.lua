--[[
  Sky: detect the weather engine (Pure, Sol), open their own planner/config apps, and the sky-quality switches their
  WeatherFX settings expose. Lumicorsa never replaces Pure or Sol; it works on top of either.
]]

local C = require('backend/config')

local M = {}

local ROOT = function () return ac.getFolder(ac.FolderID.ExtRoot) end

function M.detect()
  local style = C.get('csp:weather_fx', 'BASIC', 'IMPLEMENTATION', '')
  local pure = io.dirExists(ROOT() .. '/weather/pure')
  local sol = io.dirExists(ROOT() .. '/weather/sol')
  local active = type(style) == 'string' and style ~= '' and style or nil
  return { pure = pure, sol = sol, active = active,
    pureVersion = pure and C.manifestVersion(ROOT() .. '/weather/pure/manifest.ini') or nil }
end

function M.label()
  local d = M.detect()
  local parts = {}
  if d.pure then parts[#parts + 1] = 'Pure' .. (d.pureVersion and (' ' .. d.pureVersion) or '') end
  if d.sol then parts[#parts + 1] = 'Sol' end
  if #parts == 0 then return 'Default WeatherFX' end
  return table.concat(parts, ' + ') .. (d.active and ('  ·  active: ' .. d.active) or '')
end

M.APPS = {
  purePlanner = { folder = 'PurePlanner', window = 'main_pure_planner', label = 'Open Pure Planner' },
  pureConfig = { folder = 'PureConfig', window = 'main_pure_config', label = 'Open Pure Config' },
  solPlanner = { folder = 'SolPlanner', window = 'main', label = 'Open Sol Planner' },
}

local function appWindowVisible(a)
  local ok, w = pcall(ac.accessAppWindow, 'IMGUI_LUA_' .. a.folder .. '_' .. a.window)
  return ok and w and w:visible() or false
end

function M.register(R, St)
  for id, a in pairs(M.APPS) do
    if C.appInstalled(a.folder) then
      R.action(id, a.label, function () C.openApp(a.folder, a.window) end, {
        key = 'apps/lua/' .. a.folder,
        verify = function () C.openApp(a.folder, a.window); return appWindowVisible(a) end })
    end
  end
  R.csp('clouds', 'Extra cloud detail', 'weather_fx', 'PERFORMANCE', 'EXTRA_CLOUDS_FIDELITY')
  R.csp('cloudsh', 'Detailed cloud shadows', 'weather_fx', 'PERFORMANCE', 'DETAILED_CLOUD_SHADOWS')
  R.csp('stars', 'High-quality stars', 'weather_fx', 'PERFORMANCE', 'HIGH_QUALITY_STARS')
end

return M
