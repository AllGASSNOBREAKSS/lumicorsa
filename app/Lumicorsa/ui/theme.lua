--[[
  Lumicorsa theme: design tokens (design/tokens.json), fonts and easing.

  Fonts: the design uses FK Grotesk, but the files in the design package are trial (personal use only) and there's no
  commercial licence in /licenses, so the app ships Inter and JetBrains Mono (both SIL OFL) in the same layout.
]]

local T = {}

local function hex(h, a)
  return rgbm(tonumber(h:sub(2, 3), 16) / 255, tonumber(h:sub(4, 5), 16) / 255, tonumber(h:sub(6, 7), 16) / 255, a or 1)
end
T.hex = hex

T.C = {
  header = rgbm(0, 0, 0, 0.88), glass = rgbm(20 / 255, 21 / 255, 25 / 255, 0.56), card = rgbm(0, 0, 0, 0.28),
  rail = rgbm(0, 0, 0, 0.32), line = rgbm(1, 1, 1, 0.08), border = rgbm(1, 1, 1, 0.16),
  text = hex('#FFFFFF'), text2 = hex('#C9CCD1'), muted = hex('#9C9FA6'), faint = hex('#6B6E75'), hint = hex('#7C7F86'),
  amber = hex('#FFB547'), yellow = hex('#F5C518'), red = hex('#E5383B'), blue = hex('#3D8BFF'), ok = hex('#28C840'),
  fill = rgbm(1, 1, 1, 0.12), white = hex('#FFFFFF'), black = hex('#0A0A0C'),
}
T.R = { window = 28, card = 20, control = 12, pill = 999 }

-- DWrite font strings (cached by CSP per name).
local FONTS = {
  light = 'Inter:fonts;Weight=Light', regular = 'Inter:fonts', medium = 'Inter:fonts;Weight=Medium',
  semibold = 'Inter:fonts;Weight=SemiBold', bold = 'Inter:fonts;Weight=Bold', mono = 'JetBrains Mono:fonts;Weight=Medium',
}

local function with(font, fn)
  ui.pushDWriteFont(FONTS[font] or FONTS.regular)
  local r = fn()
  ui.popDWriteFont()
  return r
end

function T.text(str, pos, size, color, weight)
  ui.pushDWriteFont(FONTS[weight or 'regular'])
  ui.dwriteDrawText(str, size, pos, color or T.C.text)
  ui.popDWriteFont()
end
function T.mono(str, pos, size, color) T.text(str, pos, size, color, 'mono') end
function T.measure(str, size, weight)
  return with(weight or 'regular', function () return ui.measureDWriteText(str, size) end)
end
function T.textRight(str, pos, size, color, weight)
  local m = T.measure(str, size, weight)
  T.text(str, vec2(pos.x - m.x, pos.y), size, color, weight)
end
function T.monoRight(str, pos, size, color) T.textRight(str, pos, size, color, 'mono') end
function T.textCentered(str, center, size, color, weight)
  local m = T.measure(str, size, weight)
  T.text(str, vec2(center.x - m.x / 2, center.y - m.y / 2), size, color, weight)
end
function T.wrapped(str, p1, p2, size, color, weight)
  ui.pushDWriteFont(FONTS[weight or 'regular'])
  ui.dwriteDrawTextClipped(str, size, p1, p2, ui.Alignment.Start, ui.Alignment.Start, true, color)
  ui.popDWriteFont()
end

-- ---------------------------------------------------------------------------------------------- motion
-- ease-out toward a target; reaches ~95% in 450 ms (design: fills 450 ms, toggles 250 ms)
local anim = {}
function T.ease(id, target, dt, ms)
  local cur = anim[id]
  if cur == nil or type(target) ~= 'number' then anim[id] = target; return target end
  local tau = (ms or 450) / 1000 / 3
  cur = cur + (target - cur) * (1 - math.exp(-(dt or 0.016) / tau))
  if math.abs(cur - target) < 1e-4 then cur = target end
  anim[id] = cur
  return cur
end

function T.mix(a, b, t) return rgbm(a.r + (b.r - a.r) * t, a.g + (b.g - a.g) * t, a.b + (b.b - a.b) * t, a.mult + (b.mult - a.mult) * t) end
function T.alpha(c, a) return rgbm(c.r, c.g, c.b, c.mult * a) end

return T
