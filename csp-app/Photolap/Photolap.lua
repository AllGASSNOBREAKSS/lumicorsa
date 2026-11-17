--[[
  PHOTOLAP — photoreal post stack for Assetto Corsa, native to Custom Shaders Patch.
  Copyright (c) 2026 Photolap contributors. MIT License.

  Needs only Content Manager + CSP. The panel drives the shaders directly (see pl_pipeline.lua): no ReShade,
  no add-on DLL, no files exchanged between processes. Open it from the CSP apps bar or with Alt+P; Alt+O bypasses
  everything instantly, even with the window closed.
]]

local pipeline = require('pl_pipeline')

-- ---------------------------------------------------------------------------------------------- palette
local C = {
  bg      = rgbm(0.043, 0.047, 0.058, 0.96),
  card    = rgbm(0.075, 0.082, 0.100, 1),
  line    = rgbm(1, 1, 1, 0.07),
  text    = rgbm(0.92, 0.93, 0.95, 1),
  muted   = rgbm(0.55, 0.57, 0.63, 1),
  accent  = rgbm(1.00, 0.24, 0.36, 1),   -- "brake-light" red
  accent2 = rgbm(0.25, 0.85, 1.00, 1),   -- neural cyan
  ok      = rgbm(0.35, 0.90, 0.55, 1),
  warn    = rgbm(1.00, 0.70, 0.25, 1),
}

-- ---------------------------------------------------------------------------------------------- presets
-- Every PL_* key maps 1:1 to a value of shaders/final.hlsl (and the legacy ReShade Photolap.fx).
local PRESETS = {
  { id = 'photoreal', name = 'Photoreal', hint = 'Daylight, camera-true',
    neural = true, nr_intensity = 0.60,
    v = { PL_Exposure = 0.0, PL_HighlightRecover = 0.55, PL_BloomIntensity = 0.18, PL_Halation = 0.15, PL_FilmicStrength = 0.75,
          PL_Contrast = 0.08, PL_Saturation = -0.04, PL_Vibrance = 0.12, PL_HazeDensity = 0.30, PL_Clarity = 0.22, PL_Sharpen = 0.35,
          PL_ChromaAb = 0.10, PL_Vignette = 0.25, PL_Grain = 0.08, PL_Temperature = 0.0, PL_Tint = 0.0 } },
  { id = 'midnight', name = 'Midnight Run', hint = 'Night highway / tandem',
    neural = true, nr_intensity = 0.70,
    v = { PL_Exposure = 0.25, PL_HighlightRecover = 0.80, PL_BloomIntensity = 0.38, PL_Halation = 0.55, PL_FilmicStrength = 0.90,
          PL_Contrast = 0.12, PL_Saturation = 0.02, PL_Vibrance = 0.18, PL_HazeDensity = 0.18, PL_Clarity = 0.18, PL_Sharpen = 0.30,
          PL_ChromaAb = 0.18, PL_Vignette = 0.40, PL_Grain = 0.14, PL_Temperature = -0.15, PL_Tint = 0.05 } },
  { id = 'golden', name = 'Golden Hour', hint = 'Warm, soft, cinematic',
    neural = true, nr_intensity = 0.55,
    v = { PL_Exposure = 0.10, PL_HighlightRecover = 0.65, PL_BloomIntensity = 0.30, PL_Halation = 0.35, PL_FilmicStrength = 0.85,
          PL_Contrast = 0.06, PL_Saturation = 0.04, PL_Vibrance = 0.20, PL_HazeDensity = 0.45, PL_Clarity = 0.15, PL_Sharpen = 0.28,
          PL_ChromaAb = 0.12, PL_Vignette = 0.35, PL_Grain = 0.10, PL_Temperature = 0.35, PL_Tint = 0.04 } },
  { id = 'broadcast', name = 'Broadcast', hint = 'TV-camera clean, punchy',
    neural = true, nr_intensity = 0.45,
    v = { PL_Exposure = 0.0, PL_HighlightRecover = 0.45, PL_BloomIntensity = 0.10, PL_Halation = 0.0, PL_FilmicStrength = 0.60,
          PL_Contrast = 0.14, PL_Saturation = 0.08, PL_Vibrance = 0.10, PL_HazeDensity = 0.20, PL_Clarity = 0.30, PL_Sharpen = 0.45,
          PL_ChromaAb = 0.0, PL_Vignette = 0.10, PL_Grain = 0.0, PL_Temperature = 0.0, PL_Tint = 0.0 } },
  { id = 'perf', name = 'Performance', hint = 'Cheapest, no neural',
    neural = false, nr_intensity = 0.0,
    v = { PL_Exposure = 0.0, PL_HighlightRecover = 0.40, PL_BloomIntensity = 0.12, PL_Halation = 0.0, PL_FilmicStrength = 0.60,
          PL_Contrast = 0.06, PL_Saturation = 0.0, PL_Vibrance = 0.08, PL_HazeDensity = 0.0, PL_Clarity = 0.0, PL_Sharpen = 0.35,
          PL_ChromaAb = 0.0, PL_Vignette = 0.15, PL_Grain = 0.0, PL_Temperature = 0.0, PL_Tint = 0.0 },
    techniques = { light = true, atmos = false, detail = true, lens = false } },
}

-- ---------------------------------------------------------------------------------------------- persistent state
local store = ac.storage({
  enabled = true, preset = 'photoreal',
  neural = true, nr_intensity = 0.60,
  light = true, atmos = true, detail = true, lens = true,
  split = false, mix = 1.0, advanced = false,
  ignore_conflict = false,
})
local values = {}   -- current PL_* values (seeded from preset, then user-edited)

local function presetById(id)
  for _, p in ipairs(PRESETS) do if p.id == id then return p end end
  return PRESETS[1]
end

local function loadPreset(p, keepUserToggles)
  for k, v in pairs(p.v) do values[k] = v end
  store.preset = p.id
  store.neural = p.neural
  store.nr_intensity = p.nr_intensity
  if p.techniques and not keepUserToggles then
    for k, v in pairs(p.techniques) do store[k] = v end
  elseif not keepUserToggles then
    store.light, store.atmos, store.detail, store.lens = true, true, true, true
  end
end

-- user tweaks to sliders are remembered in a separate storage table
local tweaks = ac.storage({ json = '' }, 'tweaks_')
local function saveTweaks() tweaks.json = JSON.stringify(values) end
local function loadTweaks()
  local ok, t = pcall(JSON.parse, tweaks.json or '')
  if ok and type(t) == 'table' then for k, v in pairs(t) do if type(v) == 'number' then values[k] = v end end end
end

loadPreset(presetById(store.preset), true)
loadTweaks()

-- ---------------------------------------------------------------------------------------------- live status
local status = {
  shaders = 'starting', shadersOk = false,
  upscaler = 'off', upscalerOn = false,
  conflict = nil,
  gpuOn = nil, gpuOff = nil,   -- smoothed GPU frame time engaged / bypassed (ms)
  error = nil,
}

local function refreshEnvironment()
  status.upscaler, status.upscalerOn = pipeline.upscaler()
  status.conflict = pipeline.otherFilter()
end
refreshEnvironment()
setInterval(refreshEnvironment, 2, 'photolap_env')

local function unsupported()
  local sim = ac.getSim()
  if sim.isVRMode then return 'VR is not supported yet' end
  if sim.isHDR then return 'HDR output is not supported yet' end
  return nil
end

local function trackGpu(engaged)
  local ms = pipeline.gpuFrameMs()
  if not ms then return end
  local key = engaged and 'gpuOn' or 'gpuOff'
  status[key] = status[key] and math.applyLag(status[key], ms, 0.97, ac.getUI().dt) or ms
end

-- ---------------------------------------------------------------------------------------------- the frame
local frameValues = {}
local frameState = { values = frameValues }

-- First UI callback of the frame: draws over the finished scene, under the HUD and all app windows.
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
  frameState.light, frameState.atmos, frameState.detail, frameState.lens = store.light, store.atmos, store.detail, store.lens
  frameState.neural, frameState.nrGain = store.neural, store.nr_intensity * 3.5
  frameState.split = store.split
  frameState.conflict = status.conflict ~= nil and not store.ignore_conflict
  local ok, ready = pcall(pipeline.render, frameState)
  if not ok then
    status.error = tostring(ready)
    status.shaders, status.shadersOk = 'error', false
    ac.error('Photolap: ' .. status.error)
    return
  end
  status.shaders, status.shadersOk = ready and 'running' or 'compiling…', ready
  if ready then trackGpu(true) end
end)

ac.onRelease(function () pipeline.release() end)

-- ---------------------------------------------------------------------------------------------- hotkeys
-- Alt+P toggles this window (rebind in CSP > Controls).
local toggleKey = ac.ControlButton('__APP_PHOTOLAP_TOGGLE', { keyboard = { key = ui.KeyIndex.P, alt = true } })
toggleKey:onPressed(function ()
  pcall(function ()
    local w = ac.accessAppWindow('IMGUI_LUA_Photolap_main')
    if w then w:setVisible(not w:visible()) end
  end)
end)

-- Master on/off that works even with the window closed: Alt+O.
local masterKey = ac.ControlButton('__APP_PHOTOLAP_MASTER', { keyboard = { key = ui.KeyIndex.O, alt = true } })
masterKey:onPressed(function () store.enabled = not store.enabled end)

-- ---------------------------------------------------------------------------------------------- widgets
local function section(title, color)
  ui.offsetCursorY(10)
  ui.pushFont(ui.Font.Small)
  ui.textColored(title, color or C.muted)
  ui.popFont()
  local p = ui.getCursor()
  ui.drawLine(p, p + vec2(ui.availableSpaceX(), 0), C.line, 1)
  ui.offsetCursorY(6)
end

-- Pill toggle: returns true if clicked.
local function pill(id, label, on, color, w)
  w = w or ui.availableSpaceX()
  local h = 30
  local p = ui.getCursor()
  local clicked = ui.invisibleButton(id, vec2(w, h))
  local hovered = ui.itemHovered()
  ui.drawRectFilled(p, p + vec2(w, h), hovered and rgbm(1, 1, 1, 0.06) or C.card, 6)
  local tx = p.x + w - 46
  ui.drawRectFilled(vec2(tx, p.y + 8), vec2(tx + 34, p.y + 22), on and color or rgbm(1, 1, 1, 0.12), 7)
  ui.drawCircleFilled(vec2(on and tx + 27 or tx + 7, p.y + 15), 5, on and rgbm(0, 0, 0, 0.85) or C.muted, 16)
  ui.drawText(label, p + vec2(12, 7), on and C.text or C.muted)
  return clicked
end

local function sliderRow(label, key, lo, hi, fmt)
  ui.setNextItemWidth(ui.availableSpaceX())
  local v, changed = ui.slider('##' .. key, values[key] or 0, lo, hi, label .. ': ' .. (fmt or '%.2f'))
  if changed then values[key] = v; saveTweaks() end
end

local function storeSlider(label, key, lo, hi, fmt)
  ui.setNextItemWidth(ui.availableSpaceX())
  local v, changed = ui.slider('##s_' .. key, store[key], lo, hi, label .. ': ' .. (fmt or '%.2f'))
  if changed then store[key] = v end
end

local function row(label, value, color)
  ui.textColored(label, C.muted); ui.sameLine(110); ui.textColored(value, color or C.text)
end

-- ---------------------------------------------------------------------------------------------- window
function script.windowMain(dt)
  local size = ui.windowSize()
  ui.drawRectFilled(vec2(0, 0), size, C.bg, 0)
  ui.drawRectFilled(vec2(0, 0), vec2(size.x, 3), store.enabled and C.accent or C.muted, 0)

  ui.setCursor(vec2(16, 14))
  ui.beginGroup()

  -- header
  ui.pushFont(ui.Font.Title)
  ui.textColored('PHOTOLAP', C.text)
  ui.popFont()
  ui.sameLine(0, 8)
  ui.offsetCursorY(6)
  ui.textColored('photoreal for AC', C.muted)

  ui.offsetCursorY(6)
  if pill('master', store.enabled and 'ENGAGED' or 'BYPASSED  (vanilla AC)', store.enabled, C.accent, size.x - 32) then
    store.enabled = not store.enabled
  end

  -- neural
  section('PHOTOLAP NEURAL', C.accent2)
  if pill('neural', 'Neural pass', store.neural, C.accent2, size.x - 32) then store.neural = not store.neural end
  ui.pushStyleColor(ui.StyleColor.SliderGrab, C.accent2)
  ui.setNextItemWidth(size.x - 32)
  local v, ch = ui.slider('##nri', store.nr_intensity, 0, 1, 'Intensity: %.2f')
  if ch then store.nr_intensity = v end
  ui.popStyleColor()

  -- presets
  section('LOOK')
  local bw = math.floor((size.x - 32 - 8) / 2)
  for i, p in ipairs(PRESETS) do
    local active = store.preset == p.id
    ui.pushStyleColor(ui.StyleColor.Button, active and C.accent or C.card)
    ui.pushStyleColor(ui.StyleColor.Text, active and rgbm(0, 0, 0, 1) or C.text)
    if ui.button(p.name .. '##' .. p.id, vec2(i == #PRESETS and (size.x - 32) or bw, 30)) then loadPreset(p, false); saveTweaks() end
    ui.popStyleColor(2)
    if ui.itemHovered() then ui.setTooltip(p.hint) end
    if i % 2 == 1 and i ~= #PRESETS then ui.sameLine(0, 8) end
  end

  -- effects
  section('EFFECTS')
  local hw = math.floor((size.x - 32 - 8) / 2)
  if pill('t_light', 'HDR Light', store.light, C.accent, hw) then store.light = not store.light end
  ui.sameLine(0, 8)
  if pill('t_atmos', 'Atmosphere', store.atmos, C.accent, hw) then store.atmos = not store.atmos end
  if pill('t_detail', 'Detail', store.detail, C.accent, hw) then store.detail = not store.detail end
  ui.sameLine(0, 8)
  if pill('t_lens', 'Lens', store.lens, C.accent, hw) then store.lens = not store.lens end

  ui.offsetCursorY(4)
  sliderRow('Exposure', 'PL_Exposure', -2, 2, '%+.2f EV')
  sliderRow('Bloom', 'PL_BloomIntensity', 0, 1)
  sliderRow('Sharpen', 'PL_Sharpen', 0, 1)
  storeSlider('Mix', 'mix', 0, 1)

  ui.offsetCursorY(4)
  if pill('split', 'Before / after split', store.split, C.accent2, size.x - 32) then store.split = not store.split end

  -- advanced
  ui.offsetCursorY(6)
  if ui.button((store.advanced and '▾ ' or '▸ ') .. 'Advanced', vec2(size.x - 32, 24)) then store.advanced = not store.advanced end
  if store.advanced then
    section('LIGHT')
    sliderRow('Highlight recovery', 'PL_HighlightRecover', 0, 1)
    sliderRow('Halation', 'PL_Halation', 0, 1)
    sliderRow('Filmic', 'PL_FilmicStrength', 0, 1)
    sliderRow('Temperature', 'PL_Temperature', -1, 1, '%+.2f')
    sliderRow('Tint', 'PL_Tint', -1, 1, '%+.2f')
    section('GRADE')
    sliderRow('Contrast', 'PL_Contrast', -0.5, 0.5, '%+.2f')
    sliderRow('Saturation', 'PL_Saturation', -1, 1, '%+.2f')
    sliderRow('Vibrance', 'PL_Vibrance', -1, 1, '%+.2f')
    section('ATMOSPHERE · DETAIL · LENS')
    sliderRow('Haze', 'PL_HazeDensity', 0, 1)
    sliderRow('Clarity', 'PL_Clarity', 0, 1)
    sliderRow('Chromatic aberration', 'PL_ChromaAb', 0, 1)
    sliderRow('Vignette', 'PL_Vignette', 0, 1)
    sliderRow('Grain', 'PL_Grain', 0, 1)
    if status.conflict then
      section('COMPATIBILITY')
      if pill('conflict', 'Skip re-tonemap (' .. status.conflict .. ')', not store.ignore_conflict, C.ok, size.x - 32) then
        store.ignore_conflict = not store.ignore_conflict
      end
    end
  end

  -- status
  section('STATUS')
  row('Shaders', status.shaders, status.shadersOk and C.ok or (store.enabled and C.warn or C.muted))
  local neuralOn = store.enabled and store.neural and store.nr_intensity > 0
  row('Neural', neuralOn and string.format('on · %.0f%%', store.nr_intensity * 100) or 'off', neuralOn and C.accent2 or C.muted)
  if status.gpuOn and status.gpuOff then
    row('GPU cost', string.format('≈ %.1f ms', math.max(status.gpuOn - status.gpuOff, 0)), C.text)
  elseif status.gpuOn then
    row('GPU cost', string.format('frame %.1f ms · Alt+O twice to measure', status.gpuOn), C.muted)
  else
    row('GPU cost', 'measuring…', C.muted)
  end
  row('Upscaler', status.upscaler, status.upscalerOn and C.ok or C.muted)
  if not status.upscalerOn then
    ui.textWrapped('Turn on DLSS or FSR in CM › Settings › Custom Shaders Patch › Graphics adjustments › Upscaling.')
  end
  if status.conflict then
    ui.textColored(status.conflict .. ' is active: Photolap stays on top' ..
      (store.ignore_conflict and '.' or ' and skips its own re-tonemap.'), C.warn)
  end
  if not ac.isModuleActive(ac.CSPModuleID.GraphicsAdjustments) then
    ui.textColored('Enable CSP “Graphics adjustments”: Photolap reads the frame through it.', C.warn)
  end
  if status.error then ui.textWrapped(status.error) end
  ui.offsetCursorY(4)
  ui.textColored('Alt+P panel   ·   Alt+O bypass', C.muted)

  ui.endGroup()
end
