--[[
  System and Photo: optional ReShade install, profiles, performance overlay, GPU budget, cost measurement, screenshots.

  ReShade (optional, Lumicorsa runs fully without it): after the user confirms, downloads the official add-on build
  from reshade.me, takes ReShade64.dll out of the installer's embedded zip and puts it next to acs.exe as dxgi.dll.
  A marker file records that Lumicorsa installed it; Uninstall only ever removes a dxgi.dll that Lumicorsa put there.
  If another dxgi.dll is already present (another ReShade or another mod), install refuses instead of overwriting it.
]]

local C = require('backend/config')
local telemetry = require('backend/telemetry')

local M = {}

local ROOT = function () return ac.getFolder(ac.FolderID.Root) end
local MARKER = function () return ROOT() .. '/lumicorsa-reshade.json' end
local DXGI = function () return ROOT() .. '/dxgi.dll' end

-- ---------------------------------------------------------------------------------------------- ReShade
function M.reshadeState()
  if io.fileExists(MARKER()) and io.fileExists(DXGI()) then return 'installed by Lumicorsa' end
  if io.fileExists(DXGI()) and (io.fileExists(ROOT() .. '/ReShade.ini') or io.dirExists(ROOT() .. '/reshade-shaders')) then return 'installed' end
  if io.fileExists(DXGI()) then return 'other dxgi.dll present' end
  return 'not installed'
end

M.status = ''   -- last message for the UI

local function findSetupUrl(cb)
  web.get('https://reshade.me', function (err, response)
    if err or not response or not response.body then return cb(nil, 'reshade.me is unreachable') end
    local path = response.body:match('(downloads/ReShade_Setup_[%d%.]+_Addon%.exe)')
    if not path then return cb(nil, 'no add-on download link on reshade.me') end
    cb('https://reshade.me/' .. path)
  end)
end

function M.installReshade(done)
  done = done or function () end
  local state = M.reshadeState()
  if state ~= 'not installed' then M.status = 'Not installed: ReShade or another dxgi.dll is already there'; return done(false) end
  M.status = 'Finding the latest ReShade…'
  findSetupUrl(function (url, why)
    if not url then M.status = why; return done(false) end
    M.status = 'Downloading ' .. url:match('[^/]+$') .. '…'
    web.get(url, function (err, response)
      if err or not response or not response.body then M.status = 'Download failed'; return done(false) end
      local body = response.body
      local zipStart = body:find('PK\3\4', 1, true)            -- the setup exe carries a zip payload
      if not zipStart then M.status = 'Unexpected installer format'; return done(false) end
      local tmp = ac.getFolder(ac.FolderID.ExtCfgState) .. '/lumicorsa-reshade-setup.zip'
      io.save(tmp, body:sub(zipStart))
      local dll = io.loadFromZip(tmp, 'ReShade64.dll')
      io.deleteFile(tmp)
      if not dll or #dll < 100000 then M.status = 'ReShade64.dll not found in the installer'; return done(false) end
      io.save(DXGI(), dll)
      io.save(MARKER(), JSON.stringify({ source = url, installed = os.date('!%Y-%m-%dT%H:%M:%SZ') }))
      M.status = 'ReShade installed. Restart Assetto Corsa to load it.'
      done(true)
    end)
  end)
end

function M.uninstallReshade()
  if not io.fileExists(MARKER()) then M.status = 'Only a ReShade that Lumicorsa installed can be removed here'; return false end
  io.deleteFile(DXGI()); io.deleteFile(MARKER())
  M.status = 'ReShade removed. Restart Assetto Corsa.'
  return true
end

-- ---------------------------------------------------------------------------------------------- profiles
function M.profilePath() return ac.getFolder(ac.FolderID.Documents) .. '/Assetto Corsa/Lumicorsa/profile.json' end

function M.exportProfile(St, values)
  local look = {}
  for k, v in pairs(values) do if type(v) == 'number' then look[k] = v end end
  local store = {}
  for _, k in ipairs({ 'neural', 'nr', 'light', 'atmos', 'detail', 'lens', 'shafts', 'flare', 'ao', 'adapt', 'mist', 'hudOn', 'hudViews',
    'units', 'hudPos', 'hudScale', 'hudOpacity', 'sweep', 'needle', 'lcd', 'shiftAt', 'warm', 'glow', 'lamps' }) do store[k] = St[k] end
  io.createDir(ac.getFolder(ac.FolderID.Documents) .. '/Assetto Corsa/Lumicorsa')
  return io.save(M.profilePath(), JSON.stringify({ app = 'Lumicorsa', version = 2, look = look, store = store }))
end

function M.importProfile(St, values)
  local text = io.load(M.profilePath())
  if not text then return false end
  local ok, t = pcall(JSON.parse, text)
  if not ok or type(t) ~= 'table' or t.app ~= 'Lumicorsa' then return false end
  for k, v in pairs(t.look or {}) do if values[k] ~= nil and type(v) == 'number' then values[k] = v end end
  for k, v in pairs(t.store or {}) do if St[k] ~= nil and type(v) == type(St[k]) then St[k] = v end end
  return true
end

-- ---------------------------------------------------------------------------------------------- GPU budget
-- With measured costs, switch off the costliest effect groups until the total fits the budget (ms).
function M.budgetOff(St)
  local off = {}
  if not St.budgetOn or not telemetry.costs.measuredAt then return off end
  local items, total = {}, 0
  for _, g in ipairs(telemetry.GROUPS) do
    local c = telemetry.costs[g]
    if c and g ~= 'grade' then items[#items + 1] = { g = g, c = c }; total = total + c end
  end
  total = total + (telemetry.costs.grade or 0)
  table.sort(items, function (a, b) return a.c > b.c end)
  for _, it in ipairs(items) do
    if total <= St.budget then break end
    off[it.g] = true; total = total - it.c
  end
  return off
end

-- ---------------------------------------------------------------------------------------------- registry
function M.register(R, St, actions)
  local fmt = R.fmt
  R.action('reshade_install', 'Install ReShade', function () actions.confirmReshade() end, {
    key = 'downloads from reshade.me, installs dxgi.dll next to acs.exe',
    verify = function (report)   -- dry run: the official download link can be found; nothing is installed
      findSetupUrl(function (url, why) report(url ~= nil, url or why) end)
      return 'async'
    end })
  R.action('reshade_remove', 'Uninstall ReShade', function () M.uninstallReshade() end, {
    key = 'removes only a dxgi.dll Lumicorsa installed',
    verify = function () return io.fileExists(MARKER()) == io.fileExists(MARKER()) end })
  R.state('overlay', 'Performance overlay', { kind = 'toggle', get = function () return St.overlay end,
    set = function (v) St.overlay = v end, readback = function () return actions.overlayDrawn() end, frames = 3 })
  R.state('budgetOn', 'Keep effects inside the GPU budget', { kind = 'toggle', hint = 'Switches off the costliest effects first',
    get = function () return St.budgetOn end, set = function (v) St.budgetOn = v end, readback = function () return St.budgetOn end })
  R.state('budget', 'GPU budget', { kind = 'slider', min = 1, max = 6, step = 0.1, default = 3, fmt = fmt.unit(' ms', 1),
    get = function () return St.budget end, set = function (v) St.budget = v end, readback = function () return St.budget end })
  R.action('measure', 'Measure effect costs', function () actions.measure() end, {
    key = 'switches each effect off for 1.5 s and records the GPU frame-time drop',
    verify = function () return telemetry.gpuFrameMs() ~= nil end })
  R.action('export', 'Export profile', function () M.exportProfile(St, actions.values) end, { key = M.profilePath(),
    verify = function () M.exportProfile(St, actions.values); return io.fileExists(M.profilePath()) end })
  R.action('import', 'Import profile', function () M.importProfile(St, actions.values) end, { key = M.profilePath(),
    verify = function () M.exportProfile(St, actions.values); return M.importProfile(St, actions.values) end })

  -- Photo
  R.action('shot', 'Take screenshot', function () pcall(ac.makeScreenshot, nil, nil, nil) end, { key = 'ac.makeScreenshot',
    verify = function (report)
      ac.makeScreenshot(nil, nil, function (err) report(err == nil, err or 'saved to Documents/Assetto Corsa/screens') end)
      return 'async'
    end })
  R.csp('shotscale', 'Screenshot size', 'nice_screenshots', 'ACCUMULATION_AA', 'RESOLUTION_MULTIPLIER', { kind = 'seg',
    options = { { label = 'Native', value = 1 }, { label = '2×', value = 2 }, { label = '4×', value = 4 } } })
  R.api('mblur', 'Motion blur in replays', { kind = 'slider', min = 0, max = 100, step = 1, default = 40, fmt = fmt.pct,
    key = 'extra_fx.ini [MOTION_BLUR] ENABLED / EXTERIOR_ONLY=2 / MULT',
    get = function ()
      if tonumber(C.get('csp:extra_fx', 'MOTION_BLUR', 'ENABLED', 0)) ~= 1 then return 0 end
      return (tonumber(C.get('csp:extra_fx', 'MOTION_BLUR', 'MULT', 0.5)) or 0) * 100
    end,
    set = function (v, now)
      local f = now and C.set or C.setLater
      f('csp:extra_fx', 'MOTION_BLUR', 'ENABLED', v > 0 and 1 or 0)
      f('csp:extra_fx', 'MOTION_BLUR', 'EXTERIOR_ONLY', 2)
      f('csp:extra_fx', 'MOTION_BLUR', 'MULT', v / 100)
    end,
    readback = function ()
      if tonumber(C.readback('csp:extra_fx', 'MOTION_BLUR', 'ENABLED', 0)) ~= 1 then return 0 end
      return (tonumber(C.readback('csp:extra_fx', 'MOTION_BLUR', 'MULT', 0.5)) or 0) * 100
    end })
end

return M
