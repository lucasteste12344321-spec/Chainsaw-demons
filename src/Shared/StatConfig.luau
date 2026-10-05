-- Números de status e level usados pelo servidor (PlayerData, inimigos) e pela HUD (HUB_GUI).
-- Os stats do jogador (player.Stats) são a base abaixo mais os nós da árvore de habilidades (SkillTreeData).
local StatConfig = {}

StatConfig.BaseStats = {
	HP = 100,
	Energia = 100,
	Forca = 10,
	Defesa = 5,
	Velocidade = 16,
}

-- Sistema antigo de pontos de status (antes da árvore). Não é mais usado para distribuir pontos.
StatConfig.StatGain = {
	HP = 10,
	Energia = 10,
	Forca = 2,
	Defesa = 1,
	Velocidade = 1,
}
StatConfig.StatMax = {
	Defesa = 60,
	Velocidade = 22,
}

StatConfig.MaxLevel = 100 -- no level máximo o XP para de contar (a HUD mostra MAX)
StatConfig.PointsPerLevel = 1 -- pontos da árvore de habilidades por level
StatConfig.ResetCostPerLevel = 25 -- resetar a árvore custa isso x level em Gold

-- XP para passar do level atual para o próximo.
-- Ritmo pensado para ~2 horas até o level 25 (contas em docs/mapa-fase4.md):
--   um inimigo de level L dá ~15 + 10L de XP (EnemyData), ~5 inimigos por minuto na zona do level,
--   e as missões da rota Humano comum dão ~20% do XP total (105.900 XP do level 1 ao 25).
function StatConfig.XPNeeded(level)
	return 100 + 100 * level + 15 * level * level
end

function StatConfig.ResetCost(level)
	return StatConfig.ResetCostPerLevel * level
end

-- Dano extra por ataque (os golpes dos estilos de combate somam isso ao dano base)
function StatConfig.DamageBonus(forca)
	return math.max(0, forca - StatConfig.BaseStats.Forca)
end

-- Fração do dano recebido que a Defesa anula (0 a 0.6)
function StatConfig.DamageReduction(defesa)
	return math.clamp(defesa / 100, 0, 0.6)
end

return StatConfig
