
local SkillTreeData = {}

SkillTreeData.Version = 1

-- Distância entre dois nós do mesmo galho e o afastamento dos nós ao lado (em pixels, zoom 100%)
SkillTreeData.Step = 125
SkillTreeData.Fork = 90

-- Icon: kanji (a tela é preto e branco, estilo mangá; emoji sairia colorido)
-- Angle: direção do galho na tela (0 = direita, 90 = para baixo). Os estilos ficam lado a lado, à direita.
SkillTreeData.Branches = {
	Punhos = { Name = "FISTS", Icon = "拳", Angle = -30, Color = Color3.fromRGB(214, 22, 32) },
	Katana = { Name = "KATANA", Icon = "刀", Angle = 30, Color = Color3.fromRGB(225, 225, 235) },
	Forca = { Name = "STRENGTH", Icon = "力", Angle = -90, Color = Color3.fromRGB(255, 122, 24) },
	Vitalidade = { Name = "VITALITY", Icon = "命", Angle = -150, Color = Color3.fromRGB(235, 70, 95) },
	Guarda = { Name = "GUARD", Icon = "守", Angle = 150, Color = Color3.fromRGB(70, 150, 255) },
	Agilidade = { Name = "AGILITY", Icon = "速", Angle = 90, Color = Color3.fromRGB(255, 204, 36) },
}

-- Técnicas travadas pela árvore (os estilos apontam para elas em CombatStyles: Technique = "...")
SkillTreeData.Techniques = {
	PunhosRajada = { Name = "Barrage", Key = "Z", Style = "Punhos" },
	PunhosCarregado = { Name = "Charged Punch", Key = "X", Style = "Punhos" },
	PunhosUppercut = { Name = "Aerial Uppercut", Key = "Space + 4th punch", Style = "Punhos" },
	KatanaAvanco = { Name = "Dashing Slash", Key = "Z", Style = "Katana" },
	KatanaAgarrao = { Name = "Grab", Key = "X", Style = "Katana" },
	KatanaSaque = { Name = "Quick Draw", Key = "C", Style = "Katana" },
	KatanaUppercut = { Name = "Rising Slash", Key = "Space + 4th slash", Style = "Katana" },
}

-- Nome dos estilos para o jogador (o Id interno continua "Punhos", "Motosserra": salvo nos perfis)
SkillTreeData.StyleNames = { Punhos = "Fists", Katana = "Katana", Motosserra = "Chainsaw" }
function SkillTreeData.StyleName(id)
	return SkillTreeData.StyleNames[id] or id
end

-- Maestria: XP por golpe que acerta com o estilo; para ir do nível L ao L+1 precisa de Need(L).
-- Até 300 (2026-10-01, formas dos contratos: a fusão pede 120 e a Ultimate 300; ContractData). A árvore usa só
-- os primeiros níveis (3 a 30). Cada nível custa 20 x L até o 25 e depois 500 fixos: 30 = 9 mil acertos,
-- 120 = 54 mil (umas 15 h lutando) e 300 = 144 mil (umas 40 h).
SkillTreeData.Mastery = {
	MaxLevel = 300,
	XPPerHit = 1,
	Need = function(level)
		return math.min(20 * level, 500)
	end,
}

local function node(id, branch, depth, side, name, icon, cost, requires, effects, extra)
	local entry = {
		Id = id,
		Branch = branch,
		Depth = depth,
		Side = side,
		Name = name,
		Icon = icon,
		Cost = cost,
		Requires = requires,
		Effects = effects or {},
	}
	for key, value in extra or {} do
		entry[key] = value
	end
	return entry
end

SkillTreeData.Nodes = {
	node("Root", nil, 0, 0, "Character", "鎖", 0, {}, {}, {
		Default = true,
		Flavor = "Every devil hunter starts somewhere.",
	}),

	-- ===== Punhos (estilo): técnicas pedem maestria =====
	node("Punhos", "Punhos", 1, 0, "Style: Fists", "拳", 0, { "Root" }, {}, {
		Default = true,
		Flavor = "5-punch combo and guard (F). Fight with your Fists to raise mastery and unlock the techniques.",
	}),
	node("PunhosRajada", "Punhos", 2, 0, "Barrage", "連", 3, { "Punhos" }, { Technique = "PunhosRajada" }, {
		Mastery = { Style = "Punhos", Level = 6 },
		Flavor = "A fast flurry of punches that pins the target in front of you.",
	}),
	node("PunhosUppercut", "Punhos", 2, -1, "Aerial Uppercut", "昇", 2, { "Punhos" }, { Technique = "PunhosUppercut" }, {
		Mastery = { Style = "Punhos", Level = 3 },
		Flavor = "In the air, the 4th punch of the combo launches the target upward.",
	}),
	node("PunhosCarregado", "Punhos", 3, 0, "Charged Punch", "溜", 4, { "PunhosRajada" }, { Technique = "PunhosCarregado" }, {
		Mastery = { Style = "Punhos", Level = 12 },
		Flavor = "Hold to charge and release: the longer the charge, the stronger it is. A full charge breaks guards.",
	}),
	node("PunhosRajadaLonga", "Punhos", 3, 1, "Long Barrage", "乱", 4, { "PunhosRajada" }, { RajadaHits = 3 }, {
		Mastery = { Style = "Punhos", Level = 15 },
	}),
	node("PunhosTreinados", "Punhos", 3, -1, "Trained Fists", "闘", 3, { "PunhosUppercut" }, { Damage_Punhos = 0.1 }, {
		Mastery = { Style = "Punhos", Level = 8 },
	}),
	node("PunhosCargaRapida", "Punhos", 4, 0, "Quick Charge", "瞬", 4, { "PunhosCarregado" }, { ChargeTime = 0.3 }, {
		Mastery = { Style = "Punhos", Level = 20 },
	}),
	node("PunhosMestre", "Punhos", 5, 0, "Fist Master", "王", 6, { "PunhosCargaRapida" }, { Damage_Punhos = 0.15 }, {
		Mastery = { Style = "Punhos", Level = 30 },
	}),

	-- ===== Katana (estilo ensinado pelo Mestre Espadachim, level 15): o 1º nó pede maestria 1, então só quem já tem
	-- a katana (e cortou com ela) chega nas técnicas =====
	node("Katana", "Katana", 1, 0, "Style: Katana", "刀", 0, { "Root" }, {}, {
		Mastery = { Style = "Katana", Level = 1 },
		Flavor = "5-slash combo and guard (F). Learn it from the Master Swordsman (level 15) and slash with it to unlock.",
	}),
	node("KatanaAvanco", "Katana", 2, 0, "Dashing Slash", "閃", 2, { "Katana" }, { Technique = "KatanaAvanco" }, {
		Mastery = { Style = "Katana", Level = 3 },
		Flavor = "Dash forward in a straight line, slicing everyone in your path. The cuts land a moment later.",
	}),
	node("KatanaUppercut", "Katana", 2, 1, "Rising Slash", "昇", 2, { "Katana" }, { Technique = "KatanaUppercut" }, {
		Mastery = { Style = "Katana", Level = 5 },
		Flavor = "In the air, the 4th slash of the combo launches the target upward.",
	}),
	node("KatanaAgarrao", "Katana", 3, 0, "Grab", "掴", 3, { "KatanaAvanco" }, { Technique = "KatanaAgarrao" }, {
		Mastery = { Style = "Katana", Level = 8 },
		Flavor = "Grab whoever is in front of you (goes through guard), slash while holding them and throw them.",
	}),
	node("KatanaFio", "Katana", 3, 1, "Sharp Edge", "鋭", 3, { "KatanaUppercut" }, { Damage_Katana = 0.1 }, {
		Mastery = { Style = "Katana", Level = 10 },
	}),
	node("KatanaSaque", "Katana", 4, 0, "Quick Draw", "居", 4, { "KatanaAgarrao" }, { Technique = "KatanaSaque" }, {
		Mastery = { Style = "Katana", Level = 12 },
		Flavor = "Sheathe the blade and draw it in a wide slash in front of you. Breaks guards.",
	}),
	node("KatanaMestre", "Katana", 5, 0, "Blade Master", "剣", 6, { "KatanaSaque" }, { Damage_Katana = 0.15 }, {
		Mastery = { Style = "Katana", Level = 25 },
	}),

	-- ===== Força =====
	node("Forca1", "Forca", 1, 0, "Iron Fist I", "力", 1, { "Root" }, { Forca = 13 }),
	node("Forca2", "Forca", 2, 0, "Iron Fist II", "力", 2, { "Forca1" }, { Forca = 16 }),
	node("ForcaGuarda", "Forca", 2, 1, "Heavy Blow", "重", 3, { "Forca1" }, { GuardDamage = 0.25 }),
	node("Forca3", "Forca", 3, 0, "Iron Fist III", "力", 3, { "Forca2" }, { Forca = 24 }),
	node("Forca4", "Forca", 4, 0, "Iron Fist IV", "力", 3, { "Forca3" }, { Forca = 32 }),
	node("ForcaImpacto", "Forca", 4, -1, "Impact", "衝", 3, { "Forca3" }, { Knockback = 0.3 }),
	node("Forca5", "Forca", 5, 0, "Iron Fist V", "力", 4, { "Forca4" }, { Forca = 48 }),
	node("Forca6", "Forca", 6, 0, "Brutality", "血", 5, { "Forca5" }, { Forca = 64 }),
	node("Forca7", "Forca", 7, 0, "Wrecker", "鬼", 6, { "Forca6" }, { Forca = 96 }),

	-- ===== Vitalidade =====
	node("Vida1", "Vitalidade", 1, 0, "Vigor I", "命", 1, { "Root" }, { HP = 90 }),
	node("Vida2", "Vitalidade", 2, 0, "Vigor II", "命", 2, { "Vida1" }, { HP = 120 }),
	node("VidaRegen", "Vitalidade", 2, -1, "Regeneration", "癒", 3, { "Vida1" }, { Regen = 0.01 }, {
		Flavor = "After 5 seconds without taking damage.",
	}),
	node("Defesa1", "Vitalidade", 3, 0, "Thick Skin I", "盾", 3, { "Vida2" }, { Defesa = 5 }),
	node("Vida3", "Vitalidade", 4, 0, "Vigor III", "命", 3, { "Defesa1" }, { HP = 180 }),
	node("Defesa2", "Vitalidade", 5, 0, "Thick Skin II", "盾", 4, { "Vida3" }, { Defesa = 5 }),
	node("Vida4", "Vitalidade", 6, 0, "Vigor IV", "命", 4, { "Defesa2" }, { HP = 240 }),
	node("Defesa3", "Vitalidade", 7, 0, "Thick Skin III", "盾", 5, { "Vida4" }, { Defesa = 8 }),
	node("Vida5", "Vitalidade", 8, 0, "Vigor V", "命", 5, { "Defesa3" }, { HP = 330 }),
	node("VidaDemonio", "Vitalidade", 9, 0, "Devil Hide", "魔", 6, { "Vida5" }, { HP = 450, Defesa = 7 }),

	-- ===== Agilidade =====
	node("Agil1", "Agilidade", 1, 0, "Light Feet I", "速", 1, { "Root" }, { Velocidade = 1 }),
	node("Folego1", "Agilidade", 2, 0, "Stamina I", "息", 2, { "Agil1" }, { Energia = 25 }),
	node("Agil2", "Agilidade", 3, 0, "Light Feet II", "速", 2, { "Folego1" }, { Velocidade = 1 }),
	node("PuloDuplo", "Agilidade", 3, 1, "Double Jump", "跳", 4, { "Folego1" }, { DoubleJump = true }, {
		Flavor = "Press jump again in the air.",
	}),
	node("Folego2", "Agilidade", 4, 0, "Stamina II", "息", 3, { "Agil2" }, { Energia = 25, StaminaRegen = 0.25 }),
	node("Agil3", "Agilidade", 5, 0, "Light Feet III", "速", 3, { "Folego2" }, { Velocidade = 2 }),
	node("DashEconomico", "Agilidade", 5, -1, "Efficient Dash", "駆", 3, { "Folego2" }, { DashCost = 0.25 }),
	node("Agil4", "Agilidade", 6, 0, "Light Feet IV", "速", 4, { "Agil3" }, { Velocidade = 2 }),
	node("Folego3", "Agilidade", 7, 0, "Second Wind", "息", 5, { "Agil4" }, { Energia = 50, StaminaRegen = 0.25 }),

	-- ===== Guarda =====
	node("Guarda1", "Guarda", 1, 0, "Steady Guard I", "守", 1, { "Root" }, { GuardMax = 0.2 }),
	node("GuardaRegen1", "Guarda", 2, 0, "Recovery I", "再", 2, { "Guarda1" }, { GuardRegen = 0.3 }),
	node("Guarda2", "Guarda", 3, 0, "Steady Guard II", "守", 3, { "GuardaRegen1" }, { GuardMax = 0.2 }),
	node("Reflexo1", "Guarda", 3, 1, "Reflex", "眼", 3, { "GuardaRegen1" }, { ParryWindow = 0.05 }),
	node("GuardaRegen2", "Guarda", 4, 0, "Recovery II", "再", 3, { "Guarda2" }, { GuardRegen = 0.4 }),
	node("Muralha", "Guarda", 5, 0, "Bulwark", "壁", 4, { "GuardaRegen2" }, { BlockTaken = 0.05 }),
	node("Guarda3", "Guarda", 6, 0, "Steady Guard III", "守", 4, { "Muralha" }, { GuardMax = 0.3 }),
	node("Reflexo2", "Guarda", 6, -1, "Reflex II", "眼", 5, { "Muralha" }, { ParryWindow = 0.05 }),
}

SkillTreeData.ById = {}
for _, entry in SkillTreeData.Nodes do
	SkillTreeData.ById[entry.Id] = entry
end

function SkillTreeData.Get(id)
	return SkillTreeData.ById[id]
end

-- Posição do nó na tela da árvore (pixels a partir do centro, zoom 100%)
function SkillTreeData.Position(entry)
	if not entry.Branch then
		return Vector2.zero
	end
	local branch = SkillTreeData.Branches[entry.Branch]
	local angle = math.rad(branch.Angle)
	local direction = Vector2.new(math.cos(angle), math.sin(angle))
	local side = Vector2.new(-direction.Y, direction.X)
	return direction * (entry.Depth * SkillTreeData.Step) + side * (entry.Side * SkillTreeData.Fork)
end

-- Nível de maestria para um total de XP. Devolve (nível, XP dentro do nível, XP para o próximo)
function SkillTreeData.MasteryLevel(xp)
	local mastery = SkillTreeData.Mastery
	local level, rest = 0, math.max(0, math.floor(xp or 0))
	while level < mastery.MaxLevel do
		local need = mastery.Need(level + 1)
		if rest < need then
			return level, rest, need
		end
		rest -= need
		level += 1
	end
	return mastery.MaxLevel, 0, 0
end

-- XP total para chegar a um nível (o máximo, sem o nível; a maestria para de subir aí)
function SkillTreeData.MasteryXP(level)
	local total = 0
	for current = 1, math.clamp(level or SkillTreeData.Mastery.MaxLevel, 0, SkillTreeData.Mastery.MaxLevel) do
		total += SkillTreeData.Mastery.Need(current)
	end
	return total
end

local masteryCap
function SkillTreeData.MasteryCap()
	masteryCap = masteryCap or SkillTreeData.MasteryXP(SkillTreeData.Mastery.MaxLevel)
	return masteryCap
end

-- Conjunto de desbloqueados: os salvos + os padrão
function SkillTreeData.UnlockedSet(list)
	local set = {}
	for _, entry in SkillTreeData.Nodes do
		if entry.Default then
			set[entry.Id] = true
		end
	end
	for _, id in list or {} do
		if SkillTreeData.ById[id] then
			set[id] = true
		end
	end
	return set
end

-- Pontos gastos numa lista de nós
function SkillTreeData.Spent(list)
	local total = 0
	for _, id in list or {} do
		local entry = SkillTreeData.ById[id]
		if entry and not entry.Default then
			total += entry.Cost
		end
	end
	return total
end

-- Por que o nó ainda não pode ser desbloqueado (nil = pode). masteryLevels = { [Estilo] = nível }
function SkillTreeData.Blocker(entry, unlocked, masteryLevels, points)
	if unlocked[entry.Id] then
		return "Already unlocked"
	end
	local connected = #entry.Requires == 0
	for _, required in entry.Requires do
		if unlocked[required] then
			connected = true
			break
		end
	end
	if not connected then
		return "Unlock a node connected to this one first"
	end
	if entry.Mastery then
		local have = masteryLevels[entry.Mastery.Style] or 0
		if have < entry.Mastery.Level then
			return `Needs {SkillTreeData.StyleName(entry.Mastery.Style)} mastery {entry.Mastery.Level} (you have {have})`
		end
	end
	if points < entry.Cost then
		return `Needs {entry.Cost} point(s) (you have {points})`
	end
	return nil
end

-- Soma dos efeitos dos nós desbloqueados. Devolve (efeitos, técnicas)
function SkillTreeData.Compute(unlocked)
	local effects, techniques = {}, {}
	for id in unlocked do
		local entry = SkillTreeData.ById[id]
		if not entry then continue end
		for key, value in entry.Effects do
			if key == "Technique" then
				techniques[value] = true
			elseif type(value) == "boolean" then
				effects[key] = effects[key] or value
			else
				effects[key] = (effects[key] or 0) + value
			end
		end
	end
	return effects, techniques
end

local function percent(value)
	return `{math.floor(value * 100 + 0.5)}%`
end

-- Texto de cada efeito (a tela da árvore mostra a lista)
local EFFECT_TEXT = {
	HP = function(v) return `+{v} max health` end,
	Forca = function(v) return `+{v} damage per hit` end,
	Defesa = function(v) return `+{v}% damage reduction` end,
	Velocidade = function(v) return `+{v} speed` end,
	Energia = function(v) return `+{v} stamina (for dashing)` end,
	Regen = function(v) return `Regenerates {percent(v)} health per second out of combat` end,
	GuardDamage = function(v) return `+{percent(v)} damage to blocking guards` end,
	Knockback = function(v) return `+{percent(v)} knockback on hits` end,
	StaminaRegen = function(v) return `+{percent(v)} stamina recovery` end,
	DashCost = function(v) return `Dash uses {percent(v)} less stamina` end,
	GuardMax = function(v) return `+{percent(v)} max guard` end,
	GuardRegen = function(v) return `+{percent(v)} guard recovery` end,
	ParryWindow = function(v) return `+{v} s parry window` end,
	BlockTaken = function(v) return `{percent(v)} less damage through your guard` end,
	Damage_Punhos = function(v) return `+{percent(v)} Fists damage` end,
	Damage_Katana = function(v) return `+{percent(v)} Katana damage` end,
	RajadaHits = function(v) return `+{v} punches in Barrage` end,
	ChargeTime = function(v) return `Charged Punch charges {percent(v)} faster` end,
	DoubleJump = function() return "Double jump" end,
	DodgeChance = function(v) return `{percent(v)} chance to dodge a hit` end,
	XPBonus = function(v) return `+{percent(v)} XP gained` end,
	GoldBonus = function(v) return `+{percent(v)} Gold gained` end,
}

function SkillTreeData.Describe(entry)
	local lines = {}
	for key, value in entry.Effects do
		if key == "Technique" then
			local technique = SkillTreeData.Techniques[value]
			if technique then
				table.insert(lines, 1, `Unlocks: {technique.Name} ({technique.Key})`)
			end
		elseif EFFECT_TEXT[key] then
			table.insert(lines, EFFECT_TEXT[key](value))
		end
	end
	return lines
end

-- Versão curta de cada efeito (pílulas de bônus da HUD e do inventário): ícone (kanji), nome e valor
SkillTreeData.EffectInfo = {
	Forca = { Icon = "力", Name = "Strength" },
	HP = { Icon = "命", Name = "Health" },
	Defesa = { Icon = "盾", Name = "Defense" },
	Velocidade = { Icon = "速", Name = "Speed" },
	Energia = { Icon = "息", Name = "Stamina" },
	Damage_Punhos = { Icon = "拳", Name = "Fists Damage", Percent = true },
	Damage_Katana = { Icon = "刀", Name = "Katana Damage", Percent = true },
	GuardDamage = { Icon = "重", Name = "Guard Damage", Percent = true },
	Knockback = { Icon = "衝", Name = "Knockback", Percent = true },
	Regen = { Icon = "癒", Name = "Regeneration" },
	GuardMax = { Icon = "守", Name = "Max Guard", Percent = true },
	GuardRegen = { Icon = "再", Name = "Guard Recovery", Percent = true },
	ParryWindow = { Icon = "眼", Name = "Parry Window" },
	BlockTaken = { Icon = "壁", Name = "Damage Through Guard", Percent = true, Less = true },
	StaminaRegen = { Icon = "呼", Name = "Stamina Recovery", Percent = true },
	DashCost = { Icon = "駆", Name = "Dash Cost", Percent = true, Less = true },
	RajadaHits = { Icon = "連", Name = "Barrage Punches" },
	ChargeTime = { Icon = "溜", Name = "Charge Time", Percent = true, Less = true },
	DoubleJump = { Icon = "跳", Name = "Double Jump" },
	-- Só dos clãs (ClanData)
	DodgeChance = { Icon = "避", Name = "Dodge", Percent = true },
	XPBonus = { Icon = "学", Name = "XP Bonus", Percent = true },
	GoldBonus = { Icon = "金", Name = "Gold Bonus", Percent = true },
}
-- Ordem das pílulas
SkillTreeData.EffectOrder = {
	"Forca", "HP", "Defesa", "Velocidade", "Energia", "Damage_Punhos", "Damage_Katana", "GuardDamage", "Knockback", "Regen",
	"GuardMax", "GuardRegen", "ParryWindow", "BlockTaken", "StaminaRegen", "DashCost", "RajadaHits", "ChargeTime",
	"DoubleJump", "DodgeChance", "XPBonus", "GoldBonus",
}

-- Texto completo de um efeito (o mesmo da tela da árvore), para os balões de dica
function SkillTreeData.EffectText(key, value)
	local describe = EFFECT_TEXT[key]
	return if describe then describe(value) else SkillTreeData.ShortValue(key, value)
end

-- Valor curto de um efeito: "+13", "+10%", "-25%", "1%/s", "+0.05s", "ON"
function SkillTreeData.ShortValue(key, value)
	local info = SkillTreeData.EffectInfo[key] or {}
	if type(value) == "boolean" then
		return if value then "ON" else "OFF"
	elseif key == "Regen" then
		return `{math.floor(value * 1000 + 0.5) / 10}%/s`
	elseif key == "ParryWindow" then
		return `+{math.floor(value * 100 + 0.5) / 100}s`
	elseif info.Percent then
		return `{if info.Less then "-" else "+"}{math.floor(value * 100 + 0.5)}%`
	end
	return `+{math.floor(value + 0.5)}`
end

return SkillTreeData
