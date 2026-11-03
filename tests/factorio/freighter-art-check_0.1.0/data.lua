local make_animation = require("prototypes.freighter-animation")
local vehicle = table.deepcopy(data.raw.car.car)
vehicle.name = "quinityn-freighter-art-check"
vehicle.animation = make_animation("freighter-art-check")
vehicle.turret_animation = nil
vehicle.light_animation = nil
vehicle.guns = nil
vehicle.minable = nil
data:extend({ vehicle })
local alternative = table.deepcopy(vehicle)
alternative.name = "quinityn-freighter-art-check-alternate"
alternative.animation = make_animation("freighter-art-check", {
  cab = { r = 0.1, g = 0.9, b = 0.2, a = 1 },
  trim = { r = 0.9, g = 0.1, b = 0.2, a = 1 },
  cargo = { r = 0.8, g = 0.8, b = 0.8, a = 1 },
})
data:extend({ alternative })
