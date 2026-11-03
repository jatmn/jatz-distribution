local util = require('util')
local definitions = require('prototypes.depot-definitions')
local pictures = require('prototypes.depot-pictures')
local pipe_pictures = require('prototypes.depot-pipe-pictures')
for role, sizes in pairs(definitions) do
  for size, definition in pairs(sizes) do
    for _, alternate in ipairs({false,true}) do
      local name='depot-art-'..role..'-'..size..(alternate and '-alternate' or '')
      local entity
      local palette=alternate and {role={.85,.12,.7},clamps={.1,.9,.85},housing={.78,.78,.78}} or nil
      local artwork=pictures('depot-art-check',role,size,palette)
      if #definition.ports==0 then
        entity=table.deepcopy(data.raw.container['steel-chest'])
        entity.direction_count=4
        entity.picture=artwork
      else
        entity=table.deepcopy(data.raw['storage-tank']['storage-tank'])
        entity.two_direction_only=false
        entity.fluid_box={volume=1000,pipe_connections=table.deepcopy(definition.ports),pipe_covers=pipecoverspictures(),pipe_picture=pipe_pictures('depot-art-check'),secondary_draw_orders={north=-1}}
        entity.pictures={picture=artwork,fluid_background=util.empty_sprite(),window_background=util.empty_sprite(),flow_sprite=util.empty_sprite(),gas_flow=util.empty_sprite()}
        entity.window_bounding_box={{0,0},{0,0}}
        entity.show_fluid_icon=true
      end
      entity.name=name
      entity.localised_name=role:gsub('-',' ')..' depot '..size..'x'..size..(alternate and ' alternate colors' or '')
      entity.minable={mining_time=.2,result=name}
      entity.circuit_connector=nil
      entity.fast_replaceable_group=nil
      entity.selection_box={{-size/2,-size/2},{size/2,size/2}}
      entity.collision_box={{-size/2+.2,-size/2+.2},{size/2-.2,size/2-.2}}
      entity.tile_width=size
      entity.tile_height=size
      data:extend({entity,{type='item',name=name,localised_name=entity.localised_name,icon='__base__/graphics/icons/storage-tank.png',stack_size=50,place_result=name}})
    end
  end
end
