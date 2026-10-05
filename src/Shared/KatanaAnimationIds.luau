-- Animações R6 autorais; os tempos são os marcadores publicados a 60 FPS.
-- Este módulo apenas descreve os assets. A lógica das skills pertence ao Claude.
return table.freeze({
	Z = table.freeze({
		Name = "Katana_Z_AdvanceCut",
		AnimationId = "rbxassetid://99592683576869",
		Duration = 0.95,
		Markers = table.freeze({Dash = 0.15, Slash = 0.35, End = 0.95}),
	}),
	X = table.freeze({
		Name = "Katana_X_GrabCut",
		AnimationId = "rbxassetid://124017152338185",
		Duration = 1.4,
		Markers = table.freeze({Reach = 0.1333333, Grab = 0.3, Strike = 0.7333333, Release = 1.0166667, End = 1.4}),
	}),
	C = table.freeze({
		Name = "Katana_C_DrawCut",
		AnimationId = "rbxassetid://104255597432195",
		Duration = 1.45,
		Markers = table.freeze({Charge = 0.2333333, Slash = 0.4666667, Sheathe = 1.0166667, End = 1.45}),
	}),
	XTarget = table.freeze({
		Name = "Katana_X_Target",
		AnimationId = "rbxassetid://101371885624602",
		Duration = 1.4,
		Markers = table.freeze({Grab = 0.3, Strike = 0.7333333, Release = 1.0166667, End = 1.4}),
	}),
})
