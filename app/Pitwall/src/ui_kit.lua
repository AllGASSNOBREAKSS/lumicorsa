--[[
  Pitwall UI kit: frosted-glass panel, Space Grotesk text (DWrite) and a small set of declarative widgets.

  A page is a list of cards; a card is { title, icon, color, rows }. Row kinds:
    toggle  { label, get, set, apply?, disabled? }          slider { label, min, max, get, set, fmt?, apply? }
    choice  { label, options = {{label, value}}, get, set }  info   { label, value, color? }
    buttons { items = {{label, on, primary?}} }              note   { text, color? }
  `apply` = 'restart' | 'next' adds a badge (needs AC restart / applies next launch). Live settings have no badge.
  Rows are skipped while scrolled out of view, so nothing off-screen can be clicked. Scrolling is mouse-wheel only:
  no scrollbar.
]]

local K = {}

K.C = {
  white  = rgbm(0.97, 0.97, 0.98, 1),
  muted  = rgbm(0.97, 0.97, 0.98, 0.56),
  faint  = rgbm(0.97, 0.97, 0.98, 0.30),
  black  = rgbm(0.03, 0.04, 0.06, 1),
  blue   = rgbm(0.30, 0.62, 1.00, 1),
  orange = rgbm(1.00, 0.56, 0.20, 1),
  yellow = rgbm(1.00, 0.83, 0.26, 1),
  red    = rgbm(1.00, 0.32, 0.34, 1),
  green  = rgbm(0.32, 0.88, 0.54, 1),
  card   = rgbm(1, 1, 1, 0.045),
  line   = rgbm(1, 1, 1, 0.08),
  hover  = rgbm(1, 1, 1, 0.07),
  track  = rgbm(1, 1, 1, 0.14),
}
local C = K.C

local FONT = { regular = 'Space Grotesk:fonts', medium = 'Space Grotesk:fonts;Weight=Medium', bold = 'Space Grotesk:fonts;Weight=Bold' }

function K.text(str, pos, size, color, weight)
  ui.pushDWriteFont(FONT[weight or 'regular'])
  ui.dwriteDrawText(str, size or 13, pos, color or C.white)
  ui.popDWriteFont()
end

function K.measure(str, size, weight, wrap)
  ui.pushDWriteFont(FONT[weight or 'regular'])
  local m = ui.measureDWriteText(str, size or 13, wrap or -1)
  ui.popDWriteFont()
  return m
end

local function alpha(c, a) return rgbm(c.r, c.g, c.b, c.mult * a) end
K.alpha = alpha

-- ---------------------------------------------------------------------------------------------- glass background
local glass = nil
function K.glass(size, shaderCode)
  if not glass then
    glass = {
      async = true, p1 = vec2(), p2 = vec2(), uv1 = vec2(), uv2 = vec2(1, 1), blendMode = render.BlendMode.AlphaBlend,
      textures = { txPWScreen = 'dynamic::screen' },
      values = { gPWUvMin = vec2(), gPWUvMax = vec2(1, 1), gPWSize = vec2(), gPWTexel = vec2(), gPWTint = rgbm(0.035, 0.05, 0.085, 0.62), gPWRadius = 16 },
      shader = shaderCode,
    }
  end
  local screen = ac.getUI().windowSize
  local pos = ui.windowPos()
  local uv1 = vec2(pos.x / screen.x, pos.y / screen.y)
  local uv2 = vec2((pos.x + size.x) / screen.x, (pos.y + size.y) / screen.y)
  glass.p2 = size
  glass.uv1, glass.uv2 = uv1, uv2
  glass.values.gPWUvMin, glass.values.gPWUvMax = uv1, uv2
  glass.values.gPWSize = size
  glass.values.gPWTexel = vec2(1 / screen.x, 1 / screen.y)
  if not ui.renderShader(glass) then
    ui.drawRectFilled(vec2(), size, rgbm(0.035, 0.05, 0.085, 0.92), 16)   -- until the shader is compiled
  end
end

-- ---------------------------------------------------------------------------------------------- primitives
local function hit(id, p, size)
  ui.setCursor(p)
  local clicked = ui.invisibleButton(id, size)
  return clicked, ui.itemHovered(), ui.itemActive()
end
K.hit = hit

function K.badge(label, p, color)
  local m = K.measure(label, 9.5, 'bold')
  ui.drawRectFilled(p, p + vec2(m.x + 10, 15), alpha(color, 0.18), 4)
  K.text(label, p + vec2(5, 1.5), 9.5, color, 'bold')
  return m.x + 10
end

local function switch(p, on, color, enabled)
  local a = enabled and 1 or 0.4
  ui.drawRectFilled(p, p + vec2(38, 20), on and alpha(color, a) or alpha(C.track, a), 10)
  ui.drawCircleFilled(p + vec2(on and 28 or 10, 10), 7, on and alpha(C.black, 0.9 * a) or alpha(C.white, 0.75 * a), 20)
end

-- ---------------------------------------------------------------------------------------------- rows
local H = { toggle = 34, slider = 44, info = 26, buttons = 40, stepper = 34, segmented = 58 }

local function rowHeight(r, w)
  if r.kind == 'choice' then return #r.options <= 4 and H.segmented or H.stepper end
  if r.kind == 'note' then return K.measure(r.text, 11.5, 'regular', w).y + 8 end
  if r.kind == 'presets' then return math.ceil(#r.items / 2) * 40 end
  return H[r.kind] or 30
end
K.rowHeight = rowHeight

local function labelWithBadge(r, p, enabled)
  local col = enabled and C.white or C.faint
  K.text(r.label, p, 13, col, 'medium')
  if r.apply == 'restart' or r.apply == 'next' then
    local m = K.measure(r.label, 13, 'medium')
    K.badge(r.apply == 'restart' and 'RESTART' or 'NEXT LAUNCH', p + vec2(m.x + 8, 1), r.apply == 'restart' and C.orange or C.yellow)
  end
end

local function fmtValue(r, v)
  if r.fmt then return type(r.fmt) == 'function' and r.fmt(v) or string.format(r.fmt, v) end
  return string.format('%.2f', v)
end

local draw = {}

function draw.toggle(r, p, w, color, enabled, id)
  local on = r.get() and true or false
  local clicked, hovered = hit(id, p, vec2(w, H.toggle))
  if hovered and enabled then ui.drawRectFilled(p - vec2(6, 0), p + vec2(w + 6, H.toggle), C.hover, 8) end
  labelWithBadge(r, p + vec2(0, 8), enabled)
  switch(p + vec2(w - 40, 7), on, color, enabled)
  if clicked and enabled then r.set(not on) end
end

function draw.slider(r, p, w, color, enabled, id)
  local v = r.get() or r.min
  labelWithBadge(r, p + vec2(0, 2), enabled)
  local vs = fmtValue(r, v)
  local m = K.measure(vs, 12.5, 'bold')
  K.text(vs, p + vec2(w - m.x, 3), 12.5, enabled and C.yellow or C.faint, 'bold')
  local ty = p.y + 30
  local _, hovered, active = hit(id, vec2(p.x, ty - 9), vec2(w, 20))
  local t = (v - r.min) / (r.max - r.min)
  t = math.min(math.max(t, 0), 1)
  ui.drawRectFilled(vec2(p.x, ty - 2), vec2(p.x + w, ty + 2), C.track, 2)
  ui.drawRectFilled(vec2(p.x, ty - 2), vec2(p.x + w * t, ty + 2), alpha(color, enabled and 1 or 0.4), 2)
  ui.drawCircleFilled(vec2(p.x + w * t, ty), (hovered or active) and 8 or 6.5, enabled and C.white or C.faint, 20)
  if active and enabled then
    local nt = math.min(math.max((ui.mouseLocalPos().x - p.x) / w, 0), 1)
    local nv = r.min + (r.max - r.min) * nt
    if r.step then nv = math.floor(nv / r.step + 0.5) * r.step end
    if nv ~= v then r.set(nv) end
  end
end

function draw.info(r, p, w, color)
  K.text(r.label, p + vec2(0, 4), 12.5, C.muted, 'regular')
  local vs = tostring(r.value)
  local m = K.measure(vs, 12.5, 'medium')
  K.text(vs, p + vec2(w - m.x, 4), 12.5, r.color or C.white, 'medium')
end

function draw.note(r, p, w)
  local h = rowHeight(r, w)
  ui.pushDWriteFont(FONT.regular)
  ui.dwriteDrawTextClipped(r.text, 11.5, p + vec2(0, 2), p + vec2(w, h), ui.Alignment.Start, ui.Alignment.Start, true, r.color or C.muted)
  ui.popDWriteFont()
end

local function button(label, p, size, primary, color, enabled, id)
  local clicked, hovered = hit(id, p, size)
  local bg = primary and alpha(color, enabled and (hovered and 1 or 0.88) or 0.3) or (hovered and enabled and rgbm(1, 1, 1, 0.14) or rgbm(1, 1, 1, 0.08))
  ui.drawRectFilled(p, p + size, bg, 8)
  local m = K.measure(label, 12.5, 'medium')
  K.text(label, p + vec2((size.x - m.x) / 2, (size.y - 16) / 2), 12.5, primary and C.black or (enabled and C.white or C.faint), 'medium')
  return clicked and enabled
end
K.button = button

function draw.buttons(r, p, w, color, enabled, id)
  local n = #r.items
  local bw = (w - (n - 1) * 8) / n
  for i, it in ipairs(r.items) do
    local en = enabled and not it.disabled
    if button(it.label, p + vec2((i - 1) * (bw + 8), 4), vec2(bw, 32), it.primary, color, en, id .. '_' .. i) then it.on() end
  end
end

function draw.presets(r, p, w, color, enabled, id)
  local bw = (w - 8) / 2
  for i, it in ipairs(r.items) do
    local col, row = (i - 1) % 2, math.floor((i - 1) / 2)
    local last = i == #r.items and col == 0
    local size = vec2(last and w or bw, 32)
    if button(it.label, p + vec2(col * (bw + 8), row * 40), size, it.active, color, enabled, id .. '_' .. i) then it.on() end
  end
end

local function optionIndex(r)
  local v = r.get()
  for i, o in ipairs(r.options) do if tostring(o.value) == tostring(v) then return i end end
  return nil
end

function draw.choice(r, p, w, color, enabled, id)
  local idx = optionIndex(r)
  if #r.options <= 4 then
    labelWithBadge(r, p + vec2(0, 2), enabled)
    local y = p.y + 24
    local sw = w / #r.options
    ui.drawRectFilled(vec2(p.x, y), vec2(p.x + w, y + 28), rgbm(1, 1, 1, 0.06), 8)
    for i, o in ipairs(r.options) do
      local sp = vec2(p.x + (i - 1) * sw, y)
      local clicked, hovered = hit(id .. '_' .. i, sp, vec2(sw, 28))
      local sel = i == idx
      if sel then ui.drawRectFilled(sp + vec2(2, 2), sp + vec2(sw - 2, 26), alpha(color, enabled and 1 or 0.4), 6)
      elseif hovered and enabled then ui.drawRectFilled(sp + vec2(2, 2), sp + vec2(sw - 2, 26), C.hover, 6) end
      local m = K.measure(o.label, 11.5, 'medium')
      local label = o.label
      K.text(label, sp + vec2(math.max((sw - m.x) / 2, 4), 6.5), 11.5, sel and C.black or (enabled and C.white or C.faint), 'medium')
      if clicked and enabled and not sel then r.set(o.value) end
    end
  else
    labelWithBadge(r, p + vec2(0, 8), enabled)
    local label = idx and r.options[idx].label or tostring(r.get())
    if #label > 26 then label = label:sub(1, 25) .. '…' end
    local m = K.measure(label, 12.5, 'medium')
    local right = p.x + w
    local textX = right - 22 - m.x
    local prevC, prevH = hit(id .. '_p', vec2(textX - 26, p.y + 4), vec2(22, 26))
    local nextC, nextH = hit(id .. '_n', vec2(right - 20, p.y + 4), vec2(20, 26))
    ui.drawIcon(ui.Icons.ArrowLeft, vec2(textX - 22, p.y + 10), vec2(textX - 10, p.y + 22), (prevH and enabled) and color or C.muted)
    ui.drawIcon(ui.Icons.ArrowRight, vec2(right - 14, p.y + 10), vec2(right - 2, p.y + 22), (nextH and enabled) and color or C.muted)
    K.text(label, vec2(textX, p.y + 8), 12.5, enabled and C.yellow or C.faint, 'medium')
    if enabled and (prevC or nextC) then
      local n = #r.options
      local i = idx or 1
      i = prevC and ((i - 2) % n + 1) or (i % n + 1)
      r.set(r.options[i].value)
    end
  end
end

-- ---------------------------------------------------------------------------------------------- cards and pages
local CARD_PAD, CARD_HEAD = 14, 34

local function cardHeight(card, w)
  local h = CARD_HEAD + CARD_PAD
  for _, r in ipairs(card.rows) do if not r.hidden then h = h + rowHeight(r, w - CARD_PAD * 2) end end
  return h
end

-- Draws a list of cards inside `rect` (x, y, w, h) scrolled by `scroll`; returns content height.
function K.page(cards, rect, scroll, pageId)
  local x, y0, w, h = rect.x, rect.y, rect.z, rect.w
  ui.pushClipRect(vec2(x - 4, y0), vec2(x + w + 4, y0 + h), true)
  local y = y0 - scroll
  for ci, card in ipairs(cards) do
    local ch = cardHeight(card, w)
    if y + ch > y0 and y < y0 + h then
      ui.drawRectFilled(vec2(x, y), vec2(x + w, y + ch), C.card, 12)
      ui.drawRect(vec2(x, y), vec2(x + w, y + ch), C.line, 12, nil, 1)
      ui.drawIcon(card.icon, vec2(x + CARD_PAD, y + 11), vec2(x + CARD_PAD + 16, y + 27), card.color)
      K.text(card.title:upper(), vec2(x + CARD_PAD + 24, y + 11), 11.5, C.white, 'bold')
      if card.badge then
        local m = K.measure(card.badge.label, 9.5, 'bold')
        K.badge(card.badge.label, vec2(x + w - CARD_PAD - m.x - 10, y + 11), card.badge.color)
      end
    end
    local ry = y + CARD_HEAD
    local rw = w - CARD_PAD * 2
    for ri, r in ipairs(card.rows) do
      if not r.hidden then
        local rh = rowHeight(r, rw)
        if ry + rh > y0 and ry < y0 + h then   -- visible: draw and allow interaction
          local enabled = not r.disabled
          draw[r.kind](r, vec2(x + CARD_PAD, ry), rw, card.color, enabled, pageId .. '_' .. ci .. '_' .. ri)
        end
        ry = ry + rh
      end
    end
    y = y + ch + 12
  end
  ui.popClipRect()
  return y + scroll - y0
end

return K
