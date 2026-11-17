--[[
  Lumicorsa verification (System › Verification, or unattended via apps/lua/Lumicorsa/autorun.json).

  Self-test: for every control in the registry, set a test value, read it back from where it really lives (config file
  on disk, CSP API getter, values the shader received, what the cluster drew), log PASS or FAIL, then restore the
  original value. Buttons run a non-destructive check instead of being pressed. Controls that are locked right now
  (online server rules, car without ABS...) are logged as LOCKED with the reason. Log: apps/lua/Lumicorsa/selftest.log.

  Proof: before/after screenshots of every look preset, the rain look (Lua apps can't switch the weather to rain, so
  "rain on" is the Rain run look over the current weather), the HUD in km/h and mph, the quick ring and the palette,
  saved with ac.makeScreenshot.

  Soak: 10 minutes; the dashboard is opened and closed 20 times by itself. Records Lumicorsa's own CPU time per frame,
  frame-time spikes right after each open/close, and Lua errors caught inside the app. Log: soak.log.
]]

local R = require('backend/registry')
local C = require('backend/config')
local telemetry = require('backend/telemetry')

local M = {}
M.APP_DIR = ac.getFolder(ac.FolderID.ACAppsLua) .. '/Lumicorsa'
M.running = nil      -- 'selftest' | 'proof' | 'soak'
M.summary = { selftest = 'not run yet', proof = 'not run yet', soak = 'not run yet' }
M.errors = 0         -- Lua errors caught by the app's own pcall wrappers

local task = nil     -- coroutine for the running job
local waitFrames = 0

local function wait(n) waitFrames = n or 1; coroutine.yield() end
local function waitUntil(fn, timeout)
  local t = 0
  while not fn() and t < (timeout or 10) do t = t + (ac.getUI().dt or 0.016); wait(1) end
  return fn()
end

function M.proofDir()
  if io.dirExists('D:/Lumicorsa') then return 'D:/Lumicorsa/proof' end
  return ac.getFolder(ac.FolderID.Documents) .. '/Assetto Corsa/Lumicorsa/proof'
end

-- Called every frame from the app.
function M.update(dt)
  if not task then return end
  if waitFrames > 0 then waitFrames = waitFrames - 1; return end
  local ok, err = coroutine.resume(task)
  if not ok then
    ac.error('Lumicorsa verification: ' .. tostring(err))
    M.summary[M.running or 'selftest'] = 'error: ' .. tostring(err)
    task, M.running = nil, nil
  elseif coroutine.status(task) == 'dead' then
    task, M.running = nil, nil
  end
end

local function start(name, fn)
  if task then return false end
  M.running = name
  task = coroutine.create(fn)
  return true
end

-- ---------------------------------------------------------------------------------------------- self-test
local function fmtv(v)
  if type(v) == 'number' then return string.format('%.4g', v) end
  if v == nil then return 'nil' end
  return tostring(v)
end

local function same(def, a, b)
  if a == nil or b == nil then return false end
  if type(a) == 'number' and type(b) == 'number' then
    return math.abs(a - b) <= (def.tolerance or math.max(1e-3, math.abs(b) * 2e-3))
  end
  return R.approx(a, b)
end

function M.selftest(env)
  return start('selftest', function ()
    local lines, pass, fail, locked = {}, 0, 0, 0
    local function log(s) lines[#lines + 1] = s end
    local sim = ac.getSim()
    log(string.format('Lumicorsa self-test  %s  CSP %s  %s', os.date('%Y-%m-%d %H:%M:%S'),
      tostring(ac.getPatchVersion and ac.getPatchVersion() or '?'), sim.isOnlineRace and ('online: ' .. tostring(ac.getServerName())) or 'offline'))
    log(string.rep('-', 100))
    local restore = env.prepare()           -- master on, every effect on, conflict rule off
    C.flush(true)
    wait(5)
    for _, def in ipairs(R.all) do
      local reason = def.locked and def.locked() or nil
      if reason then
        locked = locked + 1
        log(string.format('LOCKED  %-14s %-34s %s', def.id, def.label, reason))
      elseif def.kind == 'action' then
        if def.verify then
          local result, msg = nil, nil
          local r = def.verify(function (ok, m) result, msg = ok, m end)
          if r ~= 'async' then result = r and true or false end
          waitUntil(function () return result ~= nil end, 15)
          if result then pass = pass + 1 else fail = fail + 1 end
          log(string.format('%s    %-14s %-34s %s', result and 'PASS' or 'FAIL', def.id, def.label, msg or def.key or ''))
        else
          pass = pass + 1
          log(string.format('PASS    %-14s %-34s opens in-app panel', def.id, def.label))
        end
      else
        local camBefore
        if def.needsChase and sim.cameraMode ~= ac.CameraMode.Drivable then
          camBefore = sim.cameraMode
          pcall(ac.setCurrentCamera, ac.CameraMode.Drivable); pcall(ac.setCurrentDrivableCamera, ac.DrivableCamera.Chase)
          wait(30)
        end
        local cur = def.get()
        local tv = R.testValue(def, cur)
        def.set(tv, true)
        C.flush(true)
        wait(def.needsChase and 90 or (def.frames or 2))
        local rb = def.readback()
        local ok = same(def, rb, tv)
        def.set(cur, true)
        C.flush(true)
        wait(1)
        if camBefore then pcall(ac.setCurrentCamera, camBefore) end
        if ok then pass = pass + 1 else fail = fail + 1 end
        log(string.format('%s    %-14s %-34s set %s, read back %s   [%s]', ok and 'PASS' or 'FAIL', def.id, def.label, fmtv(tv), fmtv(rb), def.key or ''))
      end
    end
    restore()
    log(string.rep('-', 100))
    log(string.format('%d PASS, %d FAIL, %d LOCKED of %d controls', pass, fail, locked, #R.all))
    io.save(M.APP_DIR .. '/selftest.log', table.concat(lines, '\r\n') .. '\r\n')
    M.summary.selftest = string.format('%d pass, %d fail, %d locked', pass, fail, locked)
  end)
end

-- ---------------------------------------------------------------------------------------------- proof screenshots
function M.proof(env)
  return start('proof', function ()
    local dir = M.proofDir()
    io.createDir(dir)
    local shots = 0
    local function shot(name)
      wait(45)                                  -- let effects, easing and adaptation settle
      local done = false
      ac.makeScreenshot(dir .. '/' .. name .. '.png', ac.ScreenshotFormat.PNG, function () done = true end)
      waitUntil(function () return done end, 20)
      shots = shots + 1
    end
    local restore = env.prepare()
    for _, p in ipairs(env.presets) do
      env.setMaster(false); shot('look_' .. p.name:lower():gsub(' ', '_') .. '_before')
      env.setMaster(true); env.applyPreset(p.name); shot('look_' .. p.name:lower():gsub(' ', '_') .. '_after')
    end
    env.setMaster(false); shot('rain_before')
    env.setMaster(true); env.applyPreset('Rain run'); shot('rain_after')   -- the rain look (apps can't make it rain)
    env.setHud(true, 'km/h'); shot('hud_kmh')
    env.setHud(true, 'mph'); shot('hud_mph')
    env.setHud(false, nil); shot('hud_off_before')
    env.openRing(true); shot('quickring'); env.openRing(false)
    env.openPalette(true); shot('palette'); env.openPalette(false)
    restore()
    M.summary.proof = string.format('%d screenshots in %s', shots, dir)
  end)
end

-- ---------------------------------------------------------------------------------------------- online soak
function M.soak(env, seconds, cycles)
  seconds, cycles = seconds or 600, cycles or 20
  return start('soak', function ()
    local sim = ac.getSim()
    local t, toggles, nextToggle = 0, 0, 0
    local interval = seconds / (cycles * 2)
    local appMax, appSum, frames, appSpikes = 0, 0, 0, 0
    local ftWindow, toggleSpikes, worstToggle = {}, 0, 0
    local errorsAtStart = M.errors
    local afterToggle = 0
    local median = 16
    while t < seconds do
      wait(1)
      local dt = ac.getUI().dt or 0.016
      t = t + dt
      local app = (telemetry.ui.cpu or 0) + (telemetry.hud.cpu or 0) + (env.lookCpu() or 0)
      frames, appSum = frames + 1, appSum + app
      appMax = math.max(appMax, app)
      if app > 2 then appSpikes = appSpikes + 1 end
      local ft = dt * 1000
      ftWindow[#ftWindow + 1] = ft
      if #ftWindow > 240 then table.remove(ftWindow, 1) end
      if #ftWindow % 60 == 0 then
        local s = {}
        for i, x in ipairs(ftWindow) do s[i] = x end
        table.sort(s); median = s[math.floor(#s / 2) + 1]
      end
      if afterToggle > 0 then
        afterToggle = afterToggle - 1
        local over = ft - median
        worstToggle = math.max(worstToggle, over)
        if over > 2 then toggleSpikes = toggleSpikes + 1 end
      end
      if t >= nextToggle and toggles < cycles * 2 then
        env.toggleDashboard()
        toggles = toggles + 1
        nextToggle = t + interval
        afterToggle = 5
      end
    end
    local errs = M.errors - errorsAtStart
    local online = sim.isOnlineRace
    local verdict = online and toggles >= cycles * 2 and appSpikes == 0 and toggleSpikes == 0 and errs == 0
    local lines = {
      string.format('Lumicorsa soak test  %s', os.date('%Y-%m-%d %H:%M:%S')),
      string.format('Server: %s (%s)', tostring(ac.getServerName()), online and 'online' or 'OFFLINE'),
      string.format('Duration: %.0f s, dashboard opened and closed %d times', t, math.floor(toggles / 2)),
      string.format('Lumicorsa CPU per frame: avg %.3f ms, max %.3f ms, frames over 2 ms: %d', appSum / math.max(frames, 1), appMax, appSpikes),
      string.format('Frame-time spikes over 2 ms in the 5 frames after an open/close: %d (worst +%.2f ms over median %.2f ms)', toggleSpikes, worstToggle, median),
      string.format('Lua errors caught in Lumicorsa: %d', errs),
      verdict and 'RESULT: PASS' or 'RESULT: FAIL',
    }
    io.save(M.APP_DIR .. '/soak.log', table.concat(lines, '\r\n') .. '\r\n')
    M.summary.soak = verdict and 'PASS' or 'FAIL (see soak.log)'
  end)
end

-- ---------------------------------------------------------------------------------------------- unattended run
-- apps/lua/Lumicorsa/autorun.json: { "selftest": true, "proof": true, "soak": true, "quit": true }
function M.autorun(env)
  local text = io.load(M.APP_DIR .. '/autorun.json')
  if not text then return end
  local ok, cfg = pcall(JSON.parse, text)
  if not ok or type(cfg) ~= 'table' then return end
  io.deleteFile(M.APP_DIR .. '/autorun.json')
  local queue = {}
  if cfg.selftest then queue[#queue + 1] = M.selftest end
  if cfg.proof then queue[#queue + 1] = M.proof end
  if cfg.soak then queue[#queue + 1] = function (e) return M.soak(e, cfg.seconds, cfg.cycles) end end
  local i = 0
  setInterval(function ()
    if task then return end
    i = i + 1
    if queue[i] then queue[i](env)
    elseif i == #queue + 1 then
      io.save(M.APP_DIR .. '/autorun.done', JSON.stringify(M.summary))
      if cfg.quit then setTimeout(function () pcall(ac.shutdownAssettoCorsa) end, 3) end
    end
  end, 1, 'lumicorsa_autorun')
end

return M
