local component = require("component")
local event = require("event")
local keyboard = require("keyboard")
local shell = require("shell")
local term = require("term")
local unicode = require("unicode")
local raytracer = require("raytracer")

local args = shell.parse(...)
if #args < 1 then
  io.write("Usage: print3d-view FILE [fov]\n")
  os.exit(0)
end

-- model loading

local file, reason = io.open(args[1], "r")
if not file then
  io.stderr:write("Failed opening file: " .. reason .. "\n")
  os.exit(1)
end

local rawdata = file:read("*all")
file:close()
local data, reason = load("return " .. rawdata)
if not data then
  io.stderr:write("Failed loading model: " .. reason .. "\n")
  os.exit(2)
end
data = data()

-- set up raytracer

local rt = raytracer.new()
rt.camera.position={-22+8,20+8,-22+8}
rt.camera.target={8,8,8}
rt.camera.fov=tonumber(args[2]) or 90

local state
local function setState(value)
  if state ~= value then
    state = value
    rt.model = {}
    for _, shape in ipairs(data.shapes or {}) do
      if not not shape.state == state then
        table.insert(rt.model, shape)
      end
    end
    if state and #rt.model < 1 then -- no shapes for active state
      setState(false)
    end
  end
end
setState(false)

-- set up gpu

local gpu = component.gpu
local cfg, cbg
local function setForeground(color)
  if cfg ~= color then
    gpu.setForeground(color)
    cfg = color
  end
end
local function setBackground(color)
  if cbg ~= color then
    gpu.setBackground(color)
    cbg = color
  end
end

-- helper functions

local function vrotate(v, origin, angle)
  local x, y = v[1]-origin[1], v[3]-origin[3]
  local s = math.sin(angle)
  local c = math.cos(angle)

  local rotx = x * c + y * s
  local roty = -x * s + y * c
  return {rotx+origin[1], v[2], roty+origin[3]}
end

local function ambient(normal)
  if math.abs(normal[1]) > 0.5 then
    return 0.6
  elseif math.abs(normal[3]) > 0.5 then
    return 0.8
  elseif normal[2] > 0 then
    return 1.0
  else
    return 0.4
  end
end

local function hash(str)
  local result = 7
  for i=1,#str do
    result = (result*31 + string.byte(str, i))%0xFFFFFFFF
  end
  return result
end

local function multiply(color, brightness)
  local r,b,g=(color/2^16)%256,(color/2^8)%256,color%256
  r = r*brightness
  g = g*brightness
  b = b*brightness
  return r*2^16+g*2^8+b
end

local palette = {0x0000FF, 0x00FF00, 0x00FFFF, 0xFF0000, 0xFF00FF, 0xFFFF00, 0xFFFFFF}

-- render model
while true do
  setForeground(0x000000)
  setBackground(0x000000)
  local rx, ry = gpu.getResolution()
  gpu.fill(1, 1, rx, ry, unicode.char(0x2580))

  rt:render(rx, ry*2, function(x, y, shape, normal)
    local sx, sy = x, math.ceil(y / 2)
    local ch, fg, bg = gpu.get(sx, sy)
    local brightness = ambient(normal)
    local color = multiply(data.palette and data.palette[shape.texture] or palette[hash(shape.texture or "") % #palette + 1], brightness)
    if color == 0x000000 then return end
    if y % 2 == 1 then
      setBackground(bg)
      setForeground(color)
    else
      setBackground(color)
      setForeground(fg)
    end
    gpu.set(sx, sy, ch)
  end)

  gpu.setForeground(0xFFFFFF)
  gpu.setBackground(0x000000)

  gpu.set(1, ry, "[q] Quit    [left/right] Rotate    [space] Toggle state")
  os.sleep(0.1) -- consume events that arrived in the meantime
  while true do
    local _,_,_,code=event.pull("key_down")
    if code == keyboard.keys.q then
      term.clear()
      os.exit(0)
    elseif code == keyboard.keys.space then
      setState(not state)
      break
    elseif code == keyboard.keys.left then
      local step = 10
      if keyboard.isShiftDown() then step = 90 end
      rt.camera.position = vrotate(rt.camera.position, rt.camera.target, -step/180*math.pi)
      break
    elseif code == keyboard.keys.right then
      local step = 10
      if keyboard.isShiftDown() then step = 90 end
      rt.camera.position = vrotate(rt.camera.position, rt.camera.target, step/180*math.pi)
      break
    end
  end
end
