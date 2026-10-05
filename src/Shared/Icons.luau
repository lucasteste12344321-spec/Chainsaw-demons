-- Ícones em imagem (feitos pelo ChatGPT a pedido do usuário, 2026-10-05; IDs de imagem do Roblox). Onde tem ícone, a
-- interface mostra a imagem; onde não tem, continua o kanji/símbolo de antes. Só cliente.
local Icons = {}

Icons.Ids = {
	settings = 131782499584409,
	health = 79777672477713,
	tablet = 118314468171491,
	milestones = 121499693193232, -- troféu
	defense = 126223943818626, -- escudo
	quests = 81611039448252,
	inventory = 127696801220566, -- mochila
	stamina = 101974520951475,
	fishing = 118770928772932,
	mainMenu = 130768758261577,
	gold = 112588241287275,
	speed = 85453324163028, -- pé
	passes = 101471790737378,
	lifespan = 112474696649805, -- ampulheta
	group = 113920919954057,
	spin = 124742128393777, -- roleta
	fists = 73064482272311,
	xp = 99150740470234,
	parry = 96112874061123, -- olho
	dash = 119908940187013, -- pé correndo
	knockback = 107235213271278, -- seta
	guardBreak = 130209722044820,
	staminaRegen = 102443554191561, -- fumaça recarregando
	regen = 115382951061101, -- + de regeneração
	guard = 80923888386725, -- escudo grande (guarda)
	guardRegen = 75053545325504,
	wall = 79724601418936, -- tijolos
	crown = 101339961586863, -- coroa (chefes)
	skillTree = 129056943300683, -- árvore com nós
}

-- Efeito (chaves do SkillTreeData.EffectInfo) -> ícone
Icons.EffectIcons = {
	HP = "health",
	Forca = "fists",
	Defesa = "defense",
	Velocidade = "speed",
	Energia = "stamina",
	Damage_Punhos = "fists",
	GuardDamage = "guardBreak",
	Knockback = "knockback",
	Regen = "regen",
	GuardMax = "guard",
	GuardRegen = "guardRegen",
	ParryWindow = "parry",
	BlockTaken = "wall",
	StaminaRegen = "staminaRegen",
	DashCost = "dash",
	XPBonus = "xp",
	GoldBonus = "gold",
}

function Icons.Get(name)
	local id = name and Icons.Ids[name]
	return if id then "rbxassetid://" .. id else nil
end

function Icons.Effect(key)
	return Icons.Get(Icons.EffectIcons[key])
end

-- Coloca a imagem dentro de um botão/texto (ImageLabel "Icon", centralizado) e esconde o texto. Devolve o ImageLabel,
-- ou nil se o ícone não existe (aí o texto continua). scale: fração do tamanho do pai (padrão 0.62).
function Icons.Apply(guiObject, name, scale)
	local image = Icons.Get(name)
	local existing = guiObject:FindFirstChild("Icon")
	if not image then
		if existing then existing:Destroy() end
		return nil
	end
	local label = existing or Instance.new("ImageLabel")
	label.Name = "Icon"
	label.BackgroundTransparency = 1
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Position = UDim2.fromScale(0.5, 0.5)
	label.Size = UDim2.fromScale(scale or 0.62, scale or 0.62)
	label.ScaleType = Enum.ScaleType.Fit
	label.Image = image
	label.ZIndex = guiObject.ZIndex + 1
	label.Parent = guiObject
	if guiObject:IsA("TextLabel") or guiObject:IsA("TextButton") then
		guiObject.TextTransparency = 1
	end
	return label
end

-- Tira a imagem e mostra o texto de novo
function Icons.Clear(guiObject)
	local existing = guiObject:FindFirstChild("Icon")
	if existing then existing:Destroy() end
	if guiObject:IsA("TextLabel") or guiObject:IsA("TextButton") then
		guiObject.TextTransparency = 0
	end
end

return Icons
