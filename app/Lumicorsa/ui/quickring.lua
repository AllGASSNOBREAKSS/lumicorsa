--[[
  Quick ring: a radial menu of eight toggles. Hold Q (rebindable) while driving, or click the header button.
  The centre names the item under the pointer and whether it's on; releasing Q fires the hovered item, a click fires
  the clicked one.

  Items: Vanilla, Rain look, Night look, Wipers, Chase cam, HUD, Free camera, Headlights. The design's "Rain" and
  "Photo mode" have no API (apps can't make it rain, CSP ships no photo-mode app), so they are the Rain run look and
  the free camera (F7) instead.
]]

local T = require('ui/theme')
local C = T.C

local M = {}

function M.items(env)
  local St = env.store
  local car = function () return ac.getCar(0) end
  return {
    { label = 'Vanilla', colour = '#FFFFFF', on = function () return not St.master end, flip = function () St.master = not St.master end },
    { label = 'Rain look', colour = '#7CB6FF', on = function () return St.preset == 'Rain run' and St.blend == 0 end,
      flip = function () env.togglePreset('Rain run') end },
    { label = 'Night look', colour = '#9CC9FF', on = function () return St.preset == 'Night run' and St.blend == 0 end,
      flip = function () env.togglePreset('Night run') end },
    { label = 'Wipers', colour = '#C9CCD1', on = function () local c = car(); return c and c.wiperMode > 0 end,
      flip = function () local c = car(); if c then pcall(ac.setWiperMode, c.wiperMode > 0 and 0 or math.min(1, c.wiperModes - 1)) end end },
    { label = 'Chase cam', colour = '#F5C518', on = function () return ac.getSim().cameraMode == ac.CameraMode.Drivable end,
      flip = function ()
        if ac.getSim().cameraMode == ac.CameraMode.Drivable then pcall(ac.setCurrentCamera, ac.CameraMode.Cockpit)
        else pcall(ac.setCurrentCamera, ac.CameraMode.Drivable); pcall(ac.setCurrentDrivableCamera, ac.DrivableCamera.Chase) end
      end },
    { label = 'HUD', colour = '#FF8A8C', on = function () return St.hudOn end, flip = function () St.hudOn = not St.hudOn end },
    { label = 'Free camera', colour = '#FF8A8C', on = function () return ac.getSim().cameraMode == ac.CameraMode.Free end,
      flip = function () pcall(ac.setCurrentCamera, ac.getSim().cameraMode == ac.CameraMode.Free and ac.CameraMode.Cockpit or ac.CameraMode.Free) end },
    { label = 'Headlights', colour = '#FFE27A', on = function () local c = car(); return c and c.headlightsActive end,
      flip = function () local c = car(); if c then pcall(ac.setHeadlights, not c.headlightsActive) end end },
  }
end

local opened = 0

-- Draws the ring centred at `c` (current drawing space), `mouse` in the same space. Returns the hovered item index.
function M.draw(items, c, mouse, dt, clickable)
  opened = math.min(1, opened + dt / 0.45)
  local e = 1 - (1 - opened) ^ 3
  local scale = 0.85 + 0.15 * e
  local R = 230 * scale
  ui.drawCircleFilled(c, R - 40 * scale, rgbm(14 / 255, 15 / 255, 18 / 255, 0.86 * e), 64)
  ui.drawCircle(c, R - 40 * scale, rgbm(1, 1, 1, 0.14 * e), 64, 1)
  ui.drawCircleFilled(c, 80 * scale, rgbm(1, 1, 1, 0.05 * e), 48)
  ui.drawCircle(c, 80 * scale, rgbm(1, 1, 1, 0.12 * e), 48, 1)
  local d = mouse - c
  local hovered = nil
  if math.sqrt(d.x * d.x + d.y * d.y) > 40 then
    local a = math.atan2(d.y, d.x) + math.pi / 2
    hovered = math.floor((a / (2 * math.pi) * #items + 0.5) % #items) + 1
  end
  for i, it in ipairs(items) do
    local a = (i - 1) / #items * math.pi * 2 - math.pi / 2
    local p = c + vec2(math.cos(a), math.sin(a)) * (152 * scale)
    local on = it.on()
    local hov = hovered == i
    local s = (hov and 1.1 or 1) * 37 * scale
    ui.drawRectFilled(p - vec2(s, s), p + vec2(s, s), on and rgbm(1, 1, 1, 0.18 * e) or rgbm(1, 1, 1, (hov and 0.1 or 0.05) * e), 22 * scale)
    ui.drawRect(p - vec2(s, s), p + vec2(s, s), on and rgbm(1, 1, 1, 0.6 * e) or rgbm(1, 1, 1, 0.12 * e), 22 * scale, nil, 1)
    ui.drawCircleFilled(p - vec2(0, 9 * scale), 9 * scale, T.alpha(T.hex(it.colour), e), 20)
    T.textCentered(it.label, p + vec2(0, 16 * scale), 11, T.alpha(C.white, e))
    if clickable then
      local clicked = require('ui/widgets').hit('ring_' .. i, p - vec2(s, s), vec2(s * 2, s * 2))
      if clicked then it.flip() end
    end
  end
  local cur = items[hovered or 1]
  T.textCentered(cur.label, c - vec2(0, 10), 18, T.alpha(C.white, e), 'medium')
  local on = cur.on()
  T.textCentered(on and 'On' or 'Off', c + vec2(0, 16), 13, T.alpha(on and C.ok or C.muted, e))
  return hovered
end

function M.reset() opened = 0 end

return M
