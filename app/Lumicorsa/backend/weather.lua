--[[
  Weather: time of day and time speed (offline; online the server owns them), windscreen, visibility.

  CSP gives Lua apps no way to set the weather type, temperature or rain from an app (the WeatherFX controller owns
  them), so the design's Conditions and Rain cards aren't in the app. What's here:
  - Time: ac.setWeatherTimeOffset / ac.setWeatherTimeMultiplier, read back from ac.getSim().timeTotalSeconds and
    ac.getConditionsTimeScale(). Offline only.
  - Windscreen: Rain FX drops on screen, WeatherFX automatic wipers.
  - Visibility: Lumicorsa's own distance haze and ground mist (shader).
]]

local M = {}

M.LOCK = 'Server controls weather'
function M.locked() return ac.getSim().isOnlineRace and M.LOCK or nil end

function M.time() return (ac.getSim().timeTotalSeconds or 0) / 3600 end
function M.setTime(hours)
  if M.locked() then return false end
  local delta = hours * 3600 - (ac.getSim().timeTotalSeconds or 0)
  return pcall(ac.setWeatherTimeOffset, delta, true)
end

function M.timeSpeed() local ok, v = pcall(ac.getConditionsTimeScale); return ok and v or nil end
function M.setTimeSpeed(x) if not M.locked() then pcall(ac.setWeatherTimeMultiplier, x) end end

-- Sun elevation for the day strip, from the light direction (degrees above the horizon).
function M.sunElevation()
  local d = ac.getSim().lightDirection
  if not d then return nil end
  return math.deg(math.asin(math.max(-1, math.min(1, d.y))))
end

function M.register(R, St)
  local fmt = R.fmt
  R.api('tod', 'Time of day', { kind = 'daystrip', min = 0, max = 23.99, key = 'ac.setWeatherTimeOffset', locked = M.locked,
    get = M.time, set = M.setTime, tolerance = 0.05,
    testValue = function (cur) return (cur + 3) % 24 end })
  R.api('tmul', 'Time speed', { kind = 'slider', min = 0, max = 60, step = 1, default = 1, fmt = function (v) return '×' .. math.floor(v + 0.5) end,
    key = 'ac.setWeatherTimeMultiplier', locked = M.locked,
    get = function () return St.timeSpeed end, set = function (v) St.timeSpeed = v; M.setTimeSpeed(v) end,
    readback = M.timeSpeed })
  R.csp('drops', 'Raindrops on glass', 'rain_fx', 'SCREEN_DROPS', 'ENABLED')
  R.csp('wipers', 'Auto wipers', 'weather_fx', 'MISCELLANEOUS', 'SWITCH_WIPERS_WITH_AI', { hint = 'Turn on and off with the rain' })
end

return M
