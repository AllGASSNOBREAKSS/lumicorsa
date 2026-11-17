--[[
  Lumicorsa telemetry: only numbers that can actually be measured from Lua.

  - Frame rate, frame time, 1% low and the 15 s histogram come from the frame delta (ac.getUI().dt).
  - CPU load: ac.getSim().cpuOccupancy. VRAM: ac.getVRAMConsumption() (GPU-wide, as CSP documents it).
    There's no GPU-load getter for Lua, so there's no GPU % anywhere in the app.
  - GPU frame time: ac.getPerformanceCPUAndGPUTime().
  - Lumicorsa's own CPU cost: UI and HUD draw time, timed with os.preciseClock around the draw calls.
  - Effect costs: CSP exposes no per-pass GPU timers to Lua, so "Measure costs" (System tab) measures them directly:
    with Lumicorsa on, it switches each effect group off for 1.5 s and records how much the GPU frame time drops.
    The result is stored and shown on every card. Until then cards say "not measured".
]]

local M = {}

local HIST = 900                       -- frame times kept for 1% low (about 15 s at 60 fps)
local frames, head, count = {}, 0, 0
local sparks, sparkT = {}, 0           -- FPS every 0.5 s, 60 entries (sparkline)
local buckets, bucketT, bucketSum, bucketN = {}, 0, 0, 0   -- 40 bars over 15 s
local smooth = { fps = 0, ft = 0 }

M.ui = { cpu = 0, avg = 0 }            -- dashboard draw cost (ms, smoothed)
M.hud = { cpu = 0, avg = 0 }           -- cluster draw cost (ms, smoothed)
M.costs = {}                           -- measured GPU cost per effect group (ms)
M.measuring = nil                      -- benchmark state while it runs

local function push(list, v, n) list[#list + 1] = v; if #list > n then table.remove(list, 1) end end

function M.frame(dt)
  if not dt or dt <= 0 or dt > 1 then return end
  local ms = dt * 1000
  head = head % HIST + 1; frames[head] = ms; count = math.min(count + 1, HIST)
  smooth.ft = smooth.ft == 0 and ms or smooth.ft + (ms - smooth.ft) * 0.08
  smooth.fps = 1000 / smooth.ft
  sparkT = sparkT + dt
  if sparkT >= 0.5 then sparkT = 0; push(sparks, smooth.fps, 60) end
  bucketT, bucketSum, bucketN = bucketT + dt, bucketSum + ms, bucketN + 1
  if bucketT >= 15 / 40 then push(buckets, bucketSum / bucketN, 40); bucketT, bucketSum, bucketN = 0, 0, 0 end
end

function M.fps() return smooth.fps end
function M.frameTime() return smooth.ft end
function M.sparkline() return sparks end
function M.histogram() return buckets end

-- 1% low: FPS at the 99th percentile frame time over the last ~15 s.
local sorted = {}
function M.low1()
  if count < 30 then return nil end
  for i = 1, count do sorted[i] = frames[i] end
  for i = count + 1, #sorted do sorted[i] = nil end
  table.sort(sorted)
  local p99 = sorted[math.max(1, math.floor(count * 0.99))]
  return 1000 / p99
end

function M.cpuLoad()
  local v = ac.getSim().cpuOccupancy
  if type(v) ~= 'number' or v < 0 then return nil end
  return v
end

function M.vram()
  local ok, v = pcall(ac.getVRAMConsumption)
  if not ok or type(v) ~= 'table' or not v.budget or v.budget <= 0 then return nil end
  return v.usage, v.budget
end

function M.gpuFrameMs()
  local ok, _, gpu = pcall(ac.getPerformanceCPUAndGPUTime)
  if not ok or type(gpu) ~= 'number' or gpu <= 0 then return nil end
  if gpu < 1 then gpu = gpu * 1000 end
  return gpu
end

-- Wrap a draw to time it (CPU ms, smoothed).
function M.time(slot, fn, ...)
  local t0 = os.preciseClock()
  fn(...)
  local ms = (os.preciseClock() - t0) * 1000
  local s = M[slot]
  s.cpu = ms
  s.avg = s.avg == 0 and ms or s.avg + (ms - s.avg) * 0.05
end

-- ---------------------------------------------------------------------------------------------- cost measurement
M.GROUPS = { 'neural', 'exposure', 'bloom', 'sun', 'ao', 'detail', 'dof', 'mist', 'grade' }
M.GROUP_LABELS = { neural = 'Neural', exposure = 'Adaptation', bloom = 'Bloom', sun = 'Sun', ao = 'Contact AO',
  detail = 'Detail', dof = 'Depth of field', mist = 'Mist', grade = 'Grade' }

-- Start: runs `M.measureStep(dt)` each frame; returns the set of groups to switch off this frame.
function M.startMeasure(onDone)
  M.measuring = { step = 0, t = 0, base = {}, samples = {}, onDone = onDone }
end

function M.measureStep(dt, active)
  local m = M.measuring
  if not m then return nil end
  m.t = m.t + dt
  local seq = {}
  for _, g in ipairs(M.GROUPS) do if g ~= 'grade' and active[g] then seq[#seq + 1] = g end end
  seq[#seq + 1] = 'all'                                    -- everything off: total app cost
  local phase = math.floor(m.t / 1.5)                      -- 1.5 s per phase: 0 = baseline, then one per group
  local within = m.t - phase * 1.5
  local gpu = M.gpuFrameMs()
  if gpu and within > 0.5 then                             -- skip the first 0.5 s after each switch
    local key = phase == 0 and 'base' or seq[phase]
    if key then
      m.samples[key] = m.samples[key] or {}
      push(m.samples[key], gpu, 200)
    end
  end
  if phase > #seq then
    local function mean(t) local s = 0; for _, x in ipairs(t or {}) do s = s + x end; return #(t or {}) > 0 and s / #t or nil end
    local base = mean(m.samples.base)
    if base then
      for _, g in ipairs(seq) do
        local v = mean(m.samples[g])
        if v then
          if g == 'all' then M.costs.total = math.max(base - v, 0) else M.costs[g] = math.max(base - v, 0) end
        end
      end
      local sum = 0
      for _, g in ipairs(seq) do if g ~= 'all' then sum = sum + (M.costs[g] or 0) end end
      M.costs.grade = math.max((M.costs.total or 0) - sum, 0)
      M.costs.measuredAt = os.time()
    end
    M.measuring = nil
    if m.onDone then m.onDone(base ~= nil) end
    return nil
  end
  if phase == 0 then return {} end
  local key = seq[phase]
  if key == 'all' then return { all = true } end
  return { [key] = true }
end

return M
