
local ContractData = require(script.Parent:WaitForChild("ContractData"))

local PathData = {}

PathData.MinLevel = 25 -- level mínimo para escolher um caminho
PathData.RequiredQuest = "Encruzilhada" -- missão que precisa estar completa antes de escolher
PathData.ResetCost = 25000 -- Gold para renunciar ao caminho (volta a Humano comum)
PathData.MaxContracts = 1 -- Caçador: um contrato só, com os dois poderes (V e B) na forma atual (ContractData)

-- Tempo de vida: recurso dos Caçadores, gasto ao usar poderes de contrato
PathData.MaxLifespan = 100
PathData.LifespanRegen = 0.25 -- por segundo

-- Ids de caminho salvos no perfil: "None" (padrão), "Hunter", "Fiend"
PathData.Paths = {
	None = {
		DisplayName = "Humano",
		Glyph = "人", -- kanji das telas (estilo escuro)
		Team = "Humans",
		Color = Color3.fromRGB(210, 210, 215),
		Description = "Uma pessoa comum. A partir do level 25 pode escolher um caminho.",
	},
	Hunter = {
		DisplayName = "Caçador",
		Glyph = "狩",
		Team = "Humans",
		NPC = "Veterano",
		Color = Color3.fromRGB(70, 150, 255),
		Description = "Humanos que fazem contratos com demônios. Ganham poderes em troca de sacrifícios: "
			.. "parte da vida máxima enquanto o contrato existir e tempo de vida a cada uso.",
	},
	Fiend = {
		DisplayName = "Infernal",
		Glyph = "魔",
		Team = "Fiends",
		NPC = "Anciao",
		Color = Color3.fromRGB(220, 38, 38),
		Description = "Demônios que possuem o cadáver de um humano para sobreviver. Perderam parte do poder "
			.. "original, mas mantêm habilidades sobrenaturais. Os poderes custam o próprio sangue (vida).",
	},
}

-- Times (o servidor cria os que faltarem)
PathData.Teams = {
	Humans = { DisplayName = "Humanos", BrickColor = BrickColor.new("Bright blue") },
	Fiends = { DisplayName = "Infernais", BrickColor = BrickColor.new("Really red") },
}

--[[
Habilidade: {
	Id, Name, Icon (emoji, reserva), Glyph (kanji das telas), Kind, Cooldown (s), Damage, Stun? (s),
	LifespanCost? (Caçador: tempo de vida gasto), HealthCost? (Infernal: fração da vida MÁXIMA gasta),
	+ campos do Kind:
	"Cone"       golpe em cone à frente: Range, Angle (graus)
	"Area"       explosão centrada Range studs à frente: Range, Radius
	"Dash"       avança Range studs e acerta quem estiver no caminho: Range, Radius
	"Projectile" projétil reto: Range, Speed (studs/s), Radius
	"Mark"       marca o primeiro alvo à frente (Range); depois de Delay segundos a marca explode com Damage
	"Buff"       efeito em si mesmo por Duration segundos (VisaoFutura: esquiva de todo dano)
}
]]

PathData.Contracts = {
	Raposa = {
		DisplayName = "Demônio Raposa",
		Icon = "🦊",
		Glyph = "狐",
		Description = "A cabeça de uma raposa gigante sai de um portal: morde o ponto mirado (V) ou avança em linha reta (B). Inimigos com pouca vida são devorados. Com maestria, funde com os Punhos.",
		HPCost = 0, -- fração da vida máxima perdida enquanto tiver o contrato
		Unlock = "Path", -- "Path": pode ser o primeiro contrato | "Quest": liberado por missão
		-- Poderes, passivos e formas (V1, V2 com Punhos, Ultimate) no ContractData; Skill = o V da forma V1
		Skill = ContractData.GetSkill("Raposa", "V1", "Z"),
	},
	Fantasma = {
		DisplayName = "Demônio Fantasma",
		Icon = "👻",
		Glyph = "霊",
		Description = "Mãos invisíveis agarram e prendem todos em volta do alvo.",
		HPCost = 0.1,
		Unlock = "Path",
		Skill = {
			Id = "MaosFantasma",
			Name = "Mãos Fantasmas",
			Icon = "👻",
			Glyph = "霊",
			Kind = "Area",
			Cooldown = 14,
			Damage = 40,
			Range = 12,
			Radius = 10,
			Stun = 3,
			LifespanCost = 12,
		},
	},
	Futuro = {
		DisplayName = "Demônio do Futuro",
		Icon = "👁️",
		Glyph = "眼",
		Description = "Vê alguns segundos à frente. Passivo: 10% de chance de esquivar de qualquer golpe.",
		HPCost = 0.1,
		Unlock = "Quest",
		Passive = { DodgeChance = 0.1 },
		Skill = {
			Id = "VisaoFutura",
			Name = "Visão do Futuro",
			Icon = "👁️",
			Glyph = "眼",
			Kind = "Buff",
			Cooldown = 25,
			Damage = 0,
			Duration = 3,
			LifespanCost = 15,
		},
	},
	Maldicao = {
		DisplayName = "Demônio da Maldição",
		Icon = "📌",
		Glyph = "呪",
		Description = "Crava um prego no alvo. Depois de alguns segundos, a maldição explode com dano enorme.",
		HPCost = 0.2,
		Unlock = "Quest",
		Skill = {
			Id = "PregoMaldito",
			Name = "Prego Maldito",
			Icon = "📌",
			Glyph = "釘",
			Kind = "Mark",
			Cooldown = 30,
			Damage = 220,
			Range = 12,
			Delay = 3,
			Stun = 2,
			LifespanCost = 25,
		},
	},
}

-- Contratos desativados no ContractData (Enabled = false) somem da escolha e das missões de pacto
for contractId, contract in PathData.Contracts do
	contract.Enabled = ContractData.IsEnabled(contractId)
end

-- Passivo de todo Infernal: corpo de demônio (mais vida). A fraqueza: não pode fazer contratos
-- e os poderes custam a própria vida.
PathData.FiendPassive = { MaxHPBonus = 0.15 }

PathData.FiendTypes = {
	Sangue = {
		DisplayName = "Infernal do Sangue",
		Icon = "🩸",
		Glyph = "血",
		Description = "Molda o próprio sangue em armas. Recupera vida ao causar dano.",
		Passive = { LifeSteal = 0.1 }, -- fração do dano causado que vira vida
		Skills = {
			Z = {
				Id = "LancaSangue",
				Name = "Lança de Sangue",
				Icon = "🩸",
				Glyph = "血",
				Kind = "Projectile",
				Cooldown = 8,
				Damage = 55,
				Range = 60,
				Speed = 90,
				Radius = 3,
				Stun = 0.5,
				HealthCost = 0.05,
			},
			X = {
				Id = "MarteloSangue",
				Name = "Martelo de Sangue",
				Icon = "🔨",
				Glyph = "槌",
				Kind = "Area",
				Cooldown = 16,
				Damage = 95,
				Range = 6,
				Radius = 12,
				Stun = 1.5,
				HealthCost = 0.1,
			},
		},
	},
	Tubarao = {
		Enabled = false, -- Desativado enquanto o Infernal do Sangue recebe o kit visual.
		DisplayName = "Infernal Tubarão",
		Icon = "🦈",
		Glyph = "鮫",
		Description = "Nada pelo chão como se fosse água. Mais rápido que os outros Infernais.",
		Passive = { SpeedBonus = 4 }, -- somado à velocidade de andar
		Skills = {
			Z = {
				Id = "MergulhoTubarao",
				Name = "Mergulho",
				Icon = "🌊",
				Glyph = "波",
				Kind = "Dash",
				Cooldown = 7,
				Damage = 45,
				Range = 30,
				Radius = 6,
				Stun = 0.5,
				HealthCost = 0.03,
			},
			X = {
				Id = "MordidaTubarao",
				Name = "Mordida Voraz",
				Icon = "🦈",
				Glyph = "鮫",
				Kind = "Cone",
				Cooldown = 15,
				Damage = 110,
				Range = 10,
				Angle = 60,
				Stun = 1.5,
				HealthCost = 0.08,
			},
		},
	},
}

-- Lê o caminho de um jogador pelos atributos que o servidor replica (funciona no cliente e no servidor).
-- Devolve path ("None"/"Hunter"/"Fiend"), contracts (lista de ids), fiendType ("" se não tiver) e a forma do contrato
-- ("V1", "V2" ou "Ultimate"; atributo ContractForm). Passives(PathData.FromPlayer(p)) recebe os quatro.
function PathData.FromPlayer(player)
	local contracts = {}
	local raw = player:GetAttribute("Contracts")
	if type(raw) == "string" and raw ~= "" then
		contracts = string.split(raw, ",")
	end
	local path = player:GetAttribute("Path")
	local fiendType = player:GetAttribute("FiendType")
	local form = player:GetAttribute("ContractForm")
	return if type(path) == "string" and PathData.Paths[path] then path else "None",
		contracts,
		if type(fiendType) == "string" then fiendType else "",
		if ContractData.IsForm(form) then form else "V1"
end

-- Tecla de cada slot de poder: por dentro os slots continuam "Z" e "X", mas as teclas são V e B (as skills dos estilos
-- ficaram em Z/X/C)
PathData.SlotKeys = { Z = "V", X = "B", HZ = "H", HX = "J" } -- HZ/HX: só no modo híbrido de admin (PlayerSkill)
function PathData.KeyLabel(slot)
	return PathData.SlotKeys[slot] or tostring(slot)
end

-- Habilidade do slot ("Z" ou "X"), ou nil. form: forma do contrato do Caçador (padrão "V1"; ContractData).
-- Caçador: os dois slots são do único contrato (ContractData); contrato sem formas lá usa o Skill daqui no Z.
function PathData.GetSkill(path, contracts, fiendType, slot, form)
	if path == "Hunter" then
		local contractId = contracts[1]
		if ContractData.HasForms(contractId) then
			return ContractData.GetSkill(contractId, form or "V1", slot)
		end
		local contract = contractId and PathData.Contracts[contractId]
		return if contract and slot == "Z" then contract.Skill else nil
	elseif path == "Fiend" then
		local fiend = PathData.FiendTypes[fiendType]
		return fiend and fiend.Skills[slot]
	end
	return nil
end

-- Habilidade do slot para este jogador, pelos atributos que o servidor replica (vale no cliente e no servidor).
-- Modo híbrido (só admin, comando /hibrido; atributos Hybrid, HybridContract, HybridForm e HybridFiend): V/B ("Z"/"X")
-- são do contrato HybridContract e H/J ("HZ"/"HX") do tipo de Infernal HybridFiend, seja qual for o caminho de verdade.
-- Fora dele, H/J não têm nada e V/B seguem o caminho.
function PathData.PlayerSkill(player, slot)
	if player:GetAttribute("Hybrid") == true then
		if slot == "Z" or slot == "X" then
			local contract = player:GetAttribute("HybridContract")
			local form = player:GetAttribute("HybridForm")
			return PathData.GetSkill("Hunter", { contract }, "", slot, if ContractData.IsForm(form) then form else "V1")
		elseif slot == "HZ" or slot == "HX" then
			local fiendType = player:GetAttribute("HybridFiend")
			local fiend = type(fiendType) == "string" and PathData.FiendTypes[fiendType]
			return fiend and fiend.Skills and fiend.Skills[string.sub(slot, 2)] or nil
		end
	end
	if slot == "HZ" or slot == "HX" then return nil end
	local path, contracts, fiendType, form = PathData.FromPlayer(player)
	return PathData.GetSkill(path, contracts, fiendType, slot, form)
end

-- Multiplicador da vida máxima (Stats.HP) conforme o caminho
function PathData.HPMultiplier(path, contracts, fiendType)
	local multiplier = 1
	if path == "Hunter" then
		for _, contractId in contracts do
			local contract = PathData.Contracts[contractId]
			if contract then
				multiplier -= contract.HPCost
			end
		end
	elseif path == "Fiend" and PathData.FiendTypes[fiendType] then
		multiplier += PathData.FiendPassive.MaxHPBonus
	end
	return math.max(0.3, multiplier)
end

-- Passivos somados (DodgeChance, LifeSteal, SpeedBonus) do caminho. form: forma do contrato (ContractData)
function PathData.Passives(path, contracts, fiendType, form)
	local result = { DodgeChance = 0, LifeSteal = 0, SpeedBonus = 0 }
	local function add(passive)
		for key, value in passive or {} do
			result[key] = (result[key] or 0) + value
		end
	end
	if path == "Hunter" then
		for _, contractId in contracts do
			if ContractData.HasForms(contractId) then
				add(ContractData.Passive(contractId, form or "V1"))
			else
				local contract = PathData.Contracts[contractId]
				add(contract and contract.Passive)
			end
		end
	elseif path == "Fiend" then
		local fiend = PathData.FiendTypes[fiendType]
		add(fiend and fiend.Passive)
	end
	return result
end

return PathData
