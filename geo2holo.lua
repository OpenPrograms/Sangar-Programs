local component = require("component")
if not component.isAvailable("geolyzer") then
  io.stderr:write("This program requires a Geolyzer to run.")
  return
end
if not component.isAvailable("hologram") then
  io.stderr:write("This program requires a Hologram Projector to run.")
  return
end

local sx, sz = 48, 48
local ox, oz = -24, -24
local starty, stopy = -5, 27
local includeReplaceable = false

do
  local args = {...}
  --local args, options = shell.parse(...)
  --if options.o then
  --  includeReplaceable = true
  --end
  if #args >= 1 then
    local newY = tonumber(args[1])
    if newY then
      if newY >= -32 and newY <= 31 then
        starty = newY
        stopy = math.min(starty + 31, stopy)
      else
        io.strerr:write("Minimum Y coordinate must be between -32 and 31.")
        return
      end
    end
    if #args >= 2 then
      local newY = tonumber(args[2])
      if newY then
        if newY >= starty and newY <= 31 then
          if newY - starty <= 32 then
            stopy = newY
          else
            io.stderr:write("Minimum and maximum Y coordinates must be 32 or less apart.")
          end
        else
          io.stderr:write("Maximum Y coordinate must be between -32 and 31 and larger than or equal to the minimum.")
          return
        end
      end
    end
  end
end

component.hologram.clear()
for x=ox,sx+ox do
  for z=oz,sz+oz do
    local hx, hz = 1 + x - ox, 1 + z - oz
    local column = component.geolyzer.scan(x, z, includeReplaceable)
    local hy = 1
    for y=starty + 1,stopy + 1 do
      local color = 0
      if column then
        local hardness = column[y + 32]
        if hardness == 0 or not hardness then
          color = 0
        elseif hardness < 3 then
          color = 2
        elseif hardness < 100 then
          color = 1
        else
          color = 3
        end
      end
      if component.hologram.maxDepth() > 1 then
        component.hologram.set(hx, hy, hz, color)
      else
        component.hologram.set(hx, hy, hz, math.min(color, 1))
      end
      hy = hy + 1
    end
    os.sleep(0)
  end
end
