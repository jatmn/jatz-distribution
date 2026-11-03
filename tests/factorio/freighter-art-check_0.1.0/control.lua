script.on_init(function()
  -- This fixture is also loaded through Freeplay. Suppress its intro before
  -- a player joins, then enter our surface after scenario event handlers run.
  if remote.interfaces.freeplay then
    for _, method in ipairs({"set_skip_intro", "set_disable_crashsite"}) do
      if remote.interfaces.freeplay[method] then remote.call("freeplay",method,true) end
    end
  end
  storage.pending_entries={}
  local surface=game.create_surface("freighter-art-test", {width=128,height=128})
  surface.daytime=0
  surface.freeze_daytime=true
  surface.request_to_generate_chunks({0,0},3)
  surface.force_generate_chunk_requests()
  for _, entity in pairs(surface.find_entities()) do entity.destroy() end
  surface.destroy_decoratives{}
  local tiles={}
  for x=-60,60 do
    for y=-60,60 do
      tiles[#tiles+1]={name="concrete",position={x,y}}
    end
  end
  surface.set_tiles(tiles)
  assert(surface.count_entities_filtered{}==0,"test pad still contains scenery")
  assert(surface.count_tiles_filtered{area={{-60,-60},{61,61}},name="concrete"}==121*121,
    "test pad is not completely concreted")
  for i=0,63 do
    local entity=surface.create_entity{name="quinityn-freighter-art-check",position={-42+(i%8)*12,-42+math.floor(i/8)*12},force="player"}
    assert(entity and entity.valid, "vehicle creation failed")
    entity.orientation=i/64
    assert(entity.get_fuel_inventory().insert{name="coal",count=20}==20,"fuel insertion failed")
    assert(math.abs(entity.orientation-i/64)<0.00001, "orientation mismatch")
  end
  local alternate=surface.create_entity{name="quinityn-freighter-art-check-alternate",position={54,54},force="player"}
  assert(alternate and alternate.valid)
  alternate.orientation=40/64
  assert(alternate.get_fuel_inventory().insert{name="coal",count=20}==20,"alternate fuel insertion failed")
  game.forces.player.chart(surface, {{-64,-64},{64,64}})
  log("FREIGHTER_ART_CHECK passed 64 orientations and alternate palette prototype")
end)

local function enter_test_surface(player_index)
  local player=game.get_player(player_index)
  local surface=game.surfaces["freighter-art-test"]
  if player and surface then
    assert(player.teleport({0,0},surface),"test surface teleport failed")
    player.print("Jat'z Distribution artwork fixture. 64 headings form an 8 by 8 grid. Alternate palette is at {54,54}. Vehicles are fueled for driving tests.")
  end
end

local function queue_entry(event)
  storage.pending_entries=storage.pending_entries or {}
  storage.pending_entries[event.player_index]=game.tick+1
end
script.on_event(defines.events.on_player_created,queue_entry)
script.on_event(defines.events.on_player_joined_game,queue_entry)
script.on_event(defines.events.on_tick,function(event)
  for player_index,tick in pairs(storage.pending_entries or {}) do
    if event.tick>=tick then
      enter_test_surface(player_index)
      storage.pending_entries[player_index]=nil
    end
  end
end)
