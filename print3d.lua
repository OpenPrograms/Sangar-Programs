local component = require("component")
local shell = require("shell")

local printer = component.printer3d

local args = shell.parse(...)
if #args < 1 then
  io.write("Usage: print3d FILE\n")
  os.exit(0)
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

printer.reset()
if data.label then
  io.write("Setting label to: '" .. data.label .. "'\n")
  printer.setLabel(data.label)
end
if data.tooltip then
  io.write("Setting tooltip to: '" .. data.tooltip .. "'\n")
  printer.setTooltip(data.tooltip)
end
if data.emitRedstone then
  io.write("Setting block to " .. (data.emitRedstone and "" or "not ") .. "emit redstone when toggled.\n")
  printer.setRedstoneEmitter(data.emitRedstone)
end
if data.buttonMode then
  io.write("Setting button mode to: " .. tostring(data.buttonMode) .. ".\n")
  printer.setButtonMode(data.buttonMode)
end
io.write("Adding " .. #data.shapes .. " shapes.\n")
for _, shape in ipairs(data.shapes or {}) do
  printer.addShape(shape[1], shape[2], shape[3], shape[4], shape[5], shape[6], shape.texture, shape.state)
end

local result, reason = printer.commit()
if result then
  io.write("Job successfully committed!\n")
else
  io.stderr:write("Failed committing job: " .. reason .. "\n")
end