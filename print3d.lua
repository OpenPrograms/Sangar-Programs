local component = require("component")
local shell = require("shell")

local printer = component.printer3d

local args = shell.parse(...)
if #args < 1 then
  io.write("Usage: print3d FILE [count]\n")
  os.exit(0)
end
local count = 1
if #args > 1 then
  count = assert(tonumber(args[2]), tostring(args[2]) .. " is not a valid count")
end

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
io.write("Shapes: " .. printer.getShapeCount() .. " inactive, " .. select(2, printer.getShapeCount()) .. " active\n")

local result, reason = printer.commit(count)
if result then
  io.write("Job successfully committed!\n")
else
  io.stderr:write("Failed committing job: " .. tostring(reason) .. "\n")
end