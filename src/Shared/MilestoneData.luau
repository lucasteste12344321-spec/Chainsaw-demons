-- Marcos (Milestones, pedido do usuário em 2026-10-05, com uma imagem de referência): metas de longo prazo por save, cada
-- uma com vários níveis e o botão de resgatar. O servidor (MilestoneService) conta e paga; o cliente mostra no aparelho
-- (Device.client, aba MILESTONES).
-- Source: de onde vem o progresso
--   "Kills"   inimigos derrotados (contador do save, conta a partir desta versão)
--   "Bosses"  chefes derrotados com a sua ajuda (contador do save)
--   "Fish"    peixes pescados (profile.Fishing.Catches: conta os de antes)
--   "Quests"  missões concluídas (profile.Quests.Completed: conta as de antes)
--   "Level"   level atual
-- Tiers: { Goal, Gold, Spins? }. Resgate em ordem (o nível seguinte só depois do anterior).
local MilestoneData = {}

MilestoneData.Tracks = {
	{
		Id = "Kills",
		Icon = "fists", -- Icons (imagem; sem ela fica o Glyph)
		Name = "Devil Hunter",
		Glyph = "狩",
		Text = "Defeat %d devils",
		Source = "Kills",
		Tiers = {
			{ Goal = 10, Gold = 150 },
			{ Goal = 25, Gold = 300 },
			{ Goal = 50, Gold = 500, Spins = 1 },
			{ Goal = 100, Gold = 800 },
			{ Goal = 250, Gold = 1500, Spins = 1 },
			{ Goal = 500, Gold = 2500 },
			{ Goal = 1000, Gold = 4000, Spins = 2 },
			{ Goal = 2500, Gold = 8000 },
			{ Goal = 5000, Gold = 15000, Spins = 3 },
		},
	},
	{
		Id = "Bosses",
		Icon = "milestones", -- Icons (imagem; sem ela fica o Glyph)
		Name = "Boss Slayer",
		Glyph = "王",
		Text = "Help defeat %d bosses",
		Source = "Bosses",
		Tiers = {
			{ Goal = 1, Gold = 500 },
			{ Goal = 3, Gold = 1000, Spins = 1 },
			{ Goal = 5, Gold = 1500 },
			{ Goal = 10, Gold = 3000, Spins = 1 },
			{ Goal = 25, Gold = 6000, Spins = 2 },
			{ Goal = 50, Gold = 12000, Spins = 3 },
		},
	},
	{
		Id = "Quests",
		Icon = "quests", -- Icons (imagem; sem ela fica o Glyph)
		Name = "Problem Solver",
		Glyph = "務",
		Text = "Complete %d quests",
		Source = "Quests",
		Tiers = {
			{ Goal = 5, Gold = 200 },
			{ Goal = 10, Gold = 400 },
			{ Goal = 25, Gold = 900, Spins = 1 },
			{ Goal = 50, Gold = 2000 },
			{ Goal = 100, Gold = 4000, Spins = 2 },
		},
	},
	{
		Id = "Fish",
		Icon = "fishing", -- Icons (imagem; sem ela fica o Glyph)
		Name = "Angler",
		Glyph = "釣",
		Text = "Catch %d fish",
		Source = "Fish",
		Tiers = {
			{ Goal = 5, Gold = 150 },
			{ Goal = 15, Gold = 300 },
			{ Goal = 30, Gold = 600, Spins = 1 },
			{ Goal = 60, Gold = 1200 },
			{ Goal = 120, Gold = 2500, Spins = 1 },
		},
	},
	{
		Id = "Level",
		Icon = "xp", -- Icons (imagem; sem ela fica o Glyph)
		Name = "Rising Power",
		Glyph = "昇",
		Text = "Reach level %d",
		Source = "Level",
		Tiers = {
			{ Goal = 5, Gold = 200 },
			{ Goal = 10, Gold = 500 },
			{ Goal = 25, Gold = 1500, Spins = 1 },
			{ Goal = 50, Gold = 4000, Spins = 1 },
			{ Goal = 75, Gold = 8000, Spins = 2 },
			{ Goal = 100, Gold = 15000, Spins = 3 },
		},
	},
}

local byId = {}
for _, track in MilestoneData.Tracks do
	byId[track.Id] = track
end

function MilestoneData.Get(id)
	return byId[id]
end

function MilestoneData.TierText(track, tier)
	return string.format(track.Text, tier.Goal)
end

function MilestoneData.RewardText(tier)
	local parts = { `{tier.Gold} Gold` }
	if tier.Spins and tier.Spins > 0 then
		table.insert(parts, if tier.Spins == 1 then "1 clan spin" else `{tier.Spins} clan spins`)
	end
	return table.concat(parts, " + ")
end

-- Dados salvos (PlayerData): { Counts = { Kills, Bosses }, Claimed = { [trilha] = níveis resgatados } }
function MilestoneData.Reconcile(saved)
	saved = if type(saved) == "table" then saved else {}
	local function count(value)
		return if type(value) == "number" and value == value and value >= 0 then math.floor(value) else 0
	end
	local counts = if type(saved.Counts) == "table" then saved.Counts else {}
	local claimed = {}
	if type(saved.Claimed) == "table" then
		for id, value in saved.Claimed do
			local track = byId[id]
			if track then
				claimed[id] = math.min(count(value), #track.Tiers)
			end
		end
	end
	return {
		Counts = { Kills = count(counts.Kills), Bosses = count(counts.Bosses) },
		Claimed = claimed,
	}
end

return MilestoneData
