local component = require("component")
if not component.isAvailable("geolyzer") then
  io.stderr:write("This program requires a Geolyzer to run.")
  return
end
if not component.isAvailable("hologram") then
  io.stderr:write("This program requires a Hologram to run.")
  return
end

local sx, sz = 48, 48
local ox, oz = -24, -24

component.hologram.clear()
for x=ox,sx+ox do
  for z=oz,sz+oz do
    local hx, hz = 1 + x - ox, 1 + z - oz
    local column = component.geolyzer.scan(x, z)
    for y=1,32 do
      local hardness = column[y + 27]
      local color
      if hardness == 0 or not hardness then
        color = 0
      elseif hardness < 3 then
        color = 2
      elseif hardness < 100 then
        color = 1
      else
        color = 3
      end
      if component.hologram.maxDepth() > 1 then
        component.hologram.set(hx, y, hz, color)
      else
        component.hologram.set(hx, y, hz, math.min(color, 1))
      end
    end
    os.sleep(0)
  end
end