-- Generates a random heightmap and displays scrolling text above it.

local component = require("component")
local noise = require("noise")
local keyboard = require("keyboard")
local hologram = component.hologram

hologram.clear()

local seed = math.random(0xFFFFFFFF)
for x = 1, 16 * 3 do
  for z = 1, 16 * 3 do
    hologram.fill(x, z, 15 + noise.fbm(x/(16*3) + seed, 1, z/(16*3) + seed) * 28,1)
  end
end

local value = [[
XXXXXX XXXXX XXXXX X   X       XXXXX XXXXX X   X XXXXX X   X XXXXX XXXXX XXXX  XXXXX       
X    X X   X X     XX  X       X     X   X XX XX X   X X   X   X   X     X   X X           
X    X XXXXX XXXX  X X X       X     X   X XXXXX XXXXX X   X   X   XXXX  XXXX  XXXXX       
X    X X     X     X  XX       X     X   X X X X X     X   X   X   X     X   X     X       
XXXXXX X     XXXXX X   X       XXXXX XXXXX X   X X     XXXXX   X   XXXXX X   X XXXXX       
]]

-- local value = [[
-- XXXXXX XXXXX
-- X    X X    
-- X    X X    
-- X    X X    
-- XXXXXX XXXXX
-- ]]

local bm = {}
for token in value:gmatch("([^\r\n]*)") do
  if token ~= "" then
    table.insert(bm, token)
  end
end
print("Press Ctrl+W to stop")
local h,w = #bm,#bm[1]
local sx, sy = math.max(0,(16*3-w)/2), 2*16-h-1
local z = 16*3/2

for i = 1, math.huge do
  os.sleep(0.1)
  local function col(n)
    return (n - 1 + i) % w + 1
  end
  for i=1, math.min(16*3,w) do
    local x = sx + i
    local i = col(i)
    for j=1, h do
      local y = sy + j-1
      if bm[1+h-j]:sub(i, i) ~= " " then
        hologram.set(x, y, z, 1)
      else
        hologram.set(x, y, z, 0)
      end
      if keyboard.isKeyDown(keyboard.keys.w) and keyboard.isControlDown() then
        hologram.clear()
        os.exit()
      end
    end
  end
end
