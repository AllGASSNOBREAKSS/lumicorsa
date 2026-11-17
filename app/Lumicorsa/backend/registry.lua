--[[
  Lumicorsa settings registry. Every control in the dashboard is one entry here, and nothing else draws a control.

  An entry: { id, label, kind, get(), set(v), readback(), apply, key, locked(), ... }
    kind      slider | knob | toggle | seg | action (plus composite widgets that bind to several entries)
    get/set   UI value (display units for sliders: °, %, m, ms...)
    readback  reads the value back from where it really lives (config file on disk, CSP API getter, the values handed to
              the shader on the last frame), never from the UI's own copy. The self-test compares set() with readback().
    apply     'live' | 'restart' (CSP needs an AC restart) | 'next' (AC reads it next launch) | 'session' (next session)
    key       raw config key, shown in Expert mode
    locked()  returns a one-line reason when the setting can't be changed right now (online server rules)
]]

local C = require('backend/config')

local R = { all = {}, byId = {} }

local function approx(a, b)
  if type(a) == 'number' and type(b) == 'number' then return math.abs(a - b) <= math.max(1e-3, math.abs(b) * 1e-3) end
  return tostring(a) == tostring(b)
end
R.approx = approx

function R.add(def)
  assert(def.id and not R.byId[def.id], 'duplicate or missing setting id: ' .. tostring(def.id))
  def.apply = def.apply or 'live'
  R.all[#R.all + 1] = def
  R.byId[def.id] = def
  return def
end

function R.get(id) return R.byId[id] end

-- Formats
R.fmt = {
  pct = function (v) return string.format('%d%%', math.floor(v + 0.5)) end,
  int = function (v) return string.format('%d', math.floor(v + 0.5)) end,
  f1 = function (v) return string.format('%.1f', v) end,
  f2 = function (v) return string.format('%.2f', v) end,
}
function R.fmt.unit(u, digits)
  return function (v) return string.format('%.' .. (digits or 0) .. 'f%s', v, u) end
end

-- ---------------------------------------------------------------------------------------------- config-backed
-- A CSP module setting. Type comes from CSP's schema unless overridden. `o.map = { to = ui->cfg, from = cfg->ui }`
-- converts display units. Returns nil (no entry) if this CSP build doesn't have the key: the control isn't shown.
function R.csp(id, label, module, section, key, o)
  o = o or {}
  local src = 'csp:' .. module
  local d = C.describe(src, section, key)
  if not d and not o.kind then return nil end
  local map = o.map or { to = function (x) return x end, from = function (x) return x end }
  local def = { id = id, label = label, apply = o.apply, hint = o.hint, locked = o.locked,
    key = module .. '.ini [' .. section .. '] ' .. key, src = src, section = section, cfgKey = key }
  def.kind = o.kind or (d.kind == 'bool' and 'toggle' or d.kind == 'range' and 'slider' or 'seg')
  local fallback = o.fallback
  if def.kind == 'toggle' then
    def.get = function () return tonumber(C.get(src, section, key, fallback)) == 1 end
    def.set = function (v) C.set(src, section, key, v and 1 or 0) end
    def.readback = function () return tonumber(C.readback(src, section, key, fallback)) == 1 end
  elseif def.kind == 'seg' then
    def.options = o.options or d.options
    def.get = function () return C.get(src, section, key, fallback) end
    def.set = function (v) C.set(src, section, key, v) end
    def.readback = function () return C.readback(src, section, key, fallback) end
  else
    def.min = o.min or map.from(d.min)
    def.max = o.max or map.from(d.max)
    def.step = o.step or (d and d.round and map.from(d.round) - map.from(0)) or nil
    def.default = o.default or (d and map.from(d.default))
    def.fmt = o.fmt or (d and d.perc and function (v) return R.fmt.pct(v) end) or R.fmt.f2
    def.get = function () return map.from(tonumber(C.get(src, section, key, fallback)) or 0) end
    def.set = function (v, now)
      if now then C.set(src, section, key, map.to(v)) else C.setLater(src, section, key, map.to(v)) end
    end
    def.readback = function () return map.from(tonumber(C.readback(src, section, key, fallback)) or 0) end
  end
  return R.add(def)
end

-- An AC config value (video.ini / controls.ini). No schema: the caller describes the control.
function R.ac(id, label, file, section, key, o)
  local src = 'ac:' .. file
  local map = o.map or { to = function (x) return x end, from = function (x) return x end }
  local def = { id = id, label = label, kind = o.kind, apply = o.apply or (file == 'video' and 'next' or 'session'),
    key = file .. '.ini [' .. section .. '] ' .. key, options = o.options, min = o.min, max = o.max, step = o.step,
    default = o.default, fmt = o.fmt, hint = o.hint, locked = o.locked, src = src, section = section, cfgKey = key, snap = o.snap }
  local fallback = o.fallback or 0
  if o.kind == 'toggle' then
    def.get = function () return tonumber(C.get(src, section, key, fallback)) == 1 end
    def.set = function (v) C.set(src, section, key, v and 1 or 0) end
    def.readback = function () return tonumber(C.readback(src, section, key, fallback)) == 1 end
  elseif o.kind == 'seg' then
    def.get = function () return C.get(src, section, key, fallback) end
    def.set = function (v) C.set(src, section, key, v) end
    def.readback = function () return C.readback(src, section, key, fallback) end
  else
    def.get = function () return map.from(tonumber(C.get(src, section, key, fallback)) or fallback) end
    def.set = function (v, now)
      if now then C.set(src, section, key, map.to(v)) else C.setLater(src, section, key, map.to(v)) end
    end
    def.readback = function () return map.from(tonumber(C.readback(src, section, key, fallback)) or fallback) end
  end
  return R.add(def)
end

-- ---------------------------------------------------------------------------------------------- live API / app state
-- A setting backed by a CSP API: o.get, o.set, o.readback (an API getter, never the UI's copy).
function R.api(id, label, o)
  o.id, o.label = id, label
  o.readback = o.readback or o.get
  return R.add(o)
end

-- A Lumicorsa-owned value (look values, HUD options). `o.readback` must read where it's consumed (shader values sent,
-- cluster draw state), so the self-test proves the value reached the effect.
function R.state(id, label, o)
  o.id, o.label = id, label
  return R.add(o)
end

-- A button. `o.verify()` (optional) is a non-destructive check the self-test runs instead of pressing it.
function R.action(id, label, run, o)
  o = o or {}
  o.id, o.label, o.kind, o.run = id, label, 'action', run
  return R.add(o)
end

-- ---------------------------------------------------------------------------------------------- helpers
-- A value for the self-test that differs from `current` but is valid for the control.
function R.testValue(def, current)
  if def.testValue then return def.testValue(current) end
  if def.kind == 'toggle' then return not current end
  if def.kind == 'pos' then return current == 'tl' and 'br' or 'tl' end
  if def.kind == 'lamps' then
    local s = tostring(current or '')
    return s:find('battery', 1, true) and s:gsub(',?battery', ''):gsub('^,', '') or (s == '' and 'battery' or s .. ',battery')
  end
  if def.kind == 'seg' or def.kind == 'perf' or def.kind == 'scenes' then
    for i, o in ipairs(def.options or {}) do
      if approx(o.value, current) then return def.options[i % #def.options + 1].value end
    end
    return def.options and def.options[1] and def.options[1].value
  end
  if def.snap then   -- only the values AC accepts (e.g. 256/512/1024/2048)
    for _, t in ipairs({ 0.0, 1.0, 0.5 }) do
      local v = def.snap(def.min + (def.max - def.min) * t)
      if not approx(v, current) then return v end
    end
  end
  if def.min and def.max then
    local v = def.min + (def.max - def.min) * (approx(current, def.min + (def.max - def.min) * 0.37) and 0.61 or 0.37)
    if def.step and def.step > 0 then v = def.min + math.floor((v - def.min) / def.step + 0.5) * def.step end
    return v
  end
  return nil
end

return R
