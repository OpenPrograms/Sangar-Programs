-- Generates a random heightmap and displays scrolling text above it.

local component = require("component")
local keyboard = require("keyboard")
local hologram = component.hologram

hologram.clear()

-- in this example all of these must be five wide
local glyphs = {
[0]=[[
 XXX 
X   X
X X X
X   X
 XXX 
]],
[1]=[[
  XX 
 X X 
   X 
   X 
   X 
]],
[2]=[[
XXXX 
    X
  X  
X    
XXXXX
]],
[3]=[[
XXXX 
    X
 XXX 
    X
XXXX 
]],
[4]=[[
X   X
X   X
XXXXX
    X
    X
]],
[5]=[[
XXXXX
X    
XXXX 
    X
XXXX 
]],
[6]=[[
 XXX 
X    
XXXX 
X   X
 XXX 
]],
[7]=[[
XXXXX
   X 
 XXX 
  X  
 X   
]],
[8]=[[
 XXX 
X   X
 XXX 
X   X
 XXX 
]],
[9]=[[
 XXX 
X   X
 XXXX
    X
 XXX 
]]
}

-- Prepopulate data table; this represents the whole hologram data as a single
-- linear array, nested as y,z,x. In other words, if the hologram were 3x3x3:
-- {(1,1,1),(1,2,1),(1,3,1),(1,1,2),(1,2,2),(1,3,2),(1,1,3),(1,2,3),(1,3,3),(2,1,1),...}
-- Each entry must be a single char; they are merged into a single byte array
-- (or string) before sending the data to the hologram via table.concat. We don't
-- keep the data as a string, because we'd have to create a new string when
-- modifying it, anyway (because you can't do myString[3]="\0").
local data = {}
for i = 1, 32*48*48 do data[i] = "\0" end

local w,h=5,5
local x0 = math.floor((48-w)/2)
local z0 = math.floor(48/2)
local y0 = math.floor((32-h)/2)

print("Press Ctrl+W to stop.")
for i = 1, math.huge do
  local num = glyphs[i % 9 + 1]
  for y = 1, h do
    for x = 1, w do
      -- flip chars vertically, because hologram y axis goes up
      local charIdx = 1 + (x-1)+(h-y)*(w+1)
      local dataIdx = 1 + (y0+y-1) + z0*32 + (x0+x-1)*32*48
      data[dataIdx] = num:sub(charIdx, charIdx) == " " and "\0" or "\1"
    end
  end
  hologram.setRaw(table.concat(data))
  os.sleep(0) -- for event handling for keyboard keydown checks.
  if keyboard.isKeyDown(keyboard.keys.w) and keyboard.isControlDown() then
    hologram.clear()
    os.exit()
  end
end
