local definitions = require('prototypes.depot-definitions')
local roles={'provider','request','buffer','fuel','liquid-provider','liquid-request','liquid-buffer'}
local headings={defines.direction.north,defines.direction.east,defines.direction.south,defines.direction.west}
local vectors={[0]={0,-1},[4]={1,0},[8]={0,1},[12]={-1,0}}
local function rotated(x,y,turns)
  for _=1,turns do x,y=-y,x end
  return x,y
end
script.on_init(function()
  if remote.interfaces.freeplay then
    for _,method in ipairs({'set_skip_intro','set_disable_crashsite'}) do
      if remote.interfaces.freeplay[method] then remote.call('freeplay',method,true) end
    end
  end
  local surface=game.create_surface('depot-art-test',{width=160,height=160})
  surface.daytime=0
  surface.freeze_daytime=true
  surface.request_to_generate_chunks({0,0},3)
  surface.force_generate_chunk_requests()
  for _,entity in pairs(surface.find_entities()) do entity.destroy() end
  surface.destroy_decoratives{}
  local tiles={}
  for x=-72,72 do
    for y=-72,72 do tiles[#tiles+1]={name='concrete',position={x,y}} end
  end
  surface.set_tiles(tiles)
  local result={engine=script.active_mods.base,default_entities=0,alternate_entities=0,ghosts=0,rotations=0,pipe_connections=0,graphical_tested=false}
  for role_index,role in ipairs(roles) do
    for size_index,size in ipairs({3}) do
      local row=role_index-1
      for index,heading in ipairs(headings) do
        local name='depot-art-'..role..'-'..size
        local position={-30+(index-1)*16+.5,-56+row*8+.5}
        local ghost=surface.create_entity{name='entity-ghost',inner_name=name,position=position,direction=heading,force='player'}
        assert(ghost and ghost.direction==heading,'ghost orientation')
        ghost.destroy()
        result.ghosts=result.ghosts+1
        assert(surface.can_place_entity{name=name,position=position,direction=heading,force='player'})
        local entity=surface.create_entity{name=name,position=position,direction=heading,force='player'}
        assert(entity.direction==heading,'placed orientation')
        for step=1,4 do
          assert(entity.rotate{},'rotation failed')
          assert(entity.direction==headings[(index-1+step)%4+1],'rotation heading')
          result.rotations=result.rotations+1
        end
        for _,port in ipairs(definitions[role][size].ports) do
          local vector=vectors[port.direction]
          local x,y=rotated(port.position[1]+vector[1],port.position[2]+vector[2],index-1)
          local target={position[1]+x,position[2]+y}
          assert(surface.can_place_entity{name='pipe',position=target})
          local pipe=surface.create_entity{name='pipe',position=target,force='player'}
          local matched=false
          for _,connection in ipairs(entity.get_fluid_box_pipe_connections(1)) do
            if connection.target==pipe then matched=true end
          end
          assert(matched,'art prototype failed pipe attachment')
          result.pipe_connections=result.pipe_connections+1
        end
        if entity.fluids_count>0 then entity.insert_fluid{name=role=='fuel' and 'light-oil' or 'water',amount=500} end
        result.default_entities=result.default_entities+1
      end
      local alternate=surface.create_entity{name='depot-art-'..role..'-'..size..'-alternate',position={44.5,-55.5+row*8},direction=defines.direction.south,force='player'}
      assert(alternate and alternate.valid)
      result.alternate_entities=result.alternate_entities+1
    end
  end
  game.forces.player.chart(surface,{{-72,-72},{72,72}})
  storage.pending_entries={}
  storage.result=result
  helpers.write_file('depot-art-check.json',helpers.table_to_json(result),false)
  log('DEPOT_ART_CHECK passed 28 directional entities, 7 alternate palettes and 20 pipe connections')
end)
local function queue_entry(event)
  storage.pending_entries=storage.pending_entries or {}
  storage.pending_entries[event.player_index]=game.tick+1
end
script.on_event(defines.events.on_player_created,queue_entry)
script.on_event(defines.events.on_player_joined_game,queue_entry)
script.on_event(defines.events.on_tick,function(event)
  for player_index,tick in pairs(storage.pending_entries or {}) do
    if event.tick>=tick then
      local player=game.get_player(player_index)
      assert(player.teleport({-35,-56},game.surfaces['depot-art-test']))
      player.print('Depot art fixture. Rows contain one 3x3 variant per role. Columns face N/E/S/W. Alternate palettes at the east end are unconnected for cover inspection.')
      storage.pending_entries[player_index]=nil
    end
  end
end)
