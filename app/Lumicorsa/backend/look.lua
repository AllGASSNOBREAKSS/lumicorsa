--[[
  Lumicorsa look pipeline: everything runs as CSP Lua shaders, no ReShade, no DLL, no third-party files.

  Where it draws: `ui.onExclusiveHUD` is the first UI callback of the frame. A fullscreen `ui.renderShader` there lands
  after the finished scene (CSP post-processing and the upscaler included) and before AC's HUD and every app window, so
  apps, chat and the Lumicorsa windows are never graded. Inputs are `dynamic::screen` and `dynamic::depth`.

  Passes per frame, each skipped when its effect is off (groups in brackets are what cost measurement reports):
    neural   4 full-res conv layers                                [neural]
    adapt    16x9 log-luminance + 1x1 temporal adaptation            [exposure]
    bloom    prefilter 1/2 -> down 1/4..1/32 -> up 1/16..1/2        [bloom]
    flare    ghosts + halo from the 1/8 bloom octave                [sun]
    shafts   sky mask + radial blur toward the sun                  [sun]
    ao       contact AO from depth + separable blur                 [ao]
    clarity  quarter-res luma + separable Gaussian                  [detail]
    dof      quarter-res colour + separable Gaussian                [dof]
    final    fullscreen composite                                   [grade]
  M.sent holds the exact values handed to the final shader on the last frame (self-test readback).
]]

local M = {}

local APP_DIR = ac.getFolder(ac.FolderID.ACAppsLua) .. '/Lumicorsa'
local F16 = render.TextureFormat.R16G16B16A16.Float
local SCREEN, DEPTH = 'dynamic::screen', 'dynamic::depth'

-- ---------------------------------------------------------------------------------------------- shader sources
local common = io.load(APP_DIR .. '/shaders/common.hlsl') or ''
function M.shader(name)
  local code = io.load(APP_DIR .. '/shaders/' .. name .. '.hlsl')
  if not code then error('Lumicorsa: missing shaders/' .. name .. '.hlsl') end
  if code:find('// @common', 1, true) then code = common .. '\n' .. code end
  return code
end

local function pass(name, textures, values)
  return { async = true, textures = textures, values = values, shader = M.shader(name) }
end

-- Every table keeps the same keys for its whole life (CSP recompiles a shader when keys change).
local P = {
  nn0 = pass('nn_0', { txPLIn = SCREEN }, { gPLTexel = vec2() }),
  nn1 = pass('nn_1', { txPLIn = false }, { gPLTexel = vec2() }),
  nn2 = pass('nn_2', { txPLIn = false }, { gPLTexel = vec2() }),
  nn3 = pass('nn_3', { txPLIn = false, txPLBase = SCREEN }, { gPLTexel = vec2(), gPLIntensity = 0 }),
  lumSmall = pass('lum_small', { txPLSrc = SCREEN }, { gPLSrcTexel = vec2() }),
  adapt = pass('adapt', { txPLSmall = false, txPLPrev = false }, { gPLRate = 0.05 }),
  prefilter = pass('bloom_prefilter', { txPLSrc = SCREEN }, { gPLSrcTexel = vec2(), gPLRecover = 0, gPLExposure = 0, gPLThreshold = 1.25 }),
  down = pass('bloom_down', { txPLSrc = false }, { gPLSrcTexel = vec2() }),
  up = pass('bloom_up', { txPLSkip = false, txPLLow = false }, { gPLLowTexel = vec2() }),
  flare = pass('flare', { txPLSrc = false }, { gPLAspect = 1.78 }),
  shMask = pass('shafts_mask', { txPLSrc = SCREEN, txPLDepth = DEPTH, txPLProbe = false }, { gPLSrcTexel = vec2() }),
  shBlur = pass('shafts_blur', { txPLSrc = false }, { gPLSunUV = vec2(0.5, 0.3), gPLLength = 0.8 }),
  ao = pass('ao', { txPLDepth = DEPTH, txPLProbe = false }, { gPLTexel = vec2(), gPLNear = 0.1, gPLFar = 10000, gPLRadius = 60 }),
  lumaQ = pass('luma_quarter', { txPLSrc = SCREEN }, { gPLSrcTexel = vec2() }),
  blur = pass('blur9', { txPLSrc = false }, { gPLDir = vec2() }),
  colorQ = pass('color_quarter', { txPLSrc = SCREEN }, { gPLSrcTexel = vec2() }),
  blurC = pass('blur9c', { txPLSrc = false }, { gPLDir = vec2() }),
  probe = pass('depth_probe', { txPLDepth = DEPTH }, {}),
}

-- Defaults for every look value; presets and sliders overwrite them.
M.DEFAULTS = {
  PL_Exposure = 0, PL_HighlightRecover = 0.55, PL_Temperature = 0, PL_Tint = 0, PL_BloomIntensity = 0.22, PL_Halation = 0.25,
  PL_FilmicStrength = 0.75, PL_Contrast = 0.08, PL_Lift = 0.1, PL_Saturation = -0.04, PL_Vibrance = 0.12, PL_BlackPoint = 0.004,
  PL_ShadowTint = vec3(0.50, 0.50, 0.52), PL_HighlightTint = vec3(0.51, 0.50, 0.49),
  PL_HazeDensity = 0.30, PL_HazeStart = 0.02, PL_HazeColor = vec3(0.62, 0.70, 0.80), PL_AerialDesat = 0.35, PL_Mist = 0.2,
  PL_Clarity = 0.22, PL_Sharpen = 0.35, PL_ChromaAb = 0.12, PL_Vignette = 0.25, PL_Grain = 0.08, PL_Mix = 1.0,
  PL_Shafts = 0.4, PL_Flare = 0.25, PL_AO = 0.6, PL_Dof = 0.5,
}

local finalValues = {
  gPLTexel = vec2(), gPLSize = vec2(), gPLLight = 1, gPLAtmos = 1, gPLDetail = 1, gPLLens = 1, gPLBloomOn = 1, gPLSplit = 0,
  gPLNear = 0.1, gPLFar = 10000, gPLTime = 0, gPLShaftsOn = 0, gPLFlareOn = 0, gPLAOOn = 0, gPLDofOn = 0,
  gPLSunColor = vec3(1.0, 0.86, 0.66), gPLFocus = 0, gPLAdaptOn = 0, gPLMistOn = 0, gPLCamHeight = 1.2,
  gPLCamLook = vec3(0, 0, 1), gPLCamUp = vec3(0, 1, 0), gPLCamSide = vec3(1, 0, 0), gPLTanHalf = vec2(1, 0.6),
}
for k, v in pairs(M.DEFAULTS) do finalValues[k] = v end
M.sent = finalValues

local final = {
  async = true, p1 = vec2(), p2 = vec2(), blendMode = render.BlendMode.Opaque,
  textures = {
    txPLBase = SCREEN, txPLScreen = SCREEN, txPLDepth = DEPTH, txPLBloom = false, txPLWide = false, txPLLumaQ = false,
    txPLProbe = false, txPLShafts = false, txPLFlare = false, txPLAO = false, txPLDofBlur = false, txPLAdapt = false,
  },
  values = finalValues,
  shader = M.shader('final'),
}

-- ---------------------------------------------------------------------------------------------- render targets
local T = nil
local W, H = 0, 0
local adaptFlip = false

local function canvas(w, h)
  return ui.ExtraCanvas(vec2(math.max(1, math.floor(w)), math.max(1, math.floor(h))), 1, render.AntialiasingMode.None, F16)
end

local function dispose()
  if T then for _, c in pairs(T) do c:dispose() end end
  T = nil
end

-- Canvases are created once per resolution, never per frame.
local function ensureTargets()
  local size = ac.getSim().windowSize
  if T and size.x == W and size.y == H then return end
  dispose()
  W, H = size.x, size.y
  T = {
    nnA = canvas(W, H), nnB = canvas(W, H), nnOut = canvas(W, H),
    lumS = canvas(16, 9), adaptA = canvas(1, 1), adaptB = canvas(1, 1),
    d2 = canvas(W / 2, H / 2), d4 = canvas(W / 4, H / 4), d8 = canvas(W / 8, H / 8), d16 = canvas(W / 16, H / 16), d32 = canvas(W / 32, H / 32),
    u16 = canvas(W / 16, H / 16), u8 = canvas(W / 8, H / 8), u4 = canvas(W / 4, H / 4), u2 = canvas(W / 2, H / 2),
    flare = canvas(W / 4, H / 4),
    shA = canvas(W / 2, H / 2), shB = canvas(W / 2, H / 2),
    ao = canvas(W / 2, H / 2), aoB = canvas(W / 2, H / 2),
    q = canvas(W / 4, H / 4), qb = canvas(W / 4, H / 4),
    cq = canvas(W / 4, H / 4), cqb = canvas(W / 4, H / 4),
    gq = canvas(W / 4, H / 4), gqb = canvas(W / 4, H / 4),
    probe = canvas(1, 1),
  }
end

local function texel(c) local s = c:size(); return vec2(1 / s.x, 1 / s.y) end

-- Screen position of the sun (or moon), nil when it's off screen or behind the camera.
local function sunScreenUV()
  local sim = ac.getSim()
  local dir = sim.lightDirection
  if not dir then return nil end
  if dir.y < 0 then dir = vec3(-dir.x, -dir.y, -dir.z) end
  local look = sim.cameraLook
  if look and (look.x * dir.x + look.y * dir.y + look.z * dir.z) < 0.05 then return nil end
  local cam = sim.cameraPosition
  local p = render.projectPoint(vec3(cam.x + dir.x * 5000, cam.y + dir.y * 5000, cam.z + dir.z * 5000))
  if not p or p.x ~= p.x or math.abs(p.x) == math.huge or math.abs(p.y) == math.huge then return nil end
  if p.x > 2 or p.y > 2 then p = vec2(p.x / W, p.y / H) end
  return p
end

-- Which effect groups ran on the last frame (cost measurement and the GPU budget use these names).
M.active = {}

-- ---------------------------------------------------------------------------------------------- frame
-- `s`: light, atmos, detail, lens, neural, nrGain, shafts, flare, ao, dof, focus, adaptRate (0 = off), mist, split,
-- conflict, off (set of groups disabled by the GPU budget), values (PL_*). Returns true once every pass has drawn.
function M.render(s)
  ensureTargets()
  local ok = true
  local function run(target, p) if not target:updateWithShader(p) then ok = false end end
  local full = vec2(1 / W, 1 / H)
  local v = s.values
  local off = s.off or {}
  local sim = ac.getSim()
  local near, far = math.max(sim.cameraClipNear or 0.1, 0.01), math.max(sim.cameraClipFar or 10000, 100)
  local act = M.active
  for k in pairs(act) do act[k] = nil end

  local base = SCREEN
  if s.neural and s.nrGain > 0 and not off.neural then
    P.nn0.values.gPLTexel = full; run(T.nnA, P.nn0)
    P.nn1.values.gPLTexel = full; P.nn1.textures.txPLIn = T.nnA; run(T.nnB, P.nn1)
    P.nn2.values.gPLTexel = full; P.nn2.textures.txPLIn = T.nnB; run(T.nnA, P.nn2)
    P.nn3.values.gPLTexel = full; P.nn3.values.gPLIntensity = s.nrGain; P.nn3.textures.txPLIn = T.nnA; run(T.nnOut, P.nn3)
    base = T.nnOut
    act.neural = true
  end

  local adaptOn = (s.adaptRate or 0) > 0 and not off.exposure
  if adaptOn then
    P.lumSmall.textures.txPLSrc = base; P.lumSmall.values.gPLSrcTexel = full; run(T.lumS, P.lumSmall)
    adaptFlip = not adaptFlip
    local dst, prev = adaptFlip and T.adaptA or T.adaptB, adaptFlip and T.adaptB or T.adaptA
    P.adapt.textures.txPLSmall, P.adapt.textures.txPLPrev = T.lumS, prev
    P.adapt.values.gPLRate = math.min(1, s.adaptRate * (ac.getUI().dt or 0.016) * 4)
    run(dst, P.adapt)
    final.textures.txPLAdapt = dst
    act.exposure = true
  end

  local recover = s.conflict and 0 or v.PL_HighlightRecover
  local filmic = s.conflict and 0 or v.PL_FilmicStrength

  local mistOn = s.mist and (v.PL_Mist or 0) > 0 and not off.mist
  local needDepth = s.atmos or s.ao or s.shafts or s.dof or mistOn
  if needDepth then run(T.probe, P.probe) end

  local bloomOn = s.light and ((v.PL_BloomIntensity or 0) > 0 or (v.PL_Halation or 0) > 0) and not off.bloom
  local flareOn = s.light and s.flare and (v.PL_Flare or 0) > 0 and not off.sun
  if bloomOn or flareOn then
    local pf = P.prefilter
    pf.textures.txPLSrc = base; pf.values.gPLSrcTexel = full
    pf.values.gPLRecover = recover; pf.values.gPLExposure = v.PL_Exposure or 0
    pf.values.gPLThreshold = s.conflict and 0.8 or 1.25
    run(T.d2, pf)
    for _, l in ipairs({ { T.d2, T.d4 }, { T.d4, T.d8 }, { T.d8, T.d16 }, { T.d16, T.d32 } }) do
      P.down.textures.txPLSrc = l[1]; P.down.values.gPLSrcTexel = texel(l[1]); run(l[2], P.down)
    end
    if bloomOn then
      for _, l in ipairs({ { T.d16, T.d32, T.u16 }, { T.d8, T.u16, T.u8 }, { T.d4, T.u8, T.u4 }, { T.d2, T.u4, T.u2 } }) do
        P.up.textures.txPLSkip = l[1]; P.up.textures.txPLLow = l[2]; P.up.values.gPLLowTexel = texel(l[2]); run(l[3], P.up)
      end
      act.bloom = true
    end
    if flareOn then
      P.flare.textures.txPLSrc = T.d8; P.flare.values.gPLAspect = W / H; run(T.flare, P.flare)
      act.sun = true
    end
  end

  local sun = (s.light and s.shafts and (v.PL_Shafts or 0) > 0 and not off.sun) and sunScreenUV() or nil
  if sun then
    P.shMask.textures.txPLSrc = base; P.shMask.textures.txPLProbe = T.probe; P.shMask.values.gPLSrcTexel = full
    run(T.shA, P.shMask)
    P.shBlur.textures.txPLSrc = T.shA; P.shBlur.values.gPLSunUV = sun; P.shBlur.values.gPLLength = 0.85
    run(T.shB, P.shBlur)
    act.sun = true
  end

  local aoOn = s.ao and (v.PL_AO or 0) > 0 and not off.ao
  if aoOn then
    local a = P.ao
    a.textures.txPLProbe = T.probe
    a.values.gPLTexel, a.values.gPLNear, a.values.gPLFar = texel(T.ao), near, far
    run(T.ao, a)
    local at = texel(T.ao)
    P.blur.textures.txPLSrc = T.ao;  P.blur.values.gPLDir = vec2(at.x, 0); run(T.aoB, P.blur)
    P.blur.textures.txPLSrc = T.aoB; P.blur.values.gPLDir = vec2(0, at.y); run(T.ao, P.blur)
    act.ao = true
  end

  local clarityOn = s.detail and (v.PL_Clarity or 0) > 0 and not off.detail
  if clarityOn then
    P.lumaQ.textures.txPLSrc = base; P.lumaQ.values.gPLSrcTexel = full; run(T.q, P.lumaQ)
    local qt = texel(T.q)
    P.blur.textures.txPLSrc = T.q;  P.blur.values.gPLDir = vec2(qt.x, 0); run(T.qb, P.blur)
    P.blur.textures.txPLSrc = T.qb; P.blur.values.gPLDir = vec2(0, qt.y); run(T.q, P.blur)
    act.detail = true
  end

  local dofOn = s.dof and (v.PL_Dof or 0) > 0 and not off.dof
  if dofOn then
    P.colorQ.textures.txPLSrc = base; P.colorQ.values.gPLSrcTexel = full; run(T.cq, P.colorQ)
    local ct = texel(T.cq)
    P.blurC.textures.txPLSrc = T.cq;  P.blurC.values.gPLDir = vec2(ct.x * 2, 0); run(T.cqb, P.blurC)
    P.blurC.textures.txPLSrc = T.cqb; P.blurC.values.gPLDir = vec2(0, ct.y * 2); run(T.cq, P.blurC)
    act.dof = true
  end

  -- Final composite, fullscreen in UI space
  final.p2 = ac.getUI().windowSize
  local tx = final.textures
  tx.txPLBase = base
  tx.txPLBloom, tx.txPLWide, tx.txPLLumaQ, tx.txPLProbe = T.u2, T.u8, T.q, T.probe
  tx.txPLShafts, tx.txPLFlare, tx.txPLAO, tx.txPLDofBlur = T.shB, T.flare, T.ao, T.cq
  if not tx.txPLAdapt then tx.txPLAdapt = T.adaptA end
  local fv = finalValues
  for k, x in pairs(v) do if fv[k] ~= nil then fv[k] = x end end
  fv.PL_HighlightRecover, fv.PL_FilmicStrength = recover, filmic
  if not clarityOn then fv.PL_Clarity = 0 end
  fv.gPLTexel, fv.gPLSize = full, vec2(W, H)
  fv.gPLLight, fv.gPLAtmos = s.light and 1 or 0, s.atmos and 1 or 0
  fv.gPLDetail, fv.gPLLens = s.detail and 1 or 0, s.lens and 1 or 0
  fv.gPLBloomOn, fv.gPLSplit = bloomOn and 1 or 0, s.split and 1 or 0
  fv.gPLShaftsOn, fv.gPLFlareOn = sun and 1 or 0, flareOn and 1 or 0
  fv.gPLAOOn, fv.gPLDofOn = aoOn and 1 or 0, dofOn and 1 or 0
  fv.gPLAdaptOn, fv.gPLMistOn = adaptOn and 1 or 0, mistOn and 1 or 0
  fv.gPLFocus = s.focus or 0
  fv.gPLNear, fv.gPLFar = near, far
  fv.gPLTime = os.preciseClock()
  if mistOn then
    local car = ac.getCar(0)
    local cam = sim.cameraPosition
    fv.gPLCamHeight = car and (cam.y - car.position.y + 0.3) or 1.2
    fv.gPLCamLook, fv.gPLCamUp, fv.gPLCamSide = sim.cameraLook, sim.cameraUp, sim.cameraSide
    local ty = math.tan(math.rad(sim.cameraFOV or 56) / 2)
    fv.gPLTanHalf = vec2(ty * W / H, ty)
    act.mist = true
  end
  act.grade = true
  if not ui.renderShader(final) then ok = false end
  return ok
end

-- ---------------------------------------------------------------------------------------------- glass backdrop
-- One blurred copy of the game frame per UI frame (quarter res, two separable passes), shared by every Lumicorsa
-- window. Windows draw it with ui.drawImageRounded: one backdrop layer per window, nothing stacked.
local glassFrame = -1
function M.glass(frameIndex)
  ensureTargets()
  if glassFrame ~= frameIndex then
    glassFrame = frameIndex
    P.colorQ.textures.txPLSrc = SCREEN; P.colorQ.values.gPLSrcTexel = vec2(1 / W, 1 / H); T.gq:updateWithShader(P.colorQ)
    local t = texel(T.gq)
    P.blurC.textures.txPLSrc = T.gq;  P.blurC.values.gPLDir = vec2(t.x * 3, 0); T.gqb:updateWithShader(P.blurC)
    P.blurC.textures.txPLSrc = T.gqb; P.blurC.values.gPLDir = vec2(0, t.y * 3); T.gq:updateWithShader(P.blurC)
  end
  return T.gq
end

function M.release() dispose() end

return M
