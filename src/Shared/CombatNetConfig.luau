-- Limites compartilhados. O servidor continua sendo dono da autorização e dos recursos.
return table.freeze({
	RewindWindow = 0.25,
	HistoryDuration = 0.5,
	HistoryRate = 30,
	HistoryGap = 0.12,
	TeleportStep = 16,
	TimestampSlack = 0.08,
	FutureSlack = 0.025,
	OriginTolerance = 6,
	OriginLookback = 0.35, -- quanto do caminho guardado antes do envio vale para conferir a origem
	DashTimestampSlack = 0.15, -- folga a mais para o pedido de dash chegar (oscilação de ping)
	DashCost = 20,
	DashDistance = 35,
	DashTime = 0.3,
	DashCooldown = 1,
	StaminaRegen = 12,
	DashRequestGap = 0.1,
	DashReplyTimeout = 1,
	WallBox = Vector3.new(1.8, 3.9, 0.6),
	WallBoxDrop = 0.45,
	WallNormalY = 0.6,
})
