-- Roads turned light green on the map and freighters violet (prototypes/roads.lua and
-- prototypes/freighter-drone.lua). A force's chart keeps each chunk as it was drawn, so in saves
-- from before, roads stayed brown until something redrew their chunk, such as a radar or a
-- freighter going past (the owner's save, November 14, 2026). Redraw every chart once.
for _, force in pairs(game.forces) do
  force.rechart()
end
