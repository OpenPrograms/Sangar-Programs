local component = require("component")
local event = require("event")
local keyboard = require("keyboard")
local term = require("term")
local unicode = require("unicode")

print("Left click:  mark a cell as 'alive'.")
print("Right click: mark a cell as 'dead'.")
print("Space:       toggle pause of the simulation.")
print("Q:           exit the program.")
print("Press any key to begin.")
os.sleep(0.1)
event.pull("key")

local off = " "
local off2on = unicode.char(0x2593)
local on = unicode.char(0x2588)
local on2off = unicode.char(0x2592)

local gpu = component.gpu
local ow, oh = gpu.getResolution()
gpu.setResolution(27, 15)
local w, h = gpu.getResolution()
gpu.setBackground(0x000000)
gpu.setForeground(0xFFFFFF)
gpu.fill(1, 1, w, h, off)

local function isAlive(x, y)
  x = (x + w - 1) % w + 1
  y = (y + h - 1) % h + 1
  local char = gpu.get(x, y)
  return char == on or char == on2off
end
local function setAlive(x, y, alive)
  if isAlive(x, y) == alive then
    return
  end
  if alive then
    gpu.set(x, y, off2on)
  else
    gpu.set(x, y, on2off)
  end
end
local function flush()
  for y = 1, h do
    local row = ""
    for x = 1, w do
      row = row .. gpu.get(x, y)
    end
    local final = row:gsub(on2off, off):gsub(off2on, on)
    if final ~= row then
      gpu.set(1, y, final)
    end
  end
end

local function count(x, y)
  local n = 0
  for rx = -1, 1 do
    local nx = x + rx
    for ry = -1, 1 do
      local ny = y + ry
      if (rx ~= 0 or ry ~= 0) and isAlive(nx, ny) then
        n = n + 1
      end
    end
  end
  return n
end
local function map(x, y)
  local n = count(x, y)
  return n == 2 and isAlive(x, y) or n == 3
end
local function step()
  for y = 1, h do
    for x = 1, w do
      setAlive(x, y, map(x, y))
    end
  end
  flush()
end

local running = false
while true do
  local e = table.pack(event.pull(0.25))
  if e[1] == "key_down" then
    local _, _, _, code = table.unpack(e)
    if code == keyboard.keys.space then
      running = not running
    elseif code == keyboard.keys.q then
      gpu.setResolution(ow, oh)
      term.clear()
      return
    end
  elseif e[1] == "touch" then
    local _, _, x, y, button = table.unpack(e)
    gpu.set(x, y, button == 0 and on or off)
  end
  if running then
    step()
  end
end