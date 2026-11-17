--[[
  Photolap native pipeline: everything runs as CSP Lua shaders. No ReShade, no add-on DLL, no third-party files.

  Where it draws: `ui.onExclusiveHUD` is the first UI callback of the frame. A fullscreen `ui.renderShader` there lands
  after the scene is finished (post-processing and the upscaler included) and before AC's HUD and every app window, so
  the HUD, chat, leaderboards and this panel are never graded. Inputs are CSP's `dynamic::screen` (LDR frame) and
  `dynamic::depth`. Lua apps run in every session Content Manager launches, online servers included.

  Passes per frame (all optional, skipped when their effect is off):
    neural   4 full-res conv layers (Photolap Neural)                      -> nnOut
    bloom    prefilter 1/2 -> down 1/4..1/32 -> up 1/16..1/2              -> u2 (bloom), u8 (halation)
    clarity  quarter-res luma + separable Gaussian                         -> q
    probe    1x1 mean depth (picks the depth convention)                   -> probe
    final    fullscreen composite in the HUD callback
]]

local M = {}

local APP_DIR = ac.getFolder(ac.FolderID.ACAppsLua) .. '/Photolap'
local F16 = render.TextureFormat.R16G16B16A16.Float
local SCREEN, DEPTH = 'dynamic::screen', 'dynamic::depth'

-- ---------------------------------------------------------------------------------------------- shader sources
local common = io.load(APP_DIR .. '/shaders/common.hlsl') or ''
local function shader(name)
  local code = io.load(APP_DIR .. '/shaders/' .. name .. '.hlsl')
  if not code then error('Photolap: missing shaders/' .. name .. '.hlsl') end
  if code:find('// @common', 1, true) then code = common .. '\n' .. code end
  return code
end

local function pass(name, textures, values)
  return { async = true, textures = textures, values = values, shader = shader(name) }
end

-- Every table below keeps the same keys for its whole life (CSP recompiles a shader when keys change).
local P = {
  nn0 = pass('nn_0', { txPLIn = SCREEN }, { gPLTexel = vec2() }),
  nn1 = pass('nn_1', { txPLIn = false }, { gPLTexel = vec2() }),
  nn2 = pass('nn_2', { txPLIn = false }, { gPLTexel = vec2() }),
  nn3 = pass('nn_3', { txPLIn = false, txPLBase = SCREEN }, { gPLTexel = vec2(), gPLIntensity = 0 }),
  prefilter = pass('bloom_prefilter', { txPLSrc = SCREEN }, { gPLSrcTexel = vec2(), gPLRecover = 0, gPLExposure = 0, gPLThreshold = 1.25 }),
  down = pass('bloom_down', { txPLSrc = false }, { gPLSrcTexel = vec2() }),
  up = pass('bloom_up', { txPLSkip = false, txPLLow = false }, { gPLLowTexel = vec2() }),
  lumaQ = pass('luma_quarter', { txPLSrc = SCREEN }, { gPLSrcTexel = vec2() }),
  blur = pass('blur9', { txPLSrc = false }, { gPLDir = vec2() }),
  probe = pass('depth_probe', { txPLDepth = DEPTH }, {}),
}

local finalValues = {
  gPLTexel = vec2(), gPLSize = vec2(), gPLLight = 1, gPLAtmos = 1, gPLDetail = 1, gPLLens = 1, gPLBloomOn = 1, gPLSplit = 0,
  gPLNear = 0.1, gPLFar = 10000, gPLTime = 0,
  PL_Exposure = 0, PL_HighlightRecover = 0.55, PL_Temperature = 0, PL_Tint = 0, PL_BloomIntensity = 0.22, PL_Halation = 0.25,
  PL_FilmicStrength = 0.75, PL_Contrast = 0.08, PL_Saturation = -0.04, PL_Vibrance = 0.12, PL_BlackPoint = 0.004,
  PL_ShadowTint = vec3(0.50, 0.50, 0.52), PL_HighlightTint = vec3(0.51, 0.50, 0.49),
  PL_HazeDensity = 0.30, PL_HazeStart = 0.02, PL_HazeColor = vec3(0.62, 0.70, 0.80), PL_AerialDesat = 0.35,
  PL_Clarity = 0.22, PL_Sharpen = 0.35, PL_ChromaAb = 0.12, PL_Vignette = 0.30, PL_Grain = 0.10, PL_Mix = 1.0,
}
local final = {
  async = true, p1 = vec2(), p2 = vec2(), blendMode = render.BlendMode.Opaque,
  textures = { txPLBase = SCREEN, txPLScreen = SCREEN, txPLDepth = DEPTH, txPLBloom = false, txPLWide = false, txPLLumaQ = false, txPLProbe = false },
  values = finalValues,
  shader = shader('final'),
}

-- ---------------------------------------------------------------------------------------------- render targets
local T = nil   -- canvases for the current resolution
local W, H = 0, 0

local function canvas(w, h)
  return ui.ExtraCanvas(vec2(math.max(1, math.floor(w)), math.max(1, math.floor(h))), 1, render.AntialiasingMode.None, F16)
end

local function dispose()
  if T then for _, c in pairs(T) do c:dispose() end end
  T = nil
end

local function ensureTargets()
  local size = ac.getSim().windowSize
  if T and size.x == W and size.y == H then return end
  dispose()
  W, H = size.x, size.y
  T = {
    nnA = canvas(W, H), nnB = canvas(W, H), nnOut = canvas(W, H),
    d2 = canvas(W / 2, H / 2), d4 = canvas(W / 4, H / 4), d8 = canvas(W / 8, H / 8), d16 = canvas(W / 16, H / 16), d32 = canvas(W / 32, H / 32),
    u16 = canvas(W / 16, H / 16), u8 = canvas(W / 8, H / 8), u4 = canvas(W / 4, H / 4), u2 = canvas(W / 2, H / 2),
    q = canvas(W / 4, H / 4), qb = canvas(W / 4, H / 4),
    probe = canvas(1, 1),
  }
end

local function texel(c) local s = c:size(); return vec2(1 / s.x, 1 / s.y) end

-- ---------------------------------------------------------------------------------------------- frame
-- `s` is the panel state: { light, atmos, detail, lens, neural, nrGain, split, conflict, values = { PL_* } }.
-- Returns `ready` (every pass compiled and drawn) and the list of passes still compiling.
function M.render(s)
  ensureTargets()
  local ok = true
  local function run(target, p) if not target:updateWithShader(p) then ok = false end end
  local full = vec2(1 / W, 1 / H)

  -- Photolap Neural
  local base = SCREEN
  if s.neural and s.nrGain > 0 then
    P.nn0.values.gPLTexel = full; run(T.nnA, P.nn0)
    P.nn1.values.gPLTexel = full; P.nn1.textures.txPLIn = T.nnA; run(T.nnB, P.nn1)
    P.nn2.values.gPLTexel = full; P.nn2.textures.txPLIn = T.nnB; run(T.nnA, P.nn2)
    P.nn3.values.gPLTexel = full; P.nn3.values.gPLIntensity = s.nrGain; P.nn3.textures.txPLIn = T.nnA; run(T.nnOut, P.nn3)
    base = T.nnOut
  end

  local v = s.values
  local recover = s.conflict and 0 or v.PL_HighlightRecover
  local filmic = s.conflict and 0 or v.PL_FilmicStrength

  -- Bloom + halation
  local bloomOn = s.light and ((v.PL_BloomIntensity or 0) > 0 or (v.PL_Halation or 0) > 0)
  if bloomOn then
    local pf = P.prefilter
    pf.textures.txPLSrc = base; pf.values.gPLSrcTexel = full
    pf.values.gPLRecover = recover; pf.values.gPLExposure = v.PL_Exposure or 0
    pf.values.gPLThreshold = s.conflict and 0.8 or 1.25   -- without the inverse tonemap nothing exceeds 1.0
    run(T.d2, pf)
    local chain = { { T.d2, T.d4 }, { T.d4, T.d8 }, { T.d8, T.d16 }, { T.d16, T.d32 } }
    for _, l in ipairs(chain) do
      P.down.textures.txPLSrc = l[1]; P.down.values.gPLSrcTexel = texel(l[1]); run(l[2], P.down)
    end
    local ups = { { T.d16, T.d32, T.u16 }, { T.d8, T.u16, T.u8 }, { T.d4, T.u8, T.u4 }, { T.d2, T.u4, T.u2 } }
    for _, l in ipairs(ups) do
      P.up.textures.txPLSkip = l[1]; P.up.textures.txPLLow = l[2]; P.up.values.gPLLowTexel = texel(l[2]); run(l[3], P.up)
    end
  end

  -- Clarity source
  if s.detail and (v.PL_Clarity or 0) > 0 then
    P.lumaQ.textures.txPLSrc = base; P.lumaQ.values.gPLSrcTexel = full; run(T.q, P.lumaQ)
    local qt = texel(T.q)
    P.blur.textures.txPLSrc = T.q;  P.blur.values.gPLDir = vec2(qt.x, 0); run(T.qb, P.blur)
    P.blur.textures.txPLSrc = T.qb; P.blur.values.gPLDir = vec2(0, qt.y); run(T.q, P.blur)
  end

  if s.atmos then run(T.probe, P.probe) end

  -- Final composite, fullscreen in UI space
  local sim = ac.getSim()
  final.p2 = ac.getUI().windowSize
  final.textures.txPLBase = base
  final.textures.txPLBloom, final.textures.txPLWide = T.u2, T.u8
  final.textures.txPLLumaQ, final.textures.txPLProbe = T.q, T.probe
  local fv = finalValues
  for k, x in pairs(v) do if fv[k] ~= nil then fv[k] = x end end
  fv.PL_HighlightRecover, fv.PL_FilmicStrength = recover, filmic
  if not (s.detail and (v.PL_Clarity or 0) > 0) then fv.PL_Clarity = 0 end
  fv.gPLTexel, fv.gPLSize = full, vec2(W, H)
  fv.gPLLight, fv.gPLAtmos = s.light and 1 or 0, s.atmos and 1 or 0
  fv.gPLDetail, fv.gPLLens = s.detail and 1 or 0, s.lens and 1 or 0
  fv.gPLBloomOn, fv.gPLSplit = bloomOn and 1 or 0, s.split and 1 or 0
  fv.gPLNear, fv.gPLFar = math.max(sim.cameraClipNear or 0.1, 0.01), math.max(sim.cameraClipFar or 10000, 100)
  fv.gPLTime = os.preciseClock()
  if not ui.renderShader(final) then ok = false end
  return ok
end

function M.release() dispose() end

-- ---------------------------------------------------------------------------------------------- environment
local UPSCALERS = {
  [0] = 'FSR 1', [1] = 'FSR 1 (legacy)', [2] = 'NIS', [3] = 'DLSS', [4] = 'Basic', [5] = 'FSR 2', [6] = 'OptiScaler',
  [7] = 'FSR 3', [8] = 'SGSR', [9] = 'SGSR 2', [10] = 'XeSS', [11] = 'XeSS 3', [12] = 'FSR 3/4',
}

-- CSP's own upscaler (Graphics adjustments > Upscaling). Returns label, isOn.
function M.upscaler()
  local ok, cfg = pcall(ac.INIConfig.cspModule, ac.CSPModuleID.GraphicsAdjustments)
  local active, impl = false, -1
  if ok and cfg then
    active = cfg:get('FSR', 'ACTIVE', 0) == 1
    impl = cfg:get('FSR', 'OLD_IMPLEMENTATION', 0)
  end
  local sim = ac.getSim()
  local factor = sim.upscaleAppliedFactor or 1
  if not active then return 'off', false end
  local name = UPSCALERS[impl] or 'upscaler'
  if impl == 3 and factor >= 0.99 then name = 'DLAA' end
  local running = factor < 0.99 or sim.isFSRActive or sim.isTAAActive
  if not running then return name .. ' (restart AC to apply)', true end
  if factor < 0.99 then name = string.format('%s · %d%%', name, math.floor(factor * 100 + 0.5)) end
  return name, true
end

-- Other post-processing apps that grade the frame themselves. Their look is already in dynamic::screen, so Photolap
-- stays on top but drops its own re-tonemap (inverse tonemap + filmic) to avoid tonemapping twice.
local KNOWN_PP = {
  { 'IMGUI_LUA_DreamRealism', 'Dream Realism' }, { 'IMGUI_LUA_DreamPresetManager', 'Dream Realism' },
  { 'IMGUI_LUA_ExilitayFX', 'ExilitayFX' },
}
function M.otherFilter()
  local ok, windows = pcall(ac.getAppWindows)
  if not ok or type(windows) ~= 'table' then return nil end
  for _, w in ipairs(windows) do
    for _, k in ipairs(KNOWN_PP) do
      if type(w.name) == 'string' and w.name:sub(1, #k[1]) == k[1] then return k[2] end
    end
  end
  return nil
end

function M.gpuFrameMs()
  local ok, _, gpu = pcall(ac.getPerformanceCPUAndGPUTime)
  if not ok or type(gpu) ~= 'number' or gpu <= 0 then return nil end
  if gpu < 1 then gpu = gpu * 1000 end   -- seconds on some builds
  return gpu
end

return M
