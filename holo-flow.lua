-- Generates a heightmap and 'moves' across it over time, creating
-- the effect of a flowing terrain.

local component = require("component")
local noise = require("noise")
local holo = component.hologram
local keyboard = require("keyboard")
print("Press Ctrl+W to stop")

holo.clear()
local i = 0
while true do
  os.sleep(0.1)
  i = i + 0.05
  for x = 1, 16 * 3 do
    for z = 1, 16 * 3 do
      holo.fill(x, z, 15 + noise.fbm(x/(16*3) + i, 1, z/(16*3) + i) * 28,1)
      if keyboard.isKeyDown(keyboard.keys.w) and keyboard.isControlDown() then
        os.exit()
      end
    end
  end
end
