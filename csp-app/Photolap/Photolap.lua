--[[
  PHOTOLAP — in-game control panel (CSP Lua app)
  Copyright (c) 2026 Photolap contributors. MIT License.

  The panel is the single source of truth for the look. It writes state/control.ini, which the
  photolap.addon64 ReShade add-on watches and applies within ~150 ms (techniques, PL_* uniforms,
  and the DLSS 5 neural pass through the RenoDX live-control API). The add-on writes state/status.ini
  back, which the footer shows, so the panel never claims something is on that isn't.

  Open it from the CSP apps bar (right edge) or with Alt+P (rebindable in CSP controls).
]]

local APP_DIR = ac.getFolder(ac.FolderID.ACAppsLua) .. '/Photolap'
local STATE_DIR = APP_DIR .. '/state'
local CONTROL = STATE_DIR .. '/control.ini'
local STATUS = STATE_DIR .. '/status.ini'
pcall(io.createDir, STATE_DIR)

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
-- Every PL_* key maps 1:1 to a uniform in Photolap.fx. Neural values drive the RenoDX DLSS 5 pass.
local PRESETS = {
  { id = 'photoreal', name = 'Photoreal', hint = 'Daylight, camera-true',
    neural = true, nr_intensity = 0.60, nr_style = 0,
    v = { PL_Exposure = 0.0, PL_HighlightRecover = 0.55, PL_BloomIntensity = 0.18, PL_Halation = 0.15, PL_FilmicStrength = 0.75,
          PL_Contrast = 0.08, PL_Saturation = -0.04, PL_Vibrance = 0.12, PL_HazeDensity = 0.30, PL_Clarity = 0.22, PL_Sharpen = 0.35,
          PL_ChromaAb = 0.10, PL_Vignette = 0.25, PL_Grain = 0.08, PL_Temperature = 0.0, PL_Tint = 0.0 } },
  { id = 'midnight', name = 'Midnight Run', hint = 'Night highway / tandem',
    neural = true, nr_intensity = 0.70, nr_style = 0,
    v = { PL_Exposure = 0.25, PL_HighlightRecover = 0.80, PL_BloomIntensity = 0.38, PL_Halation = 0.55, PL_FilmicStrength = 0.90,
          PL_Contrast = 0.12, PL_Saturation = 0.02, PL_Vibrance = 0.18, PL_HazeDensity = 0.18, PL_Clarity = 0.18, PL_Sharpen = 0.30,
          PL_ChromaAb = 0.18, PL_Vignette = 0.40, PL_Grain = 0.14, PL_Temperature = -0.15, PL_Tint = 0.05 } },
  { id = 'golden', name = 'Golden Hour', hint = 'Warm, soft, cinematic',
    neural = true, nr_intensity = 0.55, nr_style = 0,
    v = { PL_Exposure = 0.10, PL_HighlightRecover = 0.65, PL_BloomIntensity = 0.30, PL_Halation = 0.35, PL_FilmicStrength = 0.85,
          PL_Contrast = 0.06, PL_Saturation = 0.04, PL_Vibrance = 0.20, PL_HazeDensity = 0.45, PL_Clarity = 0.15, PL_Sharpen = 0.28,
          PL_ChromaAb = 0.12, PL_Vignette = 0.35, PL_Grain = 0.10, PL_Temperature = 0.35, PL_Tint = 0.04 } },
  { id = 'broadcast', name = 'Broadcast', hint = 'TV-camera clean, punchy',
    neural = true, nr_intensity = 0.45, nr_style = 0,
    v = { PL_Exposure = 0.0, PL_HighlightRecover = 0.45, PL_BloomIntensity = 0.10, PL_Halation = 0.0, PL_FilmicStrength = 0.60,
          PL_Contrast = 0.14, PL_Saturation = 0.08, PL_Vibrance = 0.10, PL_HazeDensity = 0.20, PL_Clarity = 0.30, PL_Sharpen = 0.45,
          PL_ChromaAb = 0.0, PL_Vignette = 0.10, PL_Grain = 0.0, PL_Temperature = 0.0, PL_Tint = 0.0 } },
  { id = 'perf', name = 'Performance', hint = 'Cheapest, no neural',
    neural = false, nr_intensity = 0.0, nr_style = 0,
    v = { PL_Exposure = 0.0, PL_HighlightRecover = 0.40, PL_BloomIntensity = 0.12, PL_Halation = 0.0, PL_FilmicStrength = 0.60,
          PL_Contrast = 0.06, PL_Saturation = 0.0, PL_Vibrance = 0.08, PL_HazeDensity = 0.0, PL_Clarity = 0.0, PL_Sharpen = 0.35,
          PL_ChromaAb = 0.0, PL_Vignette = 0.15, PL_Grain = 0.0, PL_Temperature = 0.0, PL_Tint = 0.0 },
    techniques = { light = true, atmos = false, detail = true, lens = false } },
}

-- ---------------------------------------------------------------------------------------------- persistent state
local store = ac.storage({
  enabled = true, preset = 'photoreal',
  neural = true, nr_intensity = 0.60, nr_preset = 0, nr_style = 0, nr_tone = 1.0, nr_structure = 1.0, nr_keep_hud = true,
  light = true, atmos = true, detail = true, lens = true,
  hud_safe = true, hud_draw_index = 1, split = false, mix = 1.0,
  advanced = false,
})
local values = {}   -- current PL_* values (seeded from preset, then user-edited)
local seq = 0
local status = {}
local dirty = true

local function presetById(id)
  for _, p in ipairs(PRESETS) do if p.id == id then return p end end
  return PRESETS[1]
end

local function loadPreset(p, keepUserToggles)
  for k, v in pairs(p.v) do values[k] = v end
  store.preset = p.id
  store.neural = p.neural
  store.nr_intensity = p.nr_intensity
  store.nr_style = p.nr_style
  if p.techniques and not keepUserToggles then
    for k, v in pairs(p.techniques) do store[k] = v end
  elseif not keepUserToggles then
    store.light, store.atmos, store.detail, store.lens = true, true, true, true
  end
  dirty = true
end

-- user tweaks to sliders are remembered per session in a separate storage table
local tweaks = ac.storage({ json = '' }, 'tweaks_')
local function saveTweaks() tweaks.json = JSON.stringify(values) end
local function loadTweaks()
  local ok, t = pcall(JSON.parse, tweaks.json or '')
  if ok and type(t) == 'table' then for k, v in pairs(t) do values[k] = v end end
end

loadPreset(presetById(store.preset), true)
loadTweaks()

-- ---------------------------------------------------------------------------------------------- IPC with the add-on
local function b(x) return x and '1' or '0' end
local function f(x) return string.format('%.4f', x) end

local function writeControl()
  seq = seq + 1
  local lines = {
    '; Photolap control file. Written by the in-game app, read live by photolap.addon64.',
    'enabled=' .. b(store.enabled),
    'preset=' .. store.preset,
    'neural=' .. b(store.neural),
    'nr_intensity=' .. f(store.nr_intensity),
    'nr_preset=' .. tostring(store.nr_preset),
    'nr_style=' .. tostring(store.nr_style),
    'nr_tone=' .. f(store.nr_tone),
    'nr_structure=' .. f(store.nr_structure),
    'nr_keep_hud=' .. b(store.nr_keep_hud),
    'light=' .. b(store.light), 'atmos=' .. b(store.atmos), 'detail=' .. b(store.detail), 'lens=' .. b(store.lens),
    'hud_safe=' .. b(store.hud_safe),
    'hud_draw_index=' .. tostring(math.floor(store.hud_draw_index)),
    'PL_Mix=' .. f(store.mix),
    'PL_SplitView=' .. (store.split and 'true' or 'false'),
  }
  local keys = {}
  for k in pairs(values) do keys[#keys + 1] = k end
  table.sort(keys)
  for _, k in ipairs(keys) do lines[#lines + 1] = k .. '=' .. f(values[k]) end
  lines[#lines + 1] = 'writer=app'
  lines[#lines + 1] = 'seq=' .. tostring(seq)
  io.save(CONTROL, table.concat(lines, '\n') .. '\n')
end

local function readKV(path)
  local data = io.load(path)
  local t = {}
  if not data then return t end
  for line in data:gmatch('[^\r\n]+') do
    local k, v = line:match('^%s*([%w_]+)%s*=%s*(.-)%s*$')
    if k then t[k] = v end
  end
  return t
end

-- Pick up edits made in the add-on's own fallback panel (Alt+Shift+P) so both UIs stay in sync.
local function syncFromAddonPanel()
  local c = readKV(CONTROL)
  if c.writer ~= 'addon' then return end
  local function tb(k) return c[k] == '1' end
  store.enabled, store.neural = tb('enabled'), tb('neural')
  store.light, store.atmos, store.detail, store.lens = tb('light'), tb('atmos'), tb('detail'), tb('lens')
  store.hud_safe = tb('hud_safe')
  store.nr_intensity = tonumber(c.nr_intensity) or store.nr_intensity
  for k, v in pairs(c) do if k:sub(1, 3) == 'PL_' and k ~= 'PL_SplitView' and k ~= 'PL_Mix' then values[k] = tonumber(v) or values[k] end end
  store.mix = tonumber(c.PL_Mix) or store.mix
  seq = tonumber(c.seq) or seq
  saveTweaks()
end

setInterval(function()
  if dirty then writeControl(); saveTweaks(); dirty = false end
end, 0.1, 'photolap_write')

setInterval(function()
  status = readKV(STATUS)
  syncFromAddonPanel()
end, 0.5, 'photolap_status')

-- Hotkey: Alt+P toggles this window (rebind in CSP > Controls).
local toggleKey = ac.ControlButton('__APP_PHOTOLAP_TOGGLE', { keyboard = { key = ui.KeyIndex.P, alt = true } })
toggleKey:onPressed(function()
  pcall(function()
    local w = ac.accessAppWindow('IMGUI_LUA_Photolap_main')
    if w then w:setVisible(not w:visible()) end
  end)
end)

-- Master on/off shortcut that works even with the window closed: Alt+O.
local masterKey = ac.ControlButton('__APP_PHOTOLAP_MASTER', { keyboard = { key = ui.KeyIndex.O, alt = true } })
masterKey:onPressed(function() store.enabled = not store.enabled; dirty = true end)

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
  -- switch track
  local tx = p.x + w - 46
  ui.drawRectFilled(vec2(tx, p.y + 8), vec2(tx + 34, p.y + 22), on and color or rgbm(1, 1, 1, 0.12), 7)
  ui.drawCircleFilled(vec2(on and tx + 27 or tx + 7, p.y + 15), 5, on and rgbm(0, 0, 0, 0.85) or C.muted, 16)
  ui.drawText(label, p + vec2(12, 7), on and C.text or C.muted)
  return clicked
end

local function sliderRow(label, key, lo, hi, fmt)
  ui.setNextItemWidth(ui.availableSpaceX())
  local v, changed = ui.slider('##' .. key, values[key] or 0, lo, hi, label .. ': ' .. (fmt or '%.2f'))
  if changed then values[key] = v; dirty = true end
end

local function storeSlider(label, key, lo, hi, fmt)
  ui.setNextItemWidth(ui.availableSpaceX())
  local v, changed = ui.slider('##s_' .. key, store[key], lo, hi, label .. ': ' .. (fmt or '%.2f'))
  if changed then store[key] = v; dirty = true end
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
  ui.textColored('neural photoreal for AC', C.muted)

  ui.offsetCursorY(6)
  if pill('master', store.enabled and 'ENGAGED' or 'BYPASSED  (vanilla AC)', store.enabled, C.accent, size.x - 32) then
    store.enabled = not store.enabled; dirty = true
  end

  -- neural
  section('NEURAL RENDERING  ·  DLSS 5', C.accent2)
  local liveApi = status.neural_live_api == '1'
  if pill('neural', 'Neural pass', store.neural, C.accent2, size.x - 32) then store.neural = not store.neural; dirty = true end
  ui.pushStyleColor(ui.StyleColor.SliderGrab, C.accent2)
  ui.setNextItemWidth(size.x - 32)
  local v, ch = ui.slider('##nri', store.nr_intensity, 0, 1, 'Intensity: %.2f')
  if ch then store.nr_intensity = v; dirty = true end
  ui.popStyleColor()
  if not liveApi then
    ui.textColored(status.neural_backend and status.neural_backend ~= 'none'
      and ('Backend: ' .. status.neural_backend) or 'No neural backend detected: see README > Neural setup', C.warn)
  end

  -- presets
  section('LOOK')
  local bw = math.floor((size.x - 32 - 8) / 2)
  for i, p in ipairs(PRESETS) do
    local active = store.preset == p.id
    ui.pushStyleColor(ui.StyleColor.Button, active and C.accent or C.card)
    ui.pushStyleColor(ui.StyleColor.Text, active and rgbm(0, 0, 0, 1) or C.text)
    if ui.button(p.name .. '##' .. p.id, vec2(i == #PRESETS and (size.x - 32) or bw, 30)) then loadPreset(p, false) end
    ui.popStyleColor(2)
    if ui.itemHovered() then ui.setTooltip(p.hint) end
    if i % 2 == 1 and i ~= #PRESETS then ui.sameLine(0, 8) end
  end

  -- effects
  section('EFFECTS')
  local hw = math.floor((size.x - 32 - 8) / 2)
  if pill('t_light', 'HDR Light', store.light, C.accent, hw) then store.light = not store.light; dirty = true end
  ui.sameLine(0, 8)
  if pill('t_atmos', 'Atmosphere', store.atmos, C.accent, hw) then store.atmos = not store.atmos; dirty = true end
  if pill('t_detail', 'Detail', store.detail, C.accent, hw) then store.detail = not store.detail; dirty = true end
  ui.sameLine(0, 8)
  if pill('t_lens', 'Lens', store.lens, C.accent, hw) then store.lens = not store.lens; dirty = true end

  ui.offsetCursorY(4)
  sliderRow('Exposure', 'PL_Exposure', -2, 2, '%+.2f EV')
  sliderRow('Bloom', 'PL_BloomIntensity', 0, 1)
  sliderRow('Sharpen', 'PL_Sharpen', 0, 1)
  storeSlider('Mix', 'mix', 0, 1)

  ui.offsetCursorY(4)
  if pill('split', 'Before / after split', store.split, C.accent2, size.x - 32) then store.split = not store.split; dirty = true end

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
    section('NEURAL (RenoDX)')
    storeSlider('Tone', 'nr_tone', 0, 2)
    storeSlider('Structure', 'nr_structure', 0, 2)
    section('COMPATIBILITY')
    if pill('hudsafe', 'Keep HUD & apps untouched', store.hud_safe, C.ok, size.x - 32) then store.hud_safe = not store.hud_safe; dirty = true end
    ui.setNextItemWidth(size.x - 32)
    local hv, hch = ui.slider('##hdi', store.hud_draw_index, 0, 6, 'HUD-safe draw index: %.0f', true)
    if hch then store.hud_draw_index = hv; dirty = true end
  end

  -- status footer
  section('STATUS')
  local alive = status.tick ~= nil
  local function row(label, value, color)
    ui.textColored(label, C.muted); ui.sameLine(120); ui.textColored(value, color or C.text)
  end
  row('Add-on', alive and ('v' .. (status.addon_version or '?')) or 'not running', alive and C.ok or C.warn)
  row('Effects', status.effects_loaded == '1' and 'loaded' or 'missing', status.effects_loaded == '1' and C.ok or C.warn)
  row('Neural', status.neural_backend or '—', liveApi and C.ok or C.muted)
  row('HUD-safe', status.hud_safe_active == '1' and 'active' or 'fallback', status.hud_safe_active == '1' and C.ok or C.muted)
  if status.last_error and status.last_error ~= '' then ui.textWrapped(status.last_error) end
  ui.offsetCursorY(4)
  ui.textColored('Alt+P panel   ·   Alt+O bypass', C.muted)

  ui.endGroup()
end
