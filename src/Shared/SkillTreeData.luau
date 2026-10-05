
local SkillTreeData = {}

SkillTreeData.Version = 1

-- Distância entre dois nós do mesmo galho e o afastamento dos nós ao lado (em pixels, zoom 100%)
SkillTreeData.Step = 125
SkillTreeData.Fork = 90

-- Icon: kanji (a tela é preto e branco, estilo mangá; emoji sairia colorido)
-- Angle: direção do galho na tela (0 = direita, 90 = para baixo). Os estilos ficam lado a lado, à direita.
SkillTreeData.Branches = {
	Punhos = { Name = "PUNHOS", Icon = "拳", Angle = -30, Color = Color3.fromRGB(214, 22, 32) },
	Katana = { Name = "KATANA", Icon = "刀", Angle = 30, Color = Color3.fromRGB(225, 225, 235) },
	Forca = { Name = "FORÇA", Icon = "力", Angle = -90, Color = Color3.fromRGB(255, 122, 24) },
	Vitalidade = { Name = "VITALIDADE", Icon = "命", Angle = -150, Color = Color3.fromRGB(235, 70, 95) },
	Guarda = { Name = "GUARDA", Icon = "守", Angle = 150, Color = Color3.fromRGB(70, 150, 255) },
	Agilidade = { Name = "AGILIDADE", Icon = "速", Angle = 90, Color = Color3.fromRGB(255, 204, 36) },
}

-- Técnicas travadas pela árvore (os estilos apontam para elas em CombatStyles: Technique = "...")
SkillTreeData.Techniques = {
	PunhosRajada = { Name = "Rajada", Key = "Z", Style = "Punhos" },
	PunhosCarregado = { Name = "Soco carregado", Key = "X", Style = "Punhos" },
	PunhosUppercut = { Name = "Uppercut aéreo", Key = "Espaço + 4º soco", Style = "Punhos" },
	KatanaAvanco = { Name = "Avanço cortante", Key = "Z", Style = "Katana" },
	KatanaAgarrao = { Name = "Agarrão", Key = "X", Style = "Katana" },
	KatanaSaque = { Name = "Saque", Key = "C", Style = "Katana" },
	KatanaUppercut = { Name = "Corte ascendente", Key = "Espaço + 4º corte", Style = "Katana" },
}

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
	node("Root", nil, 0, 0, "Personagem", "鎖", 0, {}, {}, {
		Default = true,
		Flavor = "Todo caçador de demônios começa em algum lugar.",
	}),

	-- ===== Punhos (estilo): técnicas pedem maestria =====
	node("Punhos", "Punhos", 1, 0, "Estilo: Punhos", "拳", 0, { "Root" }, {}, {
		Default = true,
		Flavor = "Combo de 5 socos e guarda (F). Lute com os Punhos para subir a maestria e liberar as técnicas.",
	}),
	node("PunhosRajada", "Punhos", 2, 0, "Rajada", "連", 3, { "Punhos" }, { Technique = "PunhosRajada" }, {
		Mastery = { Style = "Punhos", Level = 6 },
		Flavor = "Uma sequência rápida de socos que prende o alvo na sua frente.",
	}),
	node("PunhosUppercut", "Punhos", 2, -1, "Uppercut aéreo", "昇", 2, { "Punhos" }, { Technique = "PunhosUppercut" }, {
		Mastery = { Style = "Punhos", Level = 3 },
		Flavor = "No ar, o 4º soco do combo lança o alvo para cima.",
	}),
	node("PunhosCarregado", "Punhos", 3, 0, "Soco carregado", "溜", 4, { "PunhosRajada" }, { Technique = "PunhosCarregado" }, {
		Mastery = { Style = "Punhos", Level = 12 },
		Flavor = "Segure para carregar e solte: quanto mais carregado, mais forte. Carga máxima quebra a guarda.",
	}),
	node("PunhosRajadaLonga", "Punhos", 3, 1, "Rajada longa", "乱", 4, { "PunhosRajada" }, { RajadaHits = 3 }, {
		Mastery = { Style = "Punhos", Level = 15 },
	}),
	node("PunhosTreinados", "Punhos", 3, -1, "Punhos treinados", "闘", 3, { "PunhosUppercut" }, { Damage_Punhos = 0.1 }, {
		Mastery = { Style = "Punhos", Level = 8 },
	}),
	node("PunhosCargaRapida", "Punhos", 4, 0, "Carga rápida", "瞬", 4, { "PunhosCarregado" }, { ChargeTime = 0.3 }, {
		Mastery = { Style = "Punhos", Level = 20 },
	}),
	node("PunhosMestre", "Punhos", 5, 0, "Mestre dos punhos", "王", 6, { "PunhosCargaRapida" }, { Damage_Punhos = 0.15 }, {
		Mastery = { Style = "Punhos", Level = 30 },
	}),

	-- ===== Katana (estilo ensinado pelo Mestre Espadachim, level 15): o 1º nó pede maestria 1, então só quem já tem
	-- a katana (e cortou com ela) chega nas técnicas =====
	node("Katana", "Katana", 1, 0, "Estilo: Katana", "刀", 0, { "Root" }, {}, {
		Mastery = { Style = "Katana", Level = 1 },
		Flavor = "Combo de 5 cortes e guarda (F). Aprenda com o Mestre Espadachim (level 15) e corte com ela para liberar.",
	}),
	node("KatanaAvanco", "Katana", 2, 0, "Avanço cortante", "閃", 2, { "Katana" }, { Technique = "KatanaAvanco" }, {
		Mastery = { Style = "Katana", Level = 3 },
		Flavor = "Avança em linha reta cortando todo mundo no caminho. Os cortes aparecem um instante depois.",
	}),
	node("KatanaUppercut", "Katana", 2, 1, "Corte ascendente", "昇", 2, { "Katana" }, { Technique = "KatanaUppercut" }, {
		Mastery = { Style = "Katana", Level = 5 },
		Flavor = "No ar, o 4º corte do combo lança o alvo para cima.",
	}),
	node("KatanaAgarrao", "Katana", 3, 0, "Agarrão", "掴", 3, { "KatanaAvanco" }, { Technique = "KatanaAgarrao" }, {
		Mastery = { Style = "Katana", Level = 8 },
		Flavor = "Agarra quem está na sua frente (atravessa a guarda), corta segurando e arremessa.",
	}),
	node("KatanaFio", "Katana", 3, 1, "Fio afiado", "鋭", 3, { "KatanaUppercut" }, { Damage_Katana = 0.1 }, {
		Mastery = { Style = "Katana", Level = 10 },
	}),
	node("KatanaSaque", "Katana", 4, 0, "Saque", "居", 4, { "KatanaAgarrao" }, { Technique = "KatanaSaque" }, {
		Mastery = { Style = "Katana", Level = 12 },
		Flavor = "Guarda a lâmina e saca num corte largo na sua frente. Quebra a guarda.",
	}),
	node("KatanaMestre", "Katana", 5, 0, "Mestre da lâmina", "剣", 6, { "KatanaSaque" }, { Damage_Katana = 0.15 }, {
		Mastery = { Style = "Katana", Level = 25 },
	}),

	-- ===== Força =====
	node("Forca1", "Forca", 1, 0, "Punho firme I", "力", 1, { "Root" }, { Forca = 13 }),
	node("Forca2", "Forca", 2, 0, "Punho firme II", "力", 2, { "Forca1" }, { Forca = 16 }),
	node("ForcaGuarda", "Forca", 2, 1, "Golpe pesado", "重", 3, { "Forca1" }, { GuardDamage = 0.25 }),
	node("Forca3", "Forca", 3, 0, "Punho firme III", "力", 3, { "Forca2" }, { Forca = 24 }),
	node("Forca4", "Forca", 4, 0, "Punho firme IV", "力", 3, { "Forca3" }, { Forca = 32 }),
	node("ForcaImpacto", "Forca", 4, -1, "Impacto", "衝", 3, { "Forca3" }, { Knockback = 0.3 }),
	node("Forca5", "Forca", 5, 0, "Punho firme V", "力", 4, { "Forca4" }, { Forca = 48 }),
	node("Forca6", "Forca", 6, 0, "Brutalidade", "血", 5, { "Forca5" }, { Forca = 64 }),
	node("Forca7", "Forca", 7, 0, "Demolidor", "鬼", 6, { "Forca6" }, { Forca = 96 }),

	-- ===== Vitalidade =====
	node("Vida1", "Vitalidade", 1, 0, "Vigor I", "命", 1, { "Root" }, { HP = 90 }),
	node("Vida2", "Vitalidade", 2, 0, "Vigor II", "命", 2, { "Vida1" }, { HP = 120 }),
	node("VidaRegen", "Vitalidade", 2, -1, "Regeneração", "癒", 3, { "Vida1" }, { Regen = 0.01 }, {
		Flavor = "Depois de 5 segundos sem levar dano.",
	}),
	node("Defesa1", "Vitalidade", 3, 0, "Couro grosso I", "盾", 3, { "Vida2" }, { Defesa = 5 }),
	node("Vida3", "Vitalidade", 4, 0, "Vigor III", "命", 3, { "Defesa1" }, { HP = 180 }),
	node("Defesa2", "Vitalidade", 5, 0, "Couro grosso II", "盾", 4, { "Vida3" }, { Defesa = 5 }),
	node("Vida4", "Vitalidade", 6, 0, "Vigor IV", "命", 4, { "Defesa2" }, { HP = 240 }),
	node("Defesa3", "Vitalidade", 7, 0, "Couro grosso III", "盾", 5, { "Vida4" }, { Defesa = 8 }),
	node("Vida5", "Vitalidade", 8, 0, "Vigor V", "命", 5, { "Defesa3" }, { HP = 330 }),
	node("VidaDemonio", "Vitalidade", 9, 0, "Pele de demônio", "魔", 6, { "Vida5" }, { HP = 450, Defesa = 7 }),

	-- ===== Agilidade =====
	node("Agil1", "Agilidade", 1, 0, "Pernas leves I", "速", 1, { "Root" }, { Velocidade = 1 }),
	node("Folego1", "Agilidade", 2, 0, "Fôlego I", "息", 2, { "Agil1" }, { Energia = 25 }),
	node("Agil2", "Agilidade", 3, 0, "Pernas leves II", "速", 2, { "Folego1" }, { Velocidade = 1 }),
	node("PuloDuplo", "Agilidade", 3, 1, "Pulo duplo", "跳", 4, { "Folego1" }, { DoubleJump = true }, {
		Flavor = "Aperte pular de novo no ar.",
	}),
	node("Folego2", "Agilidade", 4, 0, "Fôlego II", "息", 3, { "Agil2" }, { Energia = 25, StaminaRegen = 0.25 }),
	node("Agil3", "Agilidade", 5, 0, "Pernas leves III", "速", 3, { "Folego2" }, { Velocidade = 2 }),
	node("DashEconomico", "Agilidade", 5, -1, "Dash econômico", "駆", 3, { "Folego2" }, { DashCost = 0.25 }),
	node("Agil4", "Agilidade", 6, 0, "Pernas leves IV", "速", 4, { "Agil3" }, { Velocidade = 2 }),
	node("Folego3", "Agilidade", 7, 0, "Segundo fôlego", "息", 5, { "Agil4" }, { Energia = 50, StaminaRegen = 0.25 }),

	-- ===== Guarda =====
	node("Guarda1", "Guarda", 1, 0, "Guarda firme I", "守", 1, { "Root" }, { GuardMax = 0.2 }),
	node("GuardaRegen1", "Guarda", 2, 0, "Recuperação I", "再", 2, { "Guarda1" }, { GuardRegen = 0.3 }),
	node("Guarda2", "Guarda", 3, 0, "Guarda firme II", "守", 3, { "GuardaRegen1" }, { GuardMax = 0.2 }),
	node("Reflexo1", "Guarda", 3, 1, "Reflexo", "眼", 3, { "GuardaRegen1" }, { ParryWindow = 0.05 }),
	node("GuardaRegen2", "Guarda", 4, 0, "Recuperação II", "再", 3, { "Guarda2" }, { GuardRegen = 0.4 }),
	node("Muralha", "Guarda", 5, 0, "Muralha", "壁", 4, { "GuardaRegen2" }, { BlockTaken = 0.05 }),
	node("Guarda3", "Guarda", 6, 0, "Guarda firme III", "守", 4, { "Muralha" }, { GuardMax = 0.3 }),
	node("Reflexo2", "Guarda", 6, -1, "Reflexo II", "眼", 5, { "Muralha" }, { ParryWindow = 0.05 }),
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
		return "Já desbloqueado"
	end
	local connected = #entry.Requires == 0
	for _, required in entry.Requires do
		if unlocked[required] then
			connected = true
			break
		end
	end
	if not connected then
		return "Desbloqueie um nó ligado a este antes"
	end
	if entry.Mastery then
		local have = masteryLevels[entry.Mastery.Style] or 0
		if have < entry.Mastery.Level then
			return `Precisa de maestria {entry.Mastery.Level} em {entry.Mastery.Style} (você tem {have})`
		end
	end
	if points < entry.Cost then
		return `Precisa de {entry.Cost} ponto(s) (você tem {points})`
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
	HP = function(v) return `+{v} de vida máxima` end,
	Forca = function(v) return `+{v} de dano por golpe` end,
	Defesa = function(v) return `+{v}% de redução de dano` end,
	Velocidade = function(v) return `+{v} de velocidade` end,
	Energia = function(v) return `+{v} de fôlego (stamina do dash)` end,
	Regen = function(v) return `Regenera {percent(v)} da vida por segundo fora de combate` end,
	GuardDamage = function(v) return `+{percent(v)} de dano na guarda de quem bloqueia` end,
	Knockback = function(v) return `+{percent(v)} de empurrão nos golpes` end,
	StaminaRegen = function(v) return `+{percent(v)} de recuperação de fôlego` end,
	DashCost = function(v) return `Dash gasta {percent(v)} menos fôlego` end,
	GuardMax = function(v) return `+{percent(v)} de guarda máxima` end,
	GuardRegen = function(v) return `+{percent(v)} de recuperação da guarda` end,
	ParryWindow = function(v) return `+{v} s na janela do parry` end,
	BlockTaken = function(v) return `Passa {percent(v)} menos dano pela guarda` end,
	Damage_Punhos = function(v) return `+{percent(v)} de dano com os Punhos` end,
	Damage_Katana = function(v) return `+{percent(v)} de dano com a Katana` end,
	RajadaHits = function(v) return `+{v} socos na Rajada` end,
	ChargeTime = function(v) return `Soco carregado carrega {percent(v)} mais rápido` end,
	DoubleJump = function() return "Pulo duplo" end,
	DodgeChance = function(v) return `{percent(v)} de chance de desviar de um golpe` end,
	XPBonus = function(v) return `+{percent(v)} de XP ganho` end,
	GoldBonus = function(v) return `+{percent(v)} de Gold ganho` end,
}

function SkillTreeData.Describe(entry)
	local lines = {}
	for key, value in entry.Effects do
		if key == "Technique" then
			local technique = SkillTreeData.Techniques[value]
			if technique then
				table.insert(lines, 1, `Desbloqueia: {technique.Name} ({technique.Key})`)
			end
		elseif EFFECT_TEXT[key] then
			table.insert(lines, EFFECT_TEXT[key](value))
		end
	end
	return lines
end

-- Versão curta de cada efeito (pílulas de bônus da HUD e do inventário): ícone (kanji), nome e valor
SkillTreeData.EffectInfo = {
	Forca = { Icon = "力", Name = "Força" },
	HP = { Icon = "命", Name = "Vida" },
	Defesa = { Icon = "盾", Name = "Defesa" },
	Velocidade = { Icon = "速", Name = "Velocidade" },
	Energia = { Icon = "息", Name = "Fôlego" },
	Damage_Punhos = { Icon = "拳", Name = "Dano dos Punhos", Percent = true },
	Damage_Katana = { Icon = "刀", Name = "Dano da Katana", Percent = true },
	GuardDamage = { Icon = "重", Name = "Dano na guarda", Percent = true },
	Knockback = { Icon = "衝", Name = "Empurrão", Percent = true },
	Regen = { Icon = "癒", Name = "Regeneração" },
	GuardMax = { Icon = "守", Name = "Guarda máxima", Percent = true },
	GuardRegen = { Icon = "再", Name = "Recuperação da guarda", Percent = true },
	ParryWindow = { Icon = "眼", Name = "Janela do parry" },
	BlockTaken = { Icon = "壁", Name = "Dano pela guarda", Percent = true, Less = true },
	StaminaRegen = { Icon = "呼", Name = "Recuperação do fôlego", Percent = true },
	DashCost = { Icon = "駆", Name = "Custo do dash", Percent = true, Less = true },
	RajadaHits = { Icon = "連", Name = "Socos na Rajada" },
	ChargeTime = { Icon = "溜", Name = "Tempo de carga", Percent = true, Less = true },
	DoubleJump = { Icon = "跳", Name = "Pulo duplo" },
	-- Só dos clãs (ClanData)
	DodgeChance = { Icon = "避", Name = "Esquiva", Percent = true },
	XPBonus = { Icon = "学", Name = "Bônus de XP", Percent = true },
	GoldBonus = { Icon = "金", Name = "Bônus de Gold", Percent = true },
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
