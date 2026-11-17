--[[
  LUMICORSA — light for Assetto Corsa. Graphics, HUD and settings, running inside Custom Shaders Patch.
  Copyright (c) 2026 Lumicorsa contributors. MIT License.

  Windows: "Lumicorsa" (dashboard, Alt+P) and "Lumicorsa HUD" (analog cluster, Alt+H).
  Hotkeys (rebindable in CSP › Controls): Alt+P dashboard, Alt+O vanilla, Alt+H HUD, hold Q quick ring, Ctrl+K search.
  The look is drawn in ui.onExclusiveHUD, after the finished scene and before every HUD element and app window.
]]

local VERSION = '2.0.0'

local C = require('backend/config')
local R = require('backend/registry')
local state = require('backend/state')
local look = require('backend/look')
local telemetry = require('backend/telemetry')
local camera = require('backend/camera')
local weather = require('backend/weather')
local graphics = require('backend/graphics')
local drive = require('backend/drive')
local audio = require('backend/audio')
local sky = require('backend/sky')
local system = require('backend/system')
local verify = require('backend/verify')
local cluster = require('hud/cluster')
local T = require('ui/theme')
local W = require('ui/widgets')
local dashboard = require('ui/dashboard')
local tabs = require('ui/tabs')
local palette = require('ui/palette')
local ring = require('ui/quickring')

local St = state.store
local DASH = 'IMGUI_LUA_Lumicorsa_dashboard'
local HUD = 'IMGUI_LUA_Lumicorsa_hud'

local function window(name) local ok, w = pcall(ac.accessAppWindow, name); return ok and w or nil end
local function safe(fn, ...)   -- every per-frame callback runs protected; errors are counted for the soak test
  local ok, err = pcall(fn, ...)
  if not ok then verify.errors = verify.errors + 1; ac.error('Lumicorsa: ' .. tostring(err)) end
  return ok
end

-- ---------------------------------------------------------------------------------------------- shared environment
local frameNo, lastOverlay, lastHud, lookCpu = 0, -100, -100, 0
local env = {}
local actions = {
  values = state.values,
  overlayDrawn = function () return frameNo - lastOverlay < 3 end,
  hudDrawn = function () return frameNo - lastHud < 3 end,
  measure = function () env.startMeasure() end,
  confirmReshade = function () env.reshadeModal() end,
}

-- ---------------------------------------------------------------------------------------------- registry
state.register(R)
camera.register(R, St)
weather.register(R, St)
graphics.register(R, St)
drive.register(R, St)
audio.register(R, St)
sky.register(R, St)
system.register(R, St, actions)
cluster.register(R, St, actions)

R.action('smoothMotion', 'Set up NVIDIA Smooth Motion', function () env.smoothMotionModal() end,
  { key = 'opens a short guide (driver setting, nothing is faked in game)' })
R.action('fovCalc', 'Calculate from my screen size', function () env.fovModal() end, { key = 'sets the cockpit FOV from screen size and eye distance' })
R.state('photoDof', 'Depth of field in free camera', { kind = 'toggle', hint = 'F7 camera; aperture, focus and bokeh below',
  get = function () return St.photoDof end, set = function (v) St.photoDof = v end, readback = function () return St.photoDof end })
R.state('aperture', 'Aperture', { kind = 'knob', min = 1.4, max = 16, step = 0.1, default = 2.8, fmt = function (v) return string.format('f/%.1f', v) end,
  get = function () return St.aperture end, set = function (v) St.aperture = v end, readback = function () return St.aperture end })
R.state('focus', 'Focus', { kind = 'knob', min = 1, max = 100, step = 1, default = 12, fmt = R.fmt.unit(' m'),
  get = function () return St.focus end, set = function (v) St.focus = v end, readback = function () return St.focus end })
R.state('bokeh', 'Bokeh', { kind = 'knob', min = 0, max = 100, step = 1, default = 40, fmt = R.fmt.pct,
  get = function () return St.bokeh end, set = function (v) St.bokeh = v end, readback = function () return St.bokeh end })
R.action('selftest', 'Run self-test', function () verify.selftest(env) end, { key = 'writes apps/lua/Lumicorsa/selftest.log' })
R.action('proof', 'Capture proof screenshots', function () verify.proof(env) end, { key = 'before/after screenshots' })
R.action('soak', 'Start 10-minute soak test', function () verify.soak(env) end, { key = 'writes apps/lua/Lumicorsa/soak.log' })

local built = tabs.build(R, {
  skyLabel = function () return sky.label(), T.C.blue end,
  reshadeLabel = function () return system.reshadeState(), T.C.text2 end,
  reshadeNote = function () return system.status ~= '' and system.status or 'Optional. Lumicorsa runs fully without it.' end,
  verifyNote = function ()
    if verify.running then return 'Running: ' .. verify.running .. '…' end
    return 'Self-test: ' .. verify.summary.selftest .. '.  Proof: ' .. verify.summary.proof .. '.  Soak: ' .. verify.summary.soak .. '.'
  end,
})
local paletteEntries = palette.entries(R, tabs.LABELS)

-- ---------------------------------------------------------------------------------------------- environment for UI + verify
local otherApp = nil
local function detectOtherGrading()
  local ok, list = pcall(ac.getAppWindows)
  otherApp = nil
  if ok and type(list) == 'table' then
    for _, w in ipairs(list) do
      local n = type(w.name) == 'string' and w.name or ''
      if n:find('^IMGUI_LUA_DreamRealism') or n:find('^IMGUI_LUA_DreamPresetManager') or n:find('^IMGUI_LUA_ExilitayFX') then otherApp = n end
    end
  end
end
detectOtherGrading()

env = {
  store = St, values = state.values, telemetry = telemetry, R = R, version = VERSION, dt = 0.016,
  dotgrid = 'brand/dotgrid.png',
  glass = function () return look.glass(frameNo) end,
  refresh = function () return tonumber(C.get('ac:video', 'REFRESH', 'VALUE', 60)) or 60 end,
  sunElevation = weather.sunElevation,
  paletteEntries = paletteEntries,
  drawClusterPreview = function (p, k) safe(cluster.draw, St, T, p, k, os.preciseClock()) end,
  running = function ()
    local up, upOn = graphics.runningUpscaler()
    local rs = ac.getSim().renderSize
    local n = 0
    for _ in pairs(look.active) do n = n + 1 end
    local server = ac.getServerName()
    local rsState = system.reshadeState()
    local sk = sky.detect()
    return {
      { 'Upscaler', up, upOn and T.C.ok or T.C.faint },
      { 'Render', rs and string.format('%d × %d', rs.x, rs.y) or '?', T.C.text2 },
      { 'Shaders', St.master and string.format('%d active', n) or 'Vanilla', St.master and T.C.ok or T.C.faint },
      { 'Sky', sk.pure and sk.sol and 'Pure + Sol' or sk.pure and 'Pure' or sk.sol and 'Sol' or 'Default', T.C.blue },
      { 'Server', server or 'Offline', server and T.C.yellow or T.C.faint },
      { 'ReShade', rsState == 'not installed' and 'Not installed' or 'Installed', rsState == 'not installed' and T.C.faint or T.C.ok },
    }
  end,
  presetCost = function () return nil end,
  tierFps = graphics.tierFps,
  lookCpu = function () return lookCpu end,
}
env.ringItems = ring.items({ store = St, togglePreset = function (name)
  if St.preset == name and St.blend == 0 then state.applyPreset(env.lastPreset or 'Photoreal') else env.lastPreset = St.preset; state.applyPreset(name) end
end })

-- verification hooks
env.presets = state.PRESETS
env.applyPreset = state.applyPreset
env.setMaster = function (v) St.master = v end
env.setHud = function (on, units) St.hudOn = on; if units then St.units = units end end
env.openRing = function (v) local w = window(DASH); if w then w:setVisible(true) end; dashboard.ringOpen = v; if v then ring.reset() end end
env.openPalette = function (v) local w = window(DASH); if w then w:setVisible(true) end; if v then palette.show() else palette.hide() end end
env.toggleDashboard = function () local w = window(DASH); if w then w:setVisible(not w:visible()) end end
env.prepare = function ()
  local saved = {}
  for _, k in ipairs({ 'master', 'light', 'atmos', 'detail', 'lens', 'neural', 'shafts', 'flare', 'ao', 'mist', 'adapt', 'budgetOn', 'hudOn', 'hudViews', 'overlay', 'autoLook' }) do saved[k] = St[k] end
  local savedValues = {}
  for k, v in pairs(state.values) do savedValues[k] = v end
  St.master, St.light, St.atmos, St.detail, St.lens, St.neural = true, true, true, true, true, true
  St.shafts, St.flare, St.ao, St.mist, St.budgetOn, St.hudOn = true, true, true, true, false, true
  St.autoLook, St.hudViews = false, 'All views'               -- nothing may change values behind the test's back
  if St.adapt == 0 then St.adapt = 40 end
  local hw = window(HUD); if hw then hw:setVisible(true) end
  env.ignoreConflict = true
  return function ()
    for k, v in pairs(saved) do St[k] = v end
    for k, v in pairs(savedValues) do state.values[k] = v end
    env.ignoreConflict = false
  end
end
env.startMeasure = function ()
  St.master = true
  telemetry.startMeasure(function (ok) St.measured = ok and JSON.stringify(telemetry.costs) or St.measured end)
end
do local ok, t = pcall(JSON.parse, St.measured or ''); if ok and type(t) == 'table' then for k, v in pairs(t) do telemetry.costs[k] = v end end end

-- modals
env.smoothMotionModal = function ()
  dashboard.modal = { title = 'NVIDIA Smooth Motion', height = 330, buttons = { { label = 'Done' } },
    body = function (p, w)
      T.wrapped('Smooth Motion is a frame-generation setting in the NVIDIA driver for RTX 40 and 50 cards. It runs outside the game, so Lumicorsa can’t switch it on and doesn’t fake frame generation.\n\n'
        .. '1. Open the NVIDIA App › Graphics › Program settings.\n2. Add Assetto Corsa (acs.exe).\n3. Turn on Smooth Motion, then restart Assetto Corsa.\n\n'
        .. 'Works best with a frame cap at half your refresh rate.', p, p + vec2(w, 200), 14, T.C.text2)
    end }
end
local fovCalc = { diag = 27, dist = 70 }
env.fovModal = function ()
  local dDiag = { id = 'fov_diag', label = 'Screen diagonal', min = 13, max = 65, step = 1, fmt = R.fmt.unit('"'),
    get = function () return fovCalc.diag end, set = function (v) fovCalc.diag = v end }
  local dDist = { id = 'fov_dist', label = 'Eyes to screen', min = 30, max = 150, step = 1, fmt = R.fmt.unit(' cm'),
    get = function () return fovCalc.dist end, set = function (v) fovCalc.dist = v end }
  dashboard.modal = { title = 'Field of view from your screen', height = 330,
    buttons = { { label = 'Cancel' }, { label = 'Apply', on = function () camera.setFov(camera.fovFromScreen(fovCalc.diag, fovCalc.dist)) end } },
    body = function (p, w, dt)
      local ctx = { dt = dt, mode = 'Advanced' }
      W.slider.draw({ def = dDiag }, p, w, ctx)
      W.slider.draw({ def = dDist }, p + vec2(0, 60), w, ctx)
      T.text(string.format('Cockpit field of view: %.1f°', camera.fovFromScreen(fovCalc.diag, fovCalc.dist)), p + vec2(0, 130), 16, T.C.amber, 'medium')
    end }
end
env.reshadeModal = function ()
  system.status = ''
  dashboard.modal = { title = 'Install ReShade?', height = 300,
    buttons = { { label = 'Close' }, { label = 'Install', on = function () system.installReshade(); return true end } },
    body = function (p, w)
      T.wrapped('Downloads the official ReShade add-on build from reshade.me and installs it as dxgi.dll next to acs.exe. '
        .. 'Lumicorsa runs fully without it. Uninstall only removes a ReShade that Lumicorsa installed.\n\nCurrent state: '
        .. system.reshadeState() .. (system.status ~= '' and ('\n\n' .. system.status) or ''), p, p + vec2(w, 170), 14, T.C.text2)
    end }
end

-- ---------------------------------------------------------------------------------------------- hotkeys
local keyDash = ac.ControlButton('__APP_LUMICORSA_DASHBOARD', { keyboard = { key = ui.KeyIndex.P, alt = true } })
local keyVanilla = ac.ControlButton('__APP_LUMICORSA_VANILLA', { keyboard = { key = ui.KeyIndex.O, alt = true } })
local keyHud = ac.ControlButton('__APP_LUMICORSA_HUD', { keyboard = { key = ui.KeyIndex.H, alt = true } })
local keyRing = ac.ControlButton('__APP_LUMICORSA_RING', { keyboard = { key = ui.KeyIndex.Q } })
local keyPalette = ac.ControlButton('__APP_LUMICORSA_SEARCH', { keyboard = { key = ui.KeyIndex.K, ctrl = true } })
keyDash:onPressed(function () env.toggleDashboard() end)
keyVanilla:onPressed(function () St.master = not St.master end)
keyHud:onPressed(function () St.hudOn = not St.hudOn end)
keyPalette:onPressed(function () local w = window(DASH); if w then w:setVisible(true) end; palette.show() end)

-- ---------------------------------------------------------------------------------------------- per-frame work (first UI callback)
local ringHeld, ringHover = false, nil
local envTimer, carId = 0, nil

local function frame(mode)
  frameNo = frameNo + 1
  local dt = ac.getUI().dt or 0.016
  env.dt = dt
  telemetry.frame(dt)
  envTimer = envTimer + dt
  if envTimer > 2 then
    envTimer = 0
    detectOtherGrading()
    graphics.recordTierFps(telemetry.fps(), St)
    if St.autoLook then local pick = state.autoLookPick(os.preciseClock()); if pick ~= St.preset then state.applyPreset(pick) end end
    local car = ac.getCar(0)
    local id = car and car:id()
    if id ~= carId then carId = id; camera.restoreChase() end
    local hw = window(HUD)
    if hw and St.hudOn and not hw:visible() then hw:setVisible(true) end
  end

  -- the look (with the GPU budget, and the cost measurement when it runs)
  local blocked = ac.getSim().isVRMode or ac.getSim().isHDR
  local m = telemetry.measuring and telemetry.measureStep(dt, look.active) or nil
  if St.master and not blocked and not (m and m.all) then
    local off = system.budgetOff(St)
    if m then for k in pairs(m) do off[k] = true end end
    local t0 = os.preciseClock()
    look.render(state.frameState(otherApp ~= nil and not env.ignoreConflict, off, dt))
    lookCpu = (os.preciseClock() - t0) * 1000
  else
    lookCpu = 0
  end

  -- the analog cluster: drawn here every game frame, at the HUD window's position. 2.0.0 drew it inside the window,
  -- so it vanished whenever AC or another app hid app windows, and on every frame its textures weren't loaded yet.
  if mode == 'game' and cluster.visibleInView(St) then
    telemetry.time('hud', cluster.draw, St, T, cluster.origin(St), cluster.scale(St), os.preciseClock())
    lastHud = frameNo
  end

  -- quick ring while Q is held (released: fire the hovered item)
  if keyRing:down() and mode == 'game' then
    if not ringHeld then ringHeld = true; ring.reset() end
    ringHover = ring.draw(env.ringItems, ac.getUI().windowSize / 2, ui.mousePos(), dt, false)
  elseif ringHeld then
    ringHeld = false
    if ringHover then env.ringItems[ringHover].flip() end
    ringHover = nil
  end

  -- performance overlay
  if St.overlay then
    local p = vec2(ac.getUI().windowSize.x - 190, 16)
    ui.drawRectFilled(p, p + vec2(174, 58), rgbm(0, 0, 0, 0.6), 10)
    T.mono(string.format('%d fps', math.floor(telemetry.fps() + 0.5)), p + vec2(12, 8), 15, T.C.text)
    local low = telemetry.low1()
    T.mono(string.format('%.1f ms  1%% low %s', telemetry.frameTime(), low and math.floor(low) or '…'), p + vec2(12, 32), 12, T.C.text2)
    lastOverlay = frameNo
  end

  verify.update(dt)
  C.flush()
end

ui.onExclusiveHUD(function (mode) safe(frame, mode) end)

-- ---------------------------------------------------------------------------------------------- windows
function script.windowDashboard(dt)
  safe(telemetry.time, 'ui', dashboard.draw, env, built)
end

-- The HUD window is only a handle: drag it to move the cluster (which is drawn in the first UI callback above).
function script.windowHud(dt)
  if ui.windowHovered() then
    ui.drawRect(vec2(1, 1), ui.windowSize() - 1, rgbm(1, 0.71, 0.28, 0.6), 12, nil, 1.5)
  end
  cluster.track(St)
end

-- ---------------------------------------------------------------------------------------------- start-up
cluster.sessionStart(os.preciseClock())
ac.onSessionStart(function () cluster.sessionStart(os.preciseClock()) end)
setTimeout(function () cluster.place(St); camera.restoreChase() end, 0.5)
ac.onRelease(function () C.flush(true); look.release() end)
verify.__env = env
verify.autorun(env)
