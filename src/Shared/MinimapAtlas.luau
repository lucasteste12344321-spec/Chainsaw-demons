-- Cartografia 2D gerada no Studio. X cresce para a direita; Z cresce para baixo (norte = -Z).
-- Para mudar a geometria do mapa, refazer o bake em assets/ui/minimap/bake-studio.luau.
return {
	TileSize = 2304,
	Resolution = 1024,
	Tiles = {
		{ Image = "rbxassetid://80072324112256", Center = Vector3.new(-1248, 0, -3456) },
		{ Image = "rbxassetid://79795137174844", Center = Vector3.new(1056, 0, -3456) },
		{ Image = "rbxassetid://105096086218457", Center = Vector3.new(-1248, 0, -1152) },
		{ Image = "rbxassetid://111683808080756", Center = Vector3.new(1056, 0, -1152) },
		{ Image = "rbxassetid://97604633847471", Center = Vector3.new(-1248, 0, 1152) },
		{ Image = "rbxassetid://115335619668673", Center = Vector3.new(1056, 0, 1152) },
	},
}
