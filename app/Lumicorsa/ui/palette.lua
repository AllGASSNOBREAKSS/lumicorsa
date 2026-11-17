--[[
  Command palette (Ctrl+K or the header search pill): fuzzy search over every setting label, card title and action in
  the registry. Enter (or a click) switches to the tab and flashes the card in amber twice.
]]

local T = require('ui/theme')
local W = require('ui/widgets')
local C = T.C

local M = { open = false, query = '', selected = 1, justOpened = false }

-- Subsequence fuzzy score: higher is better, nil when the query letters aren't all present in order.
function M.score(query, text)
  query, text = query:lower(), text:lower()
  if query == '' then return 0 end
  local s = text:find(query, 1, true)
  if s then return 1000 - s - #text * 0.1 end
  local qi, score, last = 1, 0, 0
  for i = 1, #text do
    if text:sub(i, i) == query:sub(qi, qi) then
      score = score + (i == last + 1 and 5 or 1)
      last = i; qi = qi + 1
      if qi > #query then return score - #text * 0.1 end
    end
  end
  return nil
end

function M.entries(R, tabsLabels)
  local out, seen = {}, {}
  for _, d in ipairs(R.all) do
    if d.tab then
      out[#out + 1] = { label = d.label, where = tabsLabels[d.tab] .. ' · ' .. d.card, tab = d.tab, card = d.card, action = d.kind == 'action' and d or nil }
      if not seen[d.tab .. d.card] then
        seen[d.tab .. d.card] = true
        out[#out + 1] = { label = d.card, where = tabsLabels[d.tab], tab = d.tab, card = d.card }
      end
    end
  end
  return out
end

function M.show() M.open, M.query, M.selected, M.justOpened = true, '', 1, true end
function M.hide() M.open = false end

-- Draws inside the dashboard window. `go(entry)` navigates; returns nothing.
function M.draw(entries, size, dt, go)
  if not M.open then return end
  ui.drawRectFilled(vec2(), size, rgbm(0, 0, 0, 0.35), 28)
  local w = 640
  local p1 = vec2((size.x - w) / 2, 110)
  local results = {}
  local q = M.query
  if q == '' then
    for _, e in ipairs(entries) do if e.action then results[#results + 1] = { e = e, s = 0 } end end
  else
    for _, e in ipairs(entries) do
      local s = M.score(q, e.label) or (M.score(q, e.where) and M.score(q, e.where) - 200)
      if s then results[#results + 1] = { e = e, s = s } end
    end
    table.sort(results, function (a, b) return a.s > b.s end)
  end
  local n = math.min(#results, 9)
  local h = 60 + math.max(n, 1) * 46 + 16 + 40
  ui.drawRectFilled(p1, p1 + vec2(w, h), rgbm(16 / 255, 17 / 255, 20 / 255, 0.94), 22)
  ui.drawRect(p1, p1 + vec2(w, h), rgbm(1, 1, 1, 0.16), 22, nil, 1)
  -- search input
  ui.setCursor(p1 + vec2(48, 18))
  ui.setNextItemWidth(w - 130)
  if M.justOpened then ui.setKeyboardFocusHere(); M.justOpened = false end
  ui.pushStyleColor(ui.StyleColor.FrameBg, rgbm(0, 0, 0, 0))
  local newQ, changed, enter = ui.inputText('##lumi_palette', M.query, ui.InputTextFlags.None)
  ui.popStyleColor()
  if changed then M.query = newQ; M.selected = 1 end
  if M.query == '' then T.text('Try rain, chase, bloom, ReShade', p1 + vec2(52, 19), 17, C.faint) end
  ui.drawCircle(p1 + vec2(26, 30), 7, C.text2, 16, 2)
  ui.drawLine(p1 + vec2(31, 35), p1 + vec2(36, 40), C.text2, 2)
  local escP = p1 + vec2(w - 56, 18)
  local escClicked = W.hit('palette_esc', escP, vec2(40, 24))
  ui.drawRectFilled(escP, escP + vec2(40, 24), rgbm(1, 1, 1, 0.10), 6)
  T.textCentered('Esc', escP + vec2(20, 12), 12, C.text2)
  ui.drawLine(p1 + vec2(0, 60), p1 + vec2(w, 60), C.line, 1)
  if ui.keyPressed(ui.Key.Down) then M.selected = math.min(n, M.selected + 1) end
  if ui.keyPressed(ui.Key.Up) then M.selected = math.max(1, M.selected - 1) end
  if escClicked or ui.keyPressed(ui.Key.Escape) then M.hide(); return end
  for i = 1, n do
    local r = results[i].e
    local rp = p1 + vec2(8, 68 + (i - 1) * 46)
    local clicked, hovered = W.hit('palette_r' .. i, rp, vec2(w - 16, 42))
    if hovered then M.selected = i end
    if i == M.selected then ui.drawRectFilled(rp, rp + vec2(w - 16, 42), rgbm(1, 1, 1, 0.08), 12) end
    ui.drawRectFilled(rp + vec2(12, 6), rp + vec2(42, 36), rgbm(1, 1, 1, 0.08), 9)
    ui.drawCircleFilled(rp + vec2(27, 21), 5, r.action and C.yellow or C.blue, 12)
    T.text(r.label, rp + vec2(54, 12), 14, C.text)
    T.textRight(r.where, rp + vec2(w - 30, 13), 12, T.hex('#8A8D94'))
    if clicked or (enter and i == M.selected) then M.hide(); go(r); return end
  end
  if n == 0 then T.textCentered('No setting matches that. Try a shorter word.', p1 + vec2(w / 2, 90), 14, C.muted) end
  ui.drawLine(p1 + vec2(0, h - 40), p1 + vec2(w, h - 40), C.line, 1)
  T.text('Enter to open', p1 + vec2(18, h - 28), 12, T.hex('#8A8D94'))
  T.text('Alt+P toggles the panel in game', p1 + vec2(130, h - 28), 12, T.hex('#8A8D94'))
end

return M
