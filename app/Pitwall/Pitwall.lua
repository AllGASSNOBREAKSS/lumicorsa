--[[
  PITWALL — all-in-one graphics, weather and settings for Assetto Corsa. Native to Custom Shaders Patch.
  Copyright (c) 2026 Pitwall contributors. MIT License.

  Needs only Content Manager + CSP. One panel for Pitwall's own look (post stack, neural detail, realism add-ons),
  Pure, weather, CSP graphics, post-processing filters, audio and AC video settings. Alt+P opens it, Alt+O bypasses
  Pitwall's look instantly.
]]

local VERSION = '1.0.0'
local pipeline = require('src/pipeline')
local S = require('src/settings')
local K = require('src/ui_kit')
local pages = require('src/pages')
local C = K.C

-- ---------------------------------------------------------------------------------------------- presets
-- Every PL_* key maps 1:1 to a value of shaders/final.hlsl.
local PRESETS = {
  { id = 'photoreal', name = 'Photoreal', neural = true, nr_intensity = 0.60,
    v = { PL_Exposure = 0.0, PL_HighlightRecover = 0.55, PL_BloomIntensity = 0.18, PL_Halation = 0.15, PL_FilmicStrength = 0.75,
          PL_Contrast = 0.08, PL_Saturation = -0.04, PL_Vibrance = 0.12, PL_HazeDensity = 0.30, PL_Clarity = 0.22, PL_Sharpen = 0.35,
          PL_ChromaAb = 0.10, PL_Vignette = 0.25, PL_Grain = 0.08, PL_Temperature = 0.0, PL_Tint = 0.0 } },
  { id = 'midnight', name = 'Midnight Run', neural = true, nr_intensity = 0.70,
    v = { PL_Exposure = 0.25, PL_HighlightRecover = 0.80, PL_BloomIntensity = 0.38, PL_Halation = 0.55, PL_FilmicStrength = 0.90,
          PL_Contrast = 0.12, PL_Saturation = 0.02, PL_Vibrance = 0.18, PL_HazeDensity = 0.18, PL_Clarity = 0.18, PL_Sharpen = 0.30,
          PL_ChromaAb = 0.18, PL_Vignette = 0.40, PL_Grain = 0.14, PL_Temperature = -0.15, PL_Tint = 0.05 } },
  { id = 'golden', name = 'Golden Hour', neural = true, nr_intensity = 0.55,
    v = { PL_Exposure = 0.10, PL_HighlightRecover = 0.65, PL_BloomIntensity = 0.30, PL_Halation = 0.35, PL_FilmicStrength = 0.85,
          PL_Contrast = 0.06, PL_Saturation = 0.04, PL_Vibrance = 0.20, PL_HazeDensity = 0.45, PL_Clarity = 0.15, PL_Sharpen = 0.28,
          PL_ChromaAb = 0.12, PL_Vignette = 0.35, PL_Grain = 0.10, PL_Temperature = 0.35, PL_Tint = 0.04 } },
  { id = 'broadcast', name = 'Broadcast', neural = true, nr_intensity = 0.45,
    v = { PL_Exposure = 0.0, PL_HighlightRecover = 0.45, PL_BloomIntensity = 0.10, PL_Halation = 0.0, PL_FilmicStrength = 0.60,
          PL_Contrast = 0.14, PL_Saturation = 0.08, PL_Vibrance = 0.10, PL_HazeDensity = 0.20, PL_Clarity = 0.30, PL_Sharpen = 0.45,
          PL_ChromaAb = 0.0, PL_Vignette = 0.10, PL_Grain = 0.0, PL_Temperature = 0.0, PL_Tint = 0.0 } },
  { id = 'perf', name = 'Performance', neural = false, nr_intensity = 0.0,
    v = { PL_Exposure = 0.0, PL_HighlightRecover = 0.40, PL_BloomIntensity = 0.12, PL_Halation = 0.0, PL_FilmicStrength = 0.60,
          PL_Contrast = 0.06, PL_Saturation = 0.0, PL_Vibrance = 0.08, PL_HazeDensity = 0.0, PL_Clarity = 0.0, PL_Sharpen = 0.35,
          PL_ChromaAb = 0.0, PL_Vignette = 0.15, PL_Grain = 0.0, PL_Temperature = 0.0, PL_Tint = 0.0 },
    techniques = { light = true, atmos = false, detail = true, lens = false } },
}
local EXTRA_DEFAULTS = { PL_Shafts = 0.5, PL_Flare = 0.3, PL_AO = 0.5, PL_Dof = 0.5, PL_AerialDesat = 0.35 }

-- ---------------------------------------------------------------------------------------------- persistent state
local store = ac.storage({
  enabled = true, preset = 'photoreal',
  neural = true, nr_intensity = 0.60,
  light = true, atmos = true, detail = true, lens = true,
  shafts = true, flare = false, ao = true, dof = 0,
  split = false, mix = 1.0, ignore_conflict = false,
  page = 'look', gfxTab = 'upscale', fxTab = 'light', timeSpeed = 1,
})
local values = {}

local tweaks = ac.storage({ json = '' }, 'tweaks_')
local function saveTweaks() tweaks.json = JSON.stringify(values) end

local function loadPreset(p, keepToggles)
  for k, v in pairs(p.v) do values[k] = v end
  store.preset, store.neural, store.nr_intensity = p.id, p.neural, p.nr_intensity
  if not keepToggles then
    local t = p.techniques or { light = true, atmos = true, detail = true, lens = true }
    for k, v in pairs(t) do store[k] = v end
  end
end

local function presetById(id)
  for _, p in ipairs(PRESETS) do if p.id == id then return p end end
  return PRESETS[1]
end

loadPreset(presetById(store.preset), true)
do
  local ok, t = pcall(JSON.parse, tweaks.json or '')
  if ok and type(t) == 'table' then for k, v in pairs(t) do if type(v) == 'number' then values[k] = v end end end
end
for k, v in pairs(EXTRA_DEFAULTS) do if values[k] == nil then values[k] = v end end

-- ---------------------------------------------------------------------------------------------- live status
local status = { shaders = 'starting', shadersOk = false, upscaler = 'off', upscalerOn = false, conflict = nil,
  gpuOn = nil, gpuOff = nil, error = nil, notice = nil }

local function refreshEnvironment()
  status.upscaler, status.upscalerOn = pipeline.upscaler()
  status.conflict = pipeline.otherFilter()
  local old = ac.accessAppWindow and ac.accessAppWindow('IMGUI_LUA_Photolap_main')
  status.notice = old and 'The old Photolap app is still installed: delete apps/lua/Photolap so only Pitwall draws.' or nil
end
refreshEnvironment()
setInterval(refreshEnvironment, 2, 'pitwall_env')
setInterval(function () S.flush() end, 0.1, 'pitwall_flush')

local function unsupported()
  local sim = ac.getSim()
  if sim.isVRMode then return 'VR not supported yet' end
  if sim.isHDR then return 'HDR output not supported yet' end
  return nil
end

local function trackGpu(engaged)
  local ms = pipeline.gpuFrameMs()
  if not ms then return end
  local key = engaged and 'gpuOn' or 'gpuOff'
  status[key] = status[key] and math.applyLag(status[key], ms, 0.97, ac.getUI().dt) or ms
end

-- ---------------------------------------------------------------------------------------------- the frame
-- First UI callback of the frame: draws over the finished scene, under the HUD and all app windows.
local frameValues = {}
local frameState = { values = frameValues }

ui.onExclusiveHUD(function (mode)
  if status.error then return end
  local blocked = unsupported()
  if blocked then status.shaders, status.shadersOk = blocked, false; return end
  if not store.enabled then
    status.shaders, status.shadersOk = 'bypassed', false
    trackGpu(false)
    return
  end
  for k, x in pairs(values) do frameValues[k] = x end
  frameValues.PL_Mix = store.mix
  local sim = ac.getSim()
  local fs = frameState
  fs.light, fs.atmos, fs.detail, fs.lens = store.light, store.atmos, store.detail, store.lens
  fs.neural, fs.nrGain = store.neural, store.nr_intensity * 3.5
  fs.shafts, fs.flare, fs.ao = store.shafts, store.flare, store.ao
  fs.dof = store.dof == 2 or (store.dof == 1 and sim.isReplayActive)
  fs.split = store.split
  fs.conflict = status.conflict ~= nil and not store.ignore_conflict
  local ok, ready = pcall(pipeline.render, fs)
  if not ok then
    status.error = tostring(ready)
    status.shaders, status.shadersOk = 'error', false
    ac.error('Pitwall: ' .. status.error)
    return
  end
  status.shaders, status.shadersOk = ready and 'running' or 'compiling…', ready
  if ready then trackGpu(true) end
end)

ac.onRelease(function () S.flush(true); pipeline.release() end)

-- ---------------------------------------------------------------------------------------------- hotkeys
local WINDOW = 'IMGUI_LUA_Pitwall_main'
local toggleKey = ac.ControlButton('__APP_PITWALL_TOGGLE', { keyboard = { key = ui.KeyIndex.P, alt = true } })
toggleKey:onPressed(function ()
  pcall(function ()
    local w = ac.accessAppWindow(WINDOW)
    if w then w:setVisible(not w:visible()) end
  end)
end)
local masterKey = ac.ControlButton('__APP_PITWALL_MASTER', { keyboard = { key = ui.KeyIndex.O, alt = true } })
masterKey:onPressed(function () store.enabled = not store.enabled end)

-- ---------------------------------------------------------------------------------------------- window
local scroll = {}
local glassShader = pipeline.shader('glass')
local ctx = {
  store = store, values = values, status = status, presets = PRESETS, version = VERSION,
  loadPreset = function (p) loadPreset(p, false); saveTweaks() end,
  setValue = function (k, v) values[k] = v; saveTweaks() end,
  resetScroll = function () scroll[store.page] = 0 end,
}

local function header(size)
  ui.drawImage('icon.png', vec2(18, 16), vec2(54, 52))
  K.text('PITWALL', vec2(64, 15), 21, C.white, 'bold')
  K.text('All-in-one for Assetto Corsa', vec2(65, 39), 11.5, C.muted, 'regular')

  -- engaged pill
  local on = store.enabled
  local label = on and 'ENGAGED' or 'BYPASSED'
  local m = K.measure(label, 11, 'bold')
  local pw = m.x + 40
  local pp = vec2(size.x - 58 - pw, 21)
  local clicked, hovered = K.hit('pw_master', pp, vec2(pw, 26))
  ui.drawRectFilled(pp, pp + vec2(pw, 26), on and C.blue or rgbm(1, 1, 1, hovered and 0.16 or 0.1), 13)
  ui.drawCircleFilled(pp + vec2(14, 13), 4, on and C.black or C.muted, 12)
  K.text(label, pp + vec2(25, 5.5), 11, on and C.black or C.white, 'bold')
  if clicked then store.enabled = not on end

  -- close
  local cp = vec2(size.x - 44, 20)
  local cClicked, cHovered = K.hit('pw_close', cp, vec2(28, 28))
  ui.drawRectFilled(cp, cp + vec2(28, 28), rgbm(1, 1, 1, cHovered and 0.14 or 0.06), 8)
  ui.drawIcon(ui.Icons.Cancel, cp + vec2(8, 8), cp + vec2(20, 20), cHovered and C.red or C.muted)
  if cClicked then pcall(function () ac.accessAppWindow(WINDOW):setVisible(false) end) end

  -- drag handle over the title area
  local _, _, dragging = K.hit('pw_drag', vec2(0, 0), vec2(pp.x - 8, 66))
  if dragging then
    pcall(function ()
      local w = ac.accessAppWindow(WINDOW)
      w:move(w:position() + ui.mouseDelta())
    end)
  end
  ui.drawLine(vec2(16, 68), vec2(size.x - 16, 68), C.line, 1)
end

local function nav(size)
  local y = 80
  for _, item in ipairs(pages.nav) do
    local p = vec2(12, y)
    local active = store.page == item.id
    local clicked, hovered = K.hit('pw_nav_' .. item.id, p, vec2(64, 60))
    if active then
      ui.drawRectFilled(p, p + vec2(64, 60), rgbm(1, 1, 1, 0.09), 12)
      ui.drawRectFilled(vec2(p.x, p.y + 16), vec2(p.x + 3, p.y + 44), item.color, 2)
    elseif hovered then
      ui.drawRectFilled(p, p + vec2(64, 60), rgbm(1, 1, 1, 0.045), 12)
    end
    ui.drawIcon(item.icon, p + vec2(21, 9), p + vec2(43, 31), (active or hovered) and item.color or K.alpha(item.color, 0.7))
    local m = K.measure(item.label, 10.5, 'medium')
    K.text(item.label, p + vec2((64 - m.x) / 2, 37), 10.5, active and C.white or C.muted, 'medium')
    if clicked then store.page = item.id end
    y = y + 64
  end
end

local function footer(size)
  local y = size.y - 34
  ui.drawLine(vec2(16, y - 8), vec2(size.x - 16, y - 8), C.line, 1)
  local dot = status.shadersOk and C.green or (store.enabled and C.orange or C.muted)
  ui.drawCircleFilled(vec2(22, y + 8), 4, dot, 12)
  K.text('Shaders ' .. status.shaders, vec2(32, y), 11.5, C.white, 'medium')
  local right = 'Upscaler ' .. status.upscaler .. '   ·   Alt+P  Alt+O'
  local m = K.measure(right, 11.5, 'regular')
  K.text(right, vec2(size.x - 18 - m.x, y), 11.5, C.muted, 'regular')
end

function script.windowMain(dt)
  local size = ui.windowSize()
  K.glass(size, glassShader)
  header(size)
  nav(size)

  local rect = vec4(92, 80, size.x - 92 - 16, size.y - 80 - 50)
  local builder = pages[store.page] or pages.look
  local ok, cards = pcall(builder, ctx)
  if not ok then cards = { { title = 'Error', icon = ui.Icons.Warning, color = C.red, rows = { { kind = 'note', text = tostring(cards), color = C.red } } } } end
  local sc = scroll[store.page] or 0
  local contentH = K.page(cards, rect, sc, store.page)
  local maxScroll = math.max(contentH - rect.w, 0)
  local mouse = ui.mouseLocalPos()
  if ui.windowHovered() and mouse.x > rect.x and mouse.y > rect.y and mouse.y < rect.y + rect.w then
    sc = sc - ui.mouseWheel() * 60
  end
  scroll[store.page] = math.min(math.max(sc, 0), maxScroll)
  if maxScroll > 0 and scroll[store.page] < maxScroll - 1 then   -- soft hint that there's more below (no scrollbar)
    ui.drawRectFilledMultiColor(vec2(rect.x, rect.y + rect.w - 28), vec2(rect.x + rect.z, rect.y + rect.w),
      rgbm(0.035, 0.05, 0.085, 0), rgbm(0.035, 0.05, 0.085, 0), rgbm(0.035, 0.05, 0.085, 0.9), rgbm(0.035, 0.05, 0.085, 0.9))
  end

  footer(size)
  S.flush()
end
