
local ItemData = {}

-- Onde cada item veste, na ordem das casas do inventário
ItemData.Slots = {
	{ Id = "Head", Name = "Head" },
	{ Id = "Hat", Name = "Hat" },
	{ Id = "Neck", Name = "Neck" },
	{ Id = "ShoulderLeft", Name = "Left Shoulder" },
	{ Id = "ShoulderRight", Name = "Right Shoulder" },
}

ItemData.Items = {
	OgreHorns = {
		Name = "Ogre Horns",
		Rarity = "Uncommon",
		Slot = "Hat",
		Effects = { Forca = 8, GuardDamage = 0.1 },
		Description = "Torn from the Goblin King. Every hit lands heavier.",
		Accessory = "ogre horns",
	},
	OgreShoulderRight = {
		Name = "Ogre Pauldron (right)",
		Rarity = "Rare",
		Slot = "ShoulderRight",
		Effects = { Defesa = 3, HP = 60 },
		Description = "Made to take a beating. Thick leather and old iron.",
		Accessory = "right ogre shoulder",
	},
	OgreShoulderLeft = {
		Name = "Ogre Pauldron (left)",
		Rarity = "Rare",
		Slot = "ShoulderLeft",
		Effects = { Defesa = 3, GuardMax = 0.1 },
		Description = "The guarding side: holds more hits before breaking.",
		Accessory = "left ogre shoulder",
	},
	OgreChain = {
		Name = "Ogre Chain",
		Rarity = "Epic",
		Slot = "Neck",
		Effects = { HP = 150, Regen = 0.005 },
		Description = "It bound the King to his throne. Heavy, but the body gets used to it.",
		Accessory = "Ogre chain",
	},
	OgreHead = {
		Name = "Ogre Head",
		Rarity = "Legendary",
		Slot = "Head",
		Effects = { HP = 200, Forca = 15, Defesa = 4 },
		Description = "The Goblin King's own head. Whoever wears it inherits a bit of his strength.",
		Accessory = "Ogro Head",
	},

	-- Drops do chefe global Denji / Lord Chainsaw. Source: o Accessory vem de dentro do modelo do chefe (o BossService
	-- copia para VFX.Items.<Id> ao iniciar, se ainda não existir lá); o Denji é do tamanho de jogador.
	-- Não cai mais (pedido do usuário, 2026-10-05): fica aqui só para quem já tinha continuar com ele
	DenjiHair = {
		Name = "Denji's Hair",
		Rarity = "Rare",
		Slot = "Hat",
		Effects = { Forca = 10, Velocidade = 2 },
		Description = "Messy on purpose. They say it makes anyone faster at running from debt.",
		Source = { Template = "Denji", Accessory = "MessyAnimeHairstyleAccessory" },
	},
	DenjiEyepatch = {
		Name = "Denji's Eyepatch",
		Rarity = "Epic",
		Slot = "Head",
		Effects = { Forca = 14, DodgeChance = 0.03 },
		Description = "Just one eye, but it sees the hit coming.",
		Source = { Template = "Denji", Accessory = "Accessory (Meshes/denji eyepatch (2)Accessory)" },
	},
	Pochita = {
		Name = "Pochita",
		Rarity = "Legendary",
		Slot = "ShoulderLeft",
		Effects = { HP = 250, Forca = 10, Regen = 0.008 },
		Description = "Denji's best friend. Stays by your side and never lets you fall.",
		Source = { Template = "Denji", Accessory = "SawBestFriend" },
	},
}

ItemData.RarityColors = {
	["Common"] = Color3.fromRGB(200, 200, 200),
	["Uncommon"] = Color3.fromRGB(110, 220, 110),
	["Rare"] = Color3.fromRGB(80, 160, 255),
	["Epic"] = Color3.fromRGB(190, 100, 255),
	["Legendary"] = Color3.fromRGB(255, 190, 40),
}

-- Ordem das raridades (da mais comum para a mais rara), para ordenar o inventário
ItemData.RarityOrder = { ["Common"] = 1, ["Uncommon"] = 2, ["Rare"] = 3, ["Epic"] = 4, ["Legendary"] = 5 }

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
