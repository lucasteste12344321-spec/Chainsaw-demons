-- Missões diárias (DailyService no servidor; aparelho no cliente: Device.client). Três por dia, sorteadas por jogador
-- e por dia (sempre as mesmas no mesmo dia), renovam à meia-noite de Brasília (o mesmo dia dos giros do VIP).
-- Completar as três dá o bônus do dia (giro de clã) e conta a sequência de dias (Streak), que aumenta o Gold.
-- Kind: o que conta (DailyService ouve o QuestModule):
--   "Kill"     inimigo derrotado (Target = tipo do EnemyData ou nil = qualquer)
--   "Boss"     chefe derrotado com a sua ajuda (qualquer chefe do BossData)
--   "Fish"     peixe pescado
--   "Power"    poder do caminho usado (V/B); só sorteada para quem já tem caminho
local DailyData = {}

DailyData.Count = 3
DailyData.DayOffsetSeconds = -3 * 3600 -- meia-noite de Brasília (UTC-3)

-- Missões possíveis. Goal pode crescer com o level (GoalPerLevel por level, até GoalMax). MinLevel/MaxLevel limitam
-- quem recebe. Weight: chance relativa no sorteio.
DailyData.Pool = {
	{ Id = "KillAny", Kind = "Kill", Text = "Derrote %d inimigos", Goal = 15, GoalPerLevel = 0.3, GoalMax = 40, Weight = 3 },
	{ Id = "KillGoblin", Kind = "Kill", Target = "Goblin", Text = "Derrote %d Goblins", Goal = 12, MaxLevel = 15, Weight = 2 },
	{ Id = "KillLadrao", Kind = "Kill", Target = "GoblinLadrao", Text = "Derrote %d Goblins Ladrões", Goal = 10, MinLevel = 10, Weight = 2 },
	{ Id = "Boss", Kind = "Boss", Text = "Ajude a derrotar %d chefe (Rei Goblin ou Lord Chainsaw)", Goal = 1, MinLevel = 12, Weight = 1 },
	{ Id = "Fish", Kind = "Fish", Text = "Pesque %d peixes", Goal = 4, Weight = 2 },
	{ Id = "Power", Kind = "Power", Text = "Use os poderes do seu caminho %d vezes", Goal = 12, NeedsPath = true, Weight = 2 },
}

-- Recompensa de cada missão (a partir do level): Gold e uma fração do XP que falta para o próximo level
function DailyData.Reward(level)
	return { Gold = 60 + 12 * level, XPFraction = 0.15 }
end

-- Bônus por completar as três: giro de clã e +10% de Gold por dia seguido (até +60%)
DailyData.Bonus = { Spins = 1, StreakGold = 0.1, StreakMax = 7 }

function DailyData.Day(now)
	return math.floor((now + DailyData.DayOffsetSeconds) / 86400)
end

function DailyData.NextDayAt(now)
	return (DailyData.Day(now) + 1) * 86400 - DailyData.DayOffsetSeconds
end

local byId = {}
for _, entry in DailyData.Pool do
	byId[entry.Id] = entry
end

function DailyData.Get(id)
	return byId[id]
end

function DailyData.GoalFor(entry, level)
	local goal = entry.Goal + math.floor((entry.GoalPerLevel or 0) * level)
	return math.min(goal, entry.GoalMax or goal)
end

function DailyData.TextFor(entry, goal)
	return string.format(entry.Text, goal)
end

-- Sorteio do dia: sempre o mesmo para o mesmo jogador no mesmo dia
function DailyData.Roll(userId, day, level, hasPath)
	local rng = Random.new(userId * 7919 + day * 104729)
	local candidates = {}
	for _, entry in DailyData.Pool do
		if (entry.MinLevel or 0) <= level and level <= (entry.MaxLevel or math.huge) and (hasPath or not entry.NeedsPath) then
			table.insert(candidates, entry)
		end
	end
	local chosen = {}
	while #chosen < DailyData.Count and #candidates > 0 do
		local total = 0
		for _, entry in candidates do
			total += entry.Weight or 1
		end
		local pick = rng:NextNumber(0, total)
		for index, entry in candidates do
			pick -= entry.Weight or 1
			if pick <= 0 or index == #candidates then
				table.insert(chosen, { Id = entry.Id, Goal = DailyData.GoalFor(entry, level), Progress = 0, Claimed = false })
				table.remove(candidates, index)
				break
			end
		end
	end
	return chosen
end

-- Dados salvos no perfil (PlayerData): { Day, Missions = { { Id, Goal, Progress, Claimed } }, BonusClaimed, Streak,
-- LastFullDay }
function DailyData.Reconcile(saved)
	saved = if type(saved) == "table" then saved else {}
	local function number(value, default)
		return if type(value) == "number" and value == value then math.floor(value) else default
	end
	local missions = {}
	if type(saved.Missions) == "table" then
		for _, mission in saved.Missions do
			if type(mission) == "table" and byId[mission.Id] and #missions < DailyData.Count then
				table.insert(missions, {
					Id = mission.Id,
					Goal = math.max(1, number(mission.Goal, 1)),
					Progress = math.max(0, number(mission.Progress, 0)),
					Claimed = mission.Claimed == true,
				})
			end
		end
	end
	return {
		Day = number(saved.Day, -1),
		Missions = missions,
		BonusClaimed = saved.BonusClaimed == true,
		Streak = math.max(0, number(saved.Streak, 0)),
		LastFullDay = number(saved.LastFullDay, -1),
	}
end

return DailyData
