--[[
  Lumicorsa tabs: which cards each tab shows and which registry entries each card holds, in design order.
  A row whose entry doesn't exist (CSP build without that key, app not installed) is dropped, and a card with no rows
  left isn't shown. `cost` names the effect group whose measured GPU cost the card's chip shows ('free' = no GPU work
  from Lumicorsa, 'csp' = a CSP feature whose cost CSP doesn't expose).
]]

local M = {}

M.ORDER = { 'look', 'light', 'weather', 'graphics', 'camera', 'hud', 'drive', 'audio', 'sky', 'photo', 'system' }
M.LABELS = { look = 'Look', light = 'Light', weather = 'Weather', graphics = 'Graphics', camera = 'Camera', hud = 'HUD',
  drive = 'Drive', audio = 'Audio', sky = 'Sky', photo = 'Photo', system = 'System' }

local function S(id) return { w = 'slider', id = id } end
local function K(...) return { w = 'knobs', ids = { ... } } end
local function G(id) return { w = 'seg', id = id } end
local function TG(id) return { w = 'toggle', id = id } end
local function B(id) return { w = 'button', id = id } end

function M.define(ctx)
  return {
    look = {
      { title = 'Blend two looks', cost = 'free', rows = { { w = 'mixer', ids = { 'blend', 'blendPair' } }, G('blendPair') } },
      { title = 'Tone curve', cost = 'grade', rows = { { w = 'curve' }, S('contrast'), S('hl'), S('lift') } },
      { title = 'White balance', cost = 'grade', rows = { { w = 'xy', ids = { 'wb_temp', 'wb_tint' } }, S('sat') } },
      { title = 'Detail', cost = { 'detail', 'neural' }, rows = { K('sharpen', 'clarity', 'neural'), TG('neuralOn') } },
      { title = 'Exposure', cost = 'exposure', rows = { S('exposure'), S('adapt'), TG('autoLook') } },
      { title = 'Lens', cost = 'grade', rows = { K('vig', 'grain', 'ca') } },
    },
    light = {
      { title = 'Bloom and glare', cost = 'bloom', rows = { K('bloom', 'glare', 'hal') } },
      { title = 'Sun', cost = 'sun', rows = { S('shafts'), S('flare'), TG('wsrefl') } },
      { title = 'Ambient occlusion', cost = 'ao', rows = { G('ao'), S('contact') } },
      { title = 'Bounce light', cost = 'csp', rows = { TG('bounce'), TG('bounceTrack') } },
    },
    weather = {
      { title = 'Windscreen', cost = 'csp', rows = { TG('drops'), TG('wipers') } },
      { title = 'Time', cost = 'free', rows = { { w = 'daystrip', id = 'tod' }, S('tmul') } },
      { title = 'Visibility', cost = 'mist', rows = { S('haze'), S('mist') } },
    },
    graphics = {
      { title = 'Quality', cost = 'free', rows = { { w = 'perf', id = 'tier' } } },
      { title = 'Upscaling', cost = 'csp', rows = { G('up'), S('rscale'), S('upsharp') } },
      { title = 'Reflections', cost = 'csp', rows = { S('cube'), S('faces'), TG('sslr') } },
      { title = 'Shadows', cost = 'csp', rows = { S('shres'), S('shdist') } },
      { title = 'World', cost = 'csp', rows = { S('grass'), S('lod'), S('mirror') } },
      { title = 'Smoothness', cost = 'free', rows = { S('fpscap'), B('smoothMotion') } },
    },
    camera = {
      { title = 'Chase camera', cost = 'free', rows = { { w = 'cam', ids = { 'ch_d', 'ch_h', 'ch_p' } }, K('ch_h', 'ch_d', 'ch_p') } },
      { title = 'Field of view', cost = 'free', rows = { S('fov_c'), B('fovCalc') } },
      { title = 'Cockpit', cost = 'dof', rows = { TG('cdof'), S('headmove') } },
      { title = 'Seat', cost = 'free', rows = { S('seat_h'), S('seat_f') } },
      { title = 'Replay', cost = 'dof', rows = { G('replaycam'), S('rdof') } },
    },
    hud = {
      { title = 'In-game HUD', cost = 'free', rows = { TG('hudOn'), G('hudShow'), G('units') } },
      { title = 'Live preview', cost = 'free', rows = { { w = 'preview' } } },
      { title = 'Position on screen', cost = 'free', rows = { { w = 'pos', id = 'hudPos' }, S('hudsc'), S('hudop') } },
      { title = 'Warning lamps', cost = 'free', rows = { { w = 'lamps', id = 'lamps' } } },
      { title = 'Analog cluster', cost = 'free', rows = { TG('sweep'), G('needle'), G('lcd') } },
      { title = 'Shift lights', cost = 'free', rows = { S('shiftat'), TG('warm'), S('glow') } },
    },
    drive = {
      { title = 'Force feedback', cost = 'free', rows = { K('ffb', 'ffbmin', 'damper') } },
      { title = 'Feel', cost = 'free', rows = { TG('gyro'), S('kerb'), S('road') } },
      { title = 'Assists', cost = 'free', rows = { G('absm'), G('tcm') } },
      { title = 'Controls', cost = 'free', rows = { S('steerlock') } },
    },
    audio = {
      { title = 'Mix', cost = 'free', rows = { G('mix'), S('m_master') } },
      { title = 'Car', cost = 'free', rows = { K('m_engine', 'm_trans', 'm_comp') } },
      { title = 'Tyres', cost = 'free', rows = { S('m_tyres'), S('m_surf') } },
      { title = 'World', cost = 'free', rows = { S('m_opp'), S('m_wind'), S('m_amb') } },
    },
    sky = {
      { title = 'Weather engine', cost = 'free', rows = { { w = 'info', label = 'Detected', value = ctx.skyLabel } } },
      { title = 'Planners', cost = 'free', rows = { B('purePlanner'), B('pureConfig'), B('solPlanner') } },
      { title = 'Sky quality', cost = 'csp', rows = { TG('clouds'), TG('cloudsh'), TG('stars') } },
    },
    photo = {
      { title = 'Screenshot', cost = 'free', rows = { B('shot'), G('shotscale') } },
      { title = 'Depth of field', cost = 'dof', rows = { TG('photoDof'), K('aperture', 'focus', 'bokeh') } },
      { title = 'Motion', cost = 'csp', rows = { S('mblur') } },
    },
    system = {
      { title = 'ReShade', cost = 'free', rows = { { w = 'info', label = 'Status', value = ctx.reshadeLabel }, B('reshade_install'), B('reshade_remove'),
          { w = 'note', text = ctx.reshadeNote } } },
      { title = 'Hotkeys', cost = 'free', rows = { { w = 'info', label = 'Dashboard', value = function () return 'Alt+P' end },
          { w = 'info', label = 'Vanilla view', value = function () return 'Alt+O' end }, { w = 'info', label = 'HUD', value = function () return 'Alt+H' end },
          { w = 'info', label = 'Quick ring', value = function () return 'Hold Q' end }, { w = 'info', label = 'Find a setting', value = function () return 'Ctrl+K' end },
          { w = 'note', text = function () return 'Rebind any of them in CSP › Controls.' end } } },
      { title = 'Performance', cost = 'free', rows = { TG('overlay'), TG('budgetOn'), S('budget'), B('measure') } },
      { title = 'Profiles', cost = 'free', rows = { B('export'), B('import') } },
      { title = 'Verification', cost = 'free', rows = { B('selftest'), B('proof'), B('soak'), { w = 'note', text = ctx.verifyNote } } },
    },
  }
end

-- Resolve rows against the registry; drop missing entries and empty cards.
function M.build(R, ctx)
  local defs = M.define(ctx)
  local out = {}
  for tab, cards in pairs(defs) do
    out[tab] = {}
    for _, card in ipairs(cards) do
      local rows = {}
      for _, r in ipairs(card.rows) do
        if r.id then
          local d = R.get(r.id)
          if d then r.def = d; rows[#rows + 1] = r end
        elseif r.ids then
          local ds, okAll = {}, true
          for i, id in ipairs(r.ids) do ds[i] = R.get(id); if not ds[i] then okAll = false end end
          if r.w == 'knobs' then   -- knob rows keep whichever knobs exist
            local kept = {}
            for _, d in ipairs(ds) do if d then kept[#kept + 1] = d end end
            if #kept > 0 then r.defs = kept; rows[#rows + 1] = r end
          elseif okAll then r.defs = ds; rows[#rows + 1] = r end
        else
          rows[#rows + 1] = r
        end
      end
      if #rows > 0 then
        card.rows = rows
        card.tab = tab
        out[tab][#out[tab] + 1] = card
        for _, r in ipairs(rows) do   -- remember where each entry lives (palette, flash)
          for _, d in ipairs(r.defs or { r.def }) do if d and not d.tab then d.tab, d.card = tab, card.title end end
        end
      end
    end
  end
  return out
end

return M
