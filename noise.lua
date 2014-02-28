-- Perlin noise and more in pure Lua.
-- Found this on stackoverflow but can't find the URL anymore.
local noise = {}

local p = {}
local permutation = {151,160,137,91,90,15,
  131,13,201,95,96,53,194,233,7,225,140,36,103,30,69,142,8,99,37,240,21,10,23,
  190, 6,148,247,120,234,75,0,26,197,62,94,252,219,203,117,35,11,32,57,177,33,
  88,237,149,56,87,174,20,125,136,171,168, 68,175,74,165,71,134,139,48,27,166,
  77,146,158,231,83,111,229,122,60,211,133,230,220,105,92,41,55,46,245,40,244,
  102,143,54, 65,25,63,161, 1,216,80,73,209,76,132,187,208, 89,18,169,200,196,
  135,130,116,188,159,86,164,100,109,198,173,186, 3,64,52,217,226,250,124,123,
  5,202,38,147,118,126,255,82,85,212,207,206,59,227,47,16,58,17,182,189,28,42,
  223,183,170,213,119,248,152, 2,44,154,163, 70,221,153,101,155,167, 43,172,9,
  129,22,39,253, 19,98,108,110,79,113,224,232,178,185, 112,104,218,246,97,228,
  251,34,242,193,238,210,144,12,191,179,162,241, 81,51,145,235,249,14,239,107,
  49,192,214, 31,181,199,106,157,184, 84,204,176,115,121,50,45,127, 4,150,254,
  138,236,205,93,222,114,67,29,24,72,243,141,128,195,78,66,215,61,156,180
}

for i = 0, 255 do
  p[i] = permutation[i + 1]
  p[256 + i] = permutation[i + 1]
end

local function fade(t)
  return t * t * t * (t * (t * 6 - 15) + 10)
end

local function lerp(t, a, b)
  return a + t * (b - a)
end

local function grad(hash, x, y, z)
  local h, u, v = hash % 16
  if h < 8 then u = x else u = y end
  if h < 4 then v = y elseif h == 12 or h == 14 then v = x else v = z end
  local r
  if h % 2 == 0 then r = u else r = -u end
  if h % 4 == 0 then r = r + v else r = r - v end
  return r
end

function noise.perlin(x, y, z) 
  y = y or 0
  z = z or 0
  local X = math.floor(x % 255)
  local Y = math.floor(y % 255)
  local Z = math.floor(z % 255)
  x = x - math.floor(x)
  y = y - math.floor(y)
  z = z - math.floor(z)
  local u = fade(x)
  local v = fade(y)
  local w = fade(z)

  A   = p[X    ] + Y
  AA  = p[A    ] + Z
  AB  = p[A + 1] + Z
  B   = p[X + 1] + Y
  BA  = p[B    ] + Z
  BB  = p[B + 1] + Z

  return lerp(w, lerp(v, lerp(u, grad(p[AA    ], x    , y    , z    ), 
                                 grad(p[BA    ], x - 1, y    , z    )), 
                         lerp(u, grad(p[AB    ], x    , y - 1, z    ), 
                                 grad(p[BB    ], x - 1, y - 1, z    ))),
                 lerp(v, lerp(u, grad(p[AA + 1], x    , y    , z - 1),  
                                 grad(p[BA + 1], x - 1, y    , z - 1)),
                         lerp(u, grad(p[AB + 1], x    , y - 1, z - 1),
                                 grad(p[BB + 1], x - 1, y - 1, z - 1))))
end

function noise.fbm(x, y, z, octaves, lacunarity, gain)
  octaves = octaves or 8
  lacunarity = lacunarity or 2
  gain = gain or 0.5
  local amplitude = 1.0
  local frequency = 1.0
  local sum = 0.0
  for i = 0, octaves do
    sum = sum + amplitude * noise.perlin(x * frequency, y * frequency, z * frequency)
    amplitude = amplitude * gain
    frequency = frequency * lacunarity
  end
  return sum
end

return noise