-- Tempos e alcance compartilhados da invocacao da Raposa.
return table.freeze({
	AimAnimation = "rbxassetid://76984555934035",
	AimMarker = "Aim",
	AimHoldTime = 0.6,
	AimDuration = 2.1666667,
	MaxAimDistance = 60,
	MaxHoldTime = 8,
	ImpactDelay = 0.45,
	Duration = 1.75,
	Scale = 3,
	PortalEmergence = 0.28,
	ImpactRadius = 13, -- raio da cratera quando o servidor não manda (o dano usa o Radius do PathData)
	-- Finalização (PathData Finisher): tempo a mais com o Kon mastigando a presa e quantas mordidas ele dá
	DevourTime = 1.1,
	DevourChews = 3,
	DevourSounds = { Grab = 9114631768, Splat = 9114741339, Chew = 9119560180 }, -- Pro Sound Effects (públicos)
	-- Bote da Raposa (ContractData, Kind "FoxLunge"): o portal abre atrás do jogador em LungeDelay, a cabeça percorre o
	-- caminho em LungeTime (saindo LungeBehind studs atrás dele) e some LungeFade depois da mordida final
	LungeDelay = 0.3,
	LungeTime = 0.32,
	LungeBehind = 4,
	LungeScale = 1.7,
	LungeFade = 0.45,
	-- Gesto de invocação no B: um trecho da animação de mira (AimAnimation) mais rápido
	CastStart = 0.25,
	CastSpeed = 1.6,
	CastLength = 0.7,
})
