--[[
  Audio: every AC volume channel (ac.getAudioVolume / ac.setAudioVolume: live, saved like AC's own audio settings)
  and three mix profiles that set them together. A slider drag sets the volume live without saving; the save happens
  once, 250 ms after the drag ends.

  The design's Turbo knob has no AC channel, so it's the "Car components" channel instead. CSP has no Doppler switch,
  and ac.setReverbValue has no getter or documented range, so the Space card isn't in the app.
]]

local C = require('backend/config')

local M = {}

M.MIXES = {
  Studio = { main = 0.8, engine = 0.85, transmission = 0.6, carComponents = 0.6, tyres = 0.7, surfaces = 0.7, opponents = 0.75, wind = 0.35, track = 0.6 },
  Onboard = { main = 0.8, engine = 0.95, transmission = 0.75, carComponents = 0.7, tyres = 0.6, surfaces = 0.75, opponents = 0.6, wind = 0.5, track = 0.45 },
  Broadcast = { main = 0.8, engine = 0.7, transmission = 0.4, carComponents = 0.4, tyres = 0.8, surfaces = 0.5, opponents = 0.9, wind = 0.25, track = 0.8 },
}

function M.volume(key)
  local p = C.pending['audio/' .. key]
  if p ~= nil then return p end
  local ok, v = pcall(ac.getAudioVolume, key)
  return ok and type(v) == 'number' and v >= 0 and v or nil
end

function M.setVolume(key, v, now)
  v = math.min(math.max(v, 0), 1)
  if now then pcall(ac.setAudioVolume, key, v, -1, true); return end
  pcall(ac.setAudioVolume, key, v, -1, false)
  C.later('audio/' .. key, v, function (x) pcall(ac.setAudioVolume, key, x, -1, true) end)
end

function M.applyMix(name)
  for k, v in pairs(M.MIXES[name] or {}) do M.setVolume(k, v, true) end
end

function M.register(R, St)
  local CH = {
    { 'm_master', 'Master', 'main' }, { 'm_engine', 'Engine', 'engine' }, { 'm_trans', 'Gearbox', 'transmission' },
    { 'm_comp', 'Components', 'carComponents' }, { 'm_tyres', 'Tyre squeal', 'tyres' }, { 'm_surf', 'Kerbs and surfaces', 'surfaces' },
    { 'm_opp', 'Other cars', 'opponents' }, { 'm_wind', 'Wind', 'wind' }, { 'm_amb', 'Ambience', 'track' },
  }
  for _, c in ipairs(CH) do
    if M.volume(c[3]) then
      R.api(c[1], c[2], { kind = 'slider', min = 0, max = 100, step = 1, default = 80, fmt = R.fmt.pct, key = 'audio: ' .. c[3],
        get = function () return (M.volume(c[3]) or 0) * 100 end,
        set = function (v, now) M.setVolume(c[3], v / 100, now) end,
        readback = function () local ok, v = pcall(ac.getAudioVolume, c[3]); return ok and v and v * 100 or nil end })
    end
  end
  R.api('mix', 'Profile', { kind = 'seg', options = { { label = 'Studio', value = 'Studio' }, { label = 'Onboard', value = 'Onboard' },
      { label = 'Broadcast', value = 'Broadcast' } }, key = 'sets every channel',
    get = function () return St.mix or 'Onboard' end,
    set = function (v) St.mix = v; M.applyMix(v) end,
    readback = function ()   -- the profile is what the channels now say
      local m = M.MIXES[St.mix or 'Onboard']
      for k, v in pairs(m) do local x = M.volume(k); if not x or math.abs(x - v) > 0.01 then return nil end end
      return St.mix or 'Onboard'
    end })
end

return M
