
local ItemData = {}

-- Onde cada item veste, na ordem das casas do inventário
ItemData.Slots = {
	{ Id = "Head", Name = "Cabeça" },
	{ Id = "Hat", Name = "Chapéu" },
	{ Id = "Neck", Name = "Pescoço" },
	{ Id = "ShoulderLeft", Name = "Ombro esq." },
	{ Id = "ShoulderRight", Name = "Ombro dir." },
}

ItemData.Items = {
	OgreHorns = {
		Name = "Chifres de Ogro",
		Rarity = "Incomum",
		Slot = "Hat",
		Effects = { Forca = 8, GuardDamage = 0.1 },
		Description = "Arrancados do Rei Goblin. Cada golpe sai mais pesado.",
		Accessory = "ogre horns",
	},
	OgreShoulderRight = {
		Name = "Ombreira de Ogro (direita)",
		Rarity = "Raro",
		Slot = "ShoulderRight",
		Effects = { Defesa = 3, HP = 60 },
		Description = "Feita para aguentar pancada. Couro grosso e ferro velho.",
		Accessory = "right ogre shoulder",
	},
	OgreShoulderLeft = {
		Name = "Ombreira de Ogro (esquerda)",
		Rarity = "Raro",
		Slot = "ShoulderLeft",
		Effects = { Defesa = 3, GuardMax = 0.1 },
		Description = "O lado da guarda: segura mais golpes antes de quebrar.",
		Accessory = "left ogre shoulder",
	},
	OgreChain = {
		Name = "Corrente de Ogro",
		Rarity = "Épico",
		Slot = "Neck",
		Effects = { HP = 150, Regen = 0.005 },
		Description = "Prendia o Rei ao trono. Pesada, mas o corpo se acostuma.",
		Accessory = "Ogre chain",
	},
	OgreHead = {
		Name = "Cabeça de Ogro",
		Rarity = "Lendário",
		Slot = "Head",
		Effects = { HP = 200, Forca = 15, Defesa = 4 },
		Description = "A cabeça do próprio Rei Goblin. Quem veste herda um pouco da força dele.",
		Accessory = "Ogro Head",
	},
}

ItemData.RarityColors = {
	["Comum"] = Color3.fromRGB(200, 200, 200),
	["Incomum"] = Color3.fromRGB(110, 220, 110),
	["Raro"] = Color3.fromRGB(80, 160, 255),
	["Épico"] = Color3.fromRGB(190, 100, 255),
	["Lendário"] = Color3.fromRGB(255, 190, 40),
}

-- Ordem das raridades (da mais comum para a mais rara), para ordenar o inventário
ItemData.RarityOrder = { ["Comum"] = 1, ["Incomum"] = 2, ["Raro"] = 3, ["Épico"] = 4, ["Lendário"] = 5 }

local slotsById = {}
for index, slot in ItemData.Slots do
	slot.Order = index
	slotsById[slot.Id] = slot
end

function ItemData.Get(id)
	return ItemData.Items[id]
end

function ItemData.GetSlot(slotId)
	return slotsById[slotId]
end

-- Nome do Accessory em ReplicatedStorage.VFX.Items
function ItemData.ModelName(id)
	local item = ItemData.Items[id]
	return if item and type(item.Model) == "string" then item.Model else id
end

-- Modelo do item (o Accessory no tamanho de jogador) ou nil
function ItemData.FindModel(id)
	local vfx = game:GetService("ReplicatedStorage"):FindFirstChild("VFX")
	local folder = vfx and vfx:FindFirstChild("Items")
	return folder and folder:FindFirstChild(ItemData.ModelName(id))
end

-- Soma dos efeitos dos itens equipados (equipped = { [Slot] = Id })
function ItemData.Compute(equipped)
	local effects = {}
	for _, id in equipped do
		local item = ItemData.Items[id]
		for key, value in item and item.Effects or {} do
			if type(value) == "boolean" then
				effects[key] = effects[key] or value
			else
				effects[key] = (effects[key] or 0) + value
			end
		end
	end
	return effects
end

return ItemData
