-- IDs das animações do personagem (fora do combate). As do combate ficam em CombatStyles (Animations de cada estilo).
-- As animações precisam estar publicadas na conta/grupo dono do jogo e ser do mesmo rig do jogo (R6).
-- 0 = sem animação própria: nas padrão fica a do Roblox, nas de movimento não toca nada.
local CharacterAnimations = {}

-- Trocam as animações padrão do Roblox (script Animate do personagem). Aplicadas pelo CharacterAnimations.server.
CharacterAnimations.Default = {
	Idle = 0, -- parado
	Walk = 81266166601298, -- andando (sem arma equipada; com os punhos toca o Walk do CombatStyles)
	Jump = 127807131779382,
	Fall = 0,
	Climb = 0,
}

-- Movimento próprio (StaminaDashRunscript). O dash vai para onde o jogador está andando e toca a animação
-- dessa direção (parado: para a frente).
CharacterAnimations.Movement = {
	Sprint = 80849474243778, -- correndo (Ctrl)
	Dash = 92641717520859, -- dash para a frente (W)
	DashBack = 135018427002521, -- dash para trás (S)
	DashLeft = 115371854178215, -- dash para a esquerda (A)
	DashRight = 126038266119096, -- dash para a direita (D)
}

-- ID válido (número > 0) ou nil
function CharacterAnimations.Id(value)
	return if type(value) == "number" and value > 0 then value else nil
end

return CharacterAnimations
