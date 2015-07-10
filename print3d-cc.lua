local printer = peripheral.find("printer3d")

local args = {...}
if #args < 1 then
  io.write("Usage: print3d FILE [count]\n")
  return 0
end
local count = 1
if #args > 1 then
  count = assert(tonumber(args[2]), tostring(args[2]) .. " is not a valid count")
end

local file = fs.open(args[1], "r")
if not file then
  io.write("Failed opening file\n")
  return 1
end

local rawdata = file.readAll()
file.close()
local data, reason = loadstring("return " .. rawdata)
if not data then
  io.write("Failed loading model: " .. reason .. "\n")
  return 2
end
data = data()

io.write("Configuring...\n")

printer.reset()
if data.label then
  printer.setLabel(data.label)
end
if data.tooltip then
  printer.setTooltip(data.tooltip)
end
if data.lightLevel and printer.setLightLevel then -- as of OC 1.5.7
  printer.setLightLevel(data.lightLevel)
end
if data.emitRedstone then
  printer.setRedstoneEmitter(data.emitRedstone)
end
if data.buttonMode then
  printer.setButtonMode(data.buttonMode)
end
if data.collidable and printer.setCollidable then
  printer.setCollidable(not not data.collidable[1], not not data.collidable[2])
end
for i, shape in ipairs(data.shapes or {}) do
  local result, reason = printer.addShape(shape[1], shape[2], shape[3], shape[4], shape[5], shape[6], shape.texture, shape.state, shape.tint)
  if not result then
    io.write("Failed adding shape: " .. tostring(reason) .. "\n")
  end
end

io.write("Label: '" .. (printer.getLabel() or "not set") .. "'\n")
io.write("Tooltip: '" .. (printer.getTooltip() or "not set") .. "'\n")
if printer.getLightLevel then -- as of OC 1.5.7
  io.write("Light level: " .. printer.getLightLevel() .. "\n")
end
io.write("Redstone level: " .. select(2, printer.isRedstoneEmitter()) .. "\n")
io.write("Button mode: " .. tostring(printer.isButtonMode()) .. "\n")
if printer.isCollidable then -- as of OC 1.5.something
  io.write("Collidable: " .. tostring(select(1, printer.isCollidable())) .. "/" .. tostring(select(2, printer.isCollidable())) .. "\n")
end
io.write("Shapes: " .. printer.getShapeCount() .. " inactive, " .. select(2, printer.getShapeCount()) .. " active\n")

local result, reason = printer.commit(count)
if result then
  io.write("Job successfully committed!\n")
else
  io.write("Failed committing job: " .. tostring(reason) .. "\n")
end
