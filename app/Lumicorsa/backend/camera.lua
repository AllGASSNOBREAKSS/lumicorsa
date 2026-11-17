--[[
  Camera: chase camera, field of view, seat, head movement, replay camera.

  - Chase camera: AC's chase_cam.ini has DISTANCE, HEIGHT, PITCH per chase view (CHASE_0 = F1 first chase, CHASE_1 =
    second). ac.applyLiveConfigEdit('chase_cam.ini', ...) changes them live without touching the file, and Lumicorsa
    remembers the values per car and re-applies them when you drive that car again. AC has no setting for side
    offset, follow lag or roll, so those controls from the design aren't in the app.
  - Cockpit FOV: ac.setFirstPersonCameraFOV, read back from ac.getSim().firstPersonCameraFOV.
  - Seat: ac.getOnboardCameraParams / ac.setOnboardCameraParams (saved to cfg/cars/<car>/view.ini like AC's own
    camera app), as an offset from the car's default eye position.
  - Head movement from G-forces: CSP Neck FX ([GFORCES_BASE] LIMIT), scaled from its defaults.
  - Replay camera: ac.setCurrentCamera (only while a replay is playing).
]]

local C = require('backend/config')

local M = {}

-- ---------------------------------------------------------------------------------------------- chase camera
local fileChase = {}
do
  local ok, cfg = pcall(ac.INIConfig.load, ac.getFolder(ac.FolderID.Root) .. '/system/cfg/chase_cam.ini')
  for i = 0, 1 do
    local s = 'CHASE_' .. i
    fileChase[i] = {
      distance = ok and cfg and cfg:get(s, 'DISTANCE', 3.2) or 3.2,
      height = ok and cfg and cfg:get(s, 'HEIGHT', 0.9) or 0.9,
      pitch = math.deg(ok and cfg and cfg:get(s, 'PITCH', 0.035) or 0.035),
    }
  end
end

local perCar = ac.storage({ json = '' }, 'chase_')
local memory = {}
do local ok, t = pcall(JSON.parse, perCar.json or ''); if ok and type(t) == 'table' then memory = t end end

local function carKey() local car = ac.getCar(0); return car and car:id() or 'default' end
local function activeIndex()
  local m = ac.getSim().driveableCameraMode
  return (m == ac.DrivableCamera.Chase2) and 1 or 0
end

-- current values for the active chase view (per-car memory first, then chase_cam.ini)
function M.chase(index)
  index = index or activeIndex()
  local m = memory[carKey()]
  local c = m and m[tostring(index)]
  return c or fileChase[index]
end

local function applyChase(index, c)
  local ini = string.format('[CHASE_%d]\nDISTANCE=%.3f\nHEIGHT=%.3f\nPITCH=%.5f\n', index, c.distance, c.height, math.rad(c.pitch))
  return pcall(ac.applyLiveConfigEdit, 'chase_cam.ini', ini)
end

function M.setChase(field, value)
  local index = activeIndex()
  local c = {}
  for k, v in pairs(M.chase(index)) do c[k] = v end
  c[field] = value
  local key = carKey()
  memory[key] = memory[key] or {}
  memory[key][tostring(index)] = c
  applyChase(index, c)
  C.later('chase/memory', memory, function (t) perCar.json = JSON.stringify(t) end)
end

-- Re-apply this car's remembered chase cameras (on load and when the car changes).
function M.restoreChase()
  local m = memory[carKey()]
  if not m then return end
  for i = 0, 1 do local c = m[tostring(i)]; if c then applyChase(i, c) end end
end

-- Measured camera distance behind the car (self-test readback): only meaningful in a chase view.
function M.measuredChaseDistance()
  local sim = ac.getSim()
  if sim.cameraMode ~= ac.CameraMode.Drivable then return nil end
  local ok, rel = pcall(ac.getCameraPositionRelativeToCar)
  if not ok or not rel then return nil end
  return math.sqrt(rel.x * rel.x + rel.z * rel.z)
end

-- ---------------------------------------------------------------------------------------------- field of view
function M.fov() return ac.getSim().firstPersonCameraFOV end
function M.setFov(v) pcall(ac.setFirstPersonCameraFOV, v) end

-- Vertical FOV that matches the real screen: screen diagonal (inches), eye distance (cm), aspect from the AC window.
function M.fovFromScreen(diagInches, distanceCm)
  local ws = ac.getSim().windowSize
  local aspect = ws.x / math.max(ws.y, 1)
  local heightCm = diagInches * 2.54 / math.sqrt(1 + aspect * aspect)
  return math.deg(2 * math.atan(heightCm / 2 / distanceCm))
end

-- ---------------------------------------------------------------------------------------------- seat
local function seat()
  local ok, p = pcall(ac.getOnboardCameraParams, 0)
  local okd, d = pcall(ac.getOnboardCameraDefaultParams, 0)
  if not ok or not p or not okd or not d then return nil end
  return p, d
end

function M.seatOffset(axis)   -- cm from the car's default eye point (y = height, z = forward)
  local p, d = seat()
  if not p then return 0 end
  return (p.position[axis] - d.position[axis]) * 100
end

function M.setSeatOffset(axis, cm)
  local p, d = seat()
  if not p then return end
  local pos = vec3(p.position.x, p.position.y, p.position.z)
  pos[axis] = d.position[axis] + cm / 100
  pcall(ac.setOnboardCameraParams, 0, ac.SeatParams(pos, p.pitch, p.yaw), true)
end

-- ---------------------------------------------------------------------------------------------- head movement (Neck FX)
local NECK_DEFAULT = vec3(0.06, 0.04, 0.08)
function M.headMovement()
  if tonumber(C.get('csp:neck', 'BASIC', 'ENABLED', 0)) ~= 1 then return 0 end
  local l = C.get('csp:neck', 'GFORCES_BASE', 'LIMIT', NECK_DEFAULT)
  return (l and l.x) and l.x / NECK_DEFAULT.x * 40 or 40
end
function M.setHeadMovement(pct)
  C.setLater('csp:neck', 'BASIC', 'ENABLED', pct > 0 and 1 or 0)
  C.setLater('csp:neck', 'GFORCES_BASE', 'LIMIT', NECK_DEFAULT * (pct / 40))
end
function M.readHeadMovement()
  if tonumber(C.readback('csp:neck', 'BASIC', 'ENABLED', 0)) ~= 1 then return 0 end
  local l = C.readback('csp:neck', 'GFORCES_BASE', 'LIMIT', NECK_DEFAULT)
  return l and l.x and l.x / NECK_DEFAULT.x * 40 or nil
end

-- ---------------------------------------------------------------------------------------------- replay camera
M.REPLAY = { { label = 'Track', value = ac.CameraMode.Track }, { label = 'Heli', value = ac.CameraMode.Helicopter },
  { label = 'Car', value = ac.CameraMode.Car } }
function M.replayLocked() return not ac.getSim().isReplayActive and 'Works while a replay is playing' or nil end

-- ---------------------------------------------------------------------------------------------- registry
function M.register(R, St)
  local fmt = R.fmt
  local function chaseDef(id, label, field, min, max, f)
    R.api(id, label, { kind = 'knob', min = min, max = max, fmt = f, key = 'chase_cam.ini [CHASE_n] ' .. field:upper() .. ' (live edit)',
      default = fileChase[0][field],
      get = function () return M.chase()[field] end,
      set = function (v) M.setChase(field, v) end,
      readback = field == 'distance' and M.measuredChaseDistance or function () return M.chase()[field] end,
      tolerance = field == 'distance' and 0.6 or nil, needsChase = true })
  end
  chaseDef('ch_h', 'Height', 'height', -0.5, 2.5, fmt.unit(' m', 1))
  chaseDef('ch_d', 'Distance', 'distance', 2, 9, fmt.unit(' m', 1))
  chaseDef('ch_p', 'Pitch', 'pitch', -15, 15, fmt.unit('°'))

  R.api('fov_c', 'Cockpit', { kind = 'slider', min = 30, max = 110, step = 1, default = 56, fmt = fmt.unit('°'),
    key = 'ac.setFirstPersonCameraFOV', get = M.fov, set = M.setFov })
  R.api('cdof', 'Depth of field', { kind = 'toggle', hint = 'Gauges sharp, far road soft',
    get = function () return St.cockpitDof end, set = function (v) St.cockpitDof = v end,
    readback = function () return St.cockpitDof end })
  R.api('headmove', 'Head movement from G-force', { kind = 'slider', min = 0, max = 100, step = 1, default = 40, fmt = fmt.pct,
    key = 'neck.ini [GFORCES_BASE] LIMIT', get = M.headMovement, set = M.setHeadMovement, readback = M.readHeadMovement, debounced = true })
  R.api('seat_h', 'Seat height', { kind = 'slider', min = -10, max = 10, step = 1, default = 0, fmt = fmt.unit(' cm'),
    key = 'view.ini (ac.setOnboardCameraParams)', get = function () return M.seatOffset('y') end,
    set = function (v) M.setSeatOffset('y', v) end })
  R.api('seat_f', 'Seat forward', { kind = 'slider', min = -10, max = 10, step = 1, default = 0, fmt = fmt.unit(' cm'),
    key = 'view.ini (ac.setOnboardCameraParams)', get = function () return M.seatOffset('z') end,
    set = function (v) M.setSeatOffset('z', v) end })
  R.api('replaycam', 'Camera', { kind = 'seg', options = M.REPLAY, key = 'ac.setCurrentCamera', locked = M.replayLocked,
    get = function () return ac.getSim().cameraMode end, set = function (v) pcall(ac.setCurrentCamera, v) end })
  R.state('rdof', 'Replay depth of field', { kind = 'slider', min = 0, max = 100, step = 1, default = 60, fmt = fmt.pct,
    get = function () return St.replayDof * 100 end, set = function (v) St.replayDof = v / 100 end,
    readback = function () return St.replayDof * 100 end })
end

return M
