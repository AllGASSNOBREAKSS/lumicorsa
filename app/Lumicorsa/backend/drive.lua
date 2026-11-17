--[[
  Drive: force feedback, assists, steering lock.

  - FFB strength: ac.setFFBMultiplier, live; read back from ac.getCar(0).ffbMultiplier.
  - Minimum force, kerb and road effects, steering lock: cfg/controls.ini, the file CM and AC's Controls page edit.
    AC reads it when a session starts.
  - Lock damper and gyro: CSP FFB Tweaks. CSP's only damper setting is the soft-lock damper, so the design's "Damper"
    knob is labelled for what it does. Gyro is an on/off switch in CSP (its strength is hidden), so it's a toggle.
  - ABS and traction control: ac.setABS / ac.setTractionControl, offline only (online the server sets assists), and
    only for cars that have them.
  - The design's "Calibrate wheel and pedals" has no API (calibration lives in Content Manager), so it isn't in the app.
]]

local M = {}

local function car() return ac.getCar(0) end

function M.assistLocked(kind)
  return function ()
    if ac.getSim().isOnlineRace then return 'Server sets assists online' end
    local c = car()
    local n = c and (kind == 'abs' and c.absModes or c.tractionControlModes) or 0
    if not n or n <= 0 then return kind == 'abs' and 'This car has no ABS' or 'This car has no traction control' end
    return nil
  end
end

local function assistOptions() return { { label = 'Off', value = 'Off' }, { label = 'Factory', value = 'Factory' }, { label = 'On', value = 'On' } } end
local function assistGet(kind)
  local c = car()
  if not c then return 'Off' end
  local mode, n = kind == 'abs' and c.absMode or c.tractionControlMode, kind == 'abs' and c.absModes or c.tractionControlModes
  if mode == 0 then return 'Off' end
  if n and mode >= n then return 'On' end
  return 'Factory'
end
local function assistSet(kind, v)
  local c = car()
  local n = c and (kind == 'abs' and c.absModes or c.tractionControlModes) or 0
  local mode = v == 'Off' and 0 or v == 'On' and n or math.min(1, n)
  if kind == 'abs' then pcall(ac.setABS, mode) else pcall(ac.setTractionControl, mode) end
end

function M.register(R, St)
  local fmt = R.fmt
  R.api('ffb', 'Strength', { kind = 'knob', min = 0, max = 150, step = 1, default = 100, fmt = fmt.pct, key = 'ac.setFFBMultiplier',
    get = function () local c = car(); return c and c.ffbMultiplier * 100 or 100 end,
    set = function (v) pcall(ac.setFFBMultiplier, v / 100) end,
    readback = function () local c = car(); return c and c.ffbMultiplier * 100 or nil end })
  R.ac('ffbmin', 'Minimum', 'controls', 'FF_TWEAKS', 'MIN_FF', { kind = 'knob', min = 0, max = 20, step = 0.5, default = 4, fmt = fmt.pct,
    fallback = 0.04, map = { to = function (x) return x / 100 end, from = function (x) return x * 100 end } })
  R.csp('damper', 'Lock damper', 'ffb_tweaks', 'CUSTOM_SOFT_LOCK', 'DAMPER', { kind = 'knob', min = 0, max = 100, step = 1, default = 0,
    fmt = fmt.pct, map = { to = function (x) return x / 100 end, from = function (x) return x * 100 end } })
  R.csp('gyro', 'Gyroscopic effect', 'ffb_tweaks', 'GYRO2', 'ENABLED', { hint = 'Physically based wheel gyro' })
  R.ac('kerb', 'Kerb rumble', 'controls', 'FF_ENHANCEMENT', 'CURBS', { kind = 'slider', min = 0, max = 100, step = 1, default = 30,
    fmt = fmt.pct, fallback = 0.3, map = { to = function (x) return x / 100 end, from = function (x) return x * 100 end } })
  R.ac('road', 'Road texture', 'controls', 'FF_ENHANCEMENT', 'ROAD', { kind = 'slider', min = 0, max = 100, step = 1, default = 30,
    fmt = fmt.pct, fallback = 0.3, map = { to = function (x) return x / 100 end, from = function (x) return x * 100 end } })
  R.api('absm', 'ABS', { kind = 'seg', options = assistOptions(), key = 'ac.setABS', locked = M.assistLocked('abs'),
    get = function () return assistGet('abs') end, set = function (v) assistSet('abs', v) end })
  R.api('tcm', 'Traction', { kind = 'seg', options = assistOptions(), key = 'ac.setTractionControl', locked = M.assistLocked('tc'),
    get = function () return assistGet('tc') end, set = function (v) assistSet('tc', v) end })
  R.ac('steerlock', 'Steering lock', 'controls', 'STEER', 'LOCK', { kind = 'slider', min = 180, max = 1080, step = 10, default = 900,
    fmt = fmt.unit('°'), fallback = 900 })
end

return M
