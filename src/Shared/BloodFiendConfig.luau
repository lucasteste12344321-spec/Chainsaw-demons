-- Tempos compartilhados entre animacao, efeitos e resolucao no servidor.
return table.freeze({
	EffectDistance = 220,
	MaxCasts = 16,
	LancaSangue = {
		AnimationId = 0, -- preenchido apos a publicacao do clip R6
		FormTime = 0.10,
		ReleaseTime = 0.4333333,
		Duration = 1.0,
		Marker = "Release",
	},
	MarteloSangue = {
		AnimationId = 0,
		FormTime = 0.10,
		ImpactTime = 0.7333333,
		Duration = 1.4333333,
		Marker = "Hit",
		-- Pulo para a frente (2026-10-01, pedido do usuário): quem invoca salta no LeapStart (marcador "Charge") e cai no
		-- ImpactTime ("Hit"), até LeapDistance studs à frente (para antes de parede), subindo LeapHeight no meio. O martelo
		-- bate SlamOffset studs à frente de onde ele caiu (onde a cabeça dele encosta no chão na pose do "Hit"). O cliente
		-- de quem invoca move o próprio personagem (BloodFiendVFX); o servidor faz a mesma conta para o dano.
		LeapStart = 0.30,
		LeapDistance = 18,
		LeapHeight = 7,
		SlamOffset = 5,
	},
})
