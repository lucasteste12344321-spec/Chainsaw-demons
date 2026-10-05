
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AppearanceData = {}

AppearanceData.Skins = {
	{ Id = "Porcelana", Name = "Porcelain", Color = Color3.fromRGB(255, 232, 214) },
	{ Id = "Clara", Name = "Fair", Color = Color3.fromRGB(245, 215, 190) },
	{ Id = "Pessego", Name = "Peach", Color = Color3.fromRGB(234, 190, 160) },
	{ Id = "Bronzeada", Name = "Tan", Color = Color3.fromRGB(214, 162, 120) },
	{ Id = "Morena", Name = "Brown", Color = Color3.fromRGB(180, 124, 86) },
	{ Id = "Parda", Name = "Olive", Color = Color3.fromRGB(150, 100, 66) },
	{ Id = "Escura", Name = "Dark", Color = Color3.fromRGB(110, 70, 45) },
	{ Id = "Retinta", Name = "Deep", Color = Color3.fromRGB(76, 48, 32) },
	{ Id = "Palida", Name = "Pale", Color = Color3.fromRGB(226, 226, 216) },
	{ Id = "Cadaver", Name = "Corpse", Color = Color3.fromRGB(168, 176, 166) },
}

-- Rostos (decal 256 x 256, fundo transparente)
AppearanceData.Faces = {
	{ Id = "Neutro", Name = "Neutral", Texture = 79917768762408 },
	{ Id = "Serio", Name = "Serious", Texture = 125778094117709 },
	{ Id = "Tubarao", Name = "Shark", Texture = 95323890365175 },
	{ Id = "Cansado", Name = "Tired", Texture = 131581295200183 },
	{ Id = "Frio", Name = "Cold", Texture = 102012558716048 },
	{ Id = "Bravo", Name = "Angry", Texture = 77845594496717 },
	{ Id = "Timido", Name = "Shy", Texture = 86582514630412 },
	{ Id = "Confiante", Name = "Confident", Texture = 72243430214847 },
}

-- Cabelos: Model = nome do Accessory em ReplicatedStorage.VFX.Hair (nil = careca)
AppearanceData.Hairs = {
	{ Id = "Careca", Name = "Bald" },
	{ Id = "Coque", Name = "Bun", Model = "Anime1" },
	{ Id = "Rebelde", Name = "Rebel", Model = "Anime2" },
	{ Id = "Mechas", Name = "Locks", Model = "Anime3" },
	{ Id = "FranjaLonga", Name = "Long Bangs", Model = "Anime4" },
	{ Id = "Topete", Name = "Quiff", Model = "Anime5" },
	{ Id = "RaboLateral", Name = "Side Tail", Model = "Anime6" }, -- o Id ficou do nome antigo (já está salvo em perfis)
	{ Id = "Arrepiado", Name = "Spiky Up", Model = "Anime7" },
	{ Id = "Chanel", Name = "Bob", Model = "Anime8" },
	{ Id = "Espetado", Name = "Spiky", Model = "Espetado" },
	{ Id = "Classico", Name = "Classic", Model = "Classico" },
	{ Id = "Repicado", Name = "Layered", Model = "Repicado" },
	{ Id = "FranjaLado", Name = "Side Bangs", Model = "FranjaLado" },
	{ Id = "Ondulado", Name = "Wavy", Model = "Ondulado" },
	{ Id = "RaboCavalo", Name = "Ponytail", Model = "RaboCavalo" },
	{ Id = "MariaChiquinha", Name = "Pigtails", Model = "MariaChiquinha" },
	{ Id = "Chiquinhas", Name = "Twin Buns", Model = "Chiquinhas" },
	{ Id = "LongoLaco", Name = "Long with Bow", Model = "LongoLaco" },
	{ Id = "Tiara", Name = "Long with Headband", Model = "Tiara" },
}

AppearanceData.HairColors = {
	{ Id = "Preto", Name = "Black", Color = Color3.fromRGB(30, 28, 32) },
	{ Id = "CastanhoEscuro", Name = "Dark Brown", Color = Color3.fromRGB(70, 46, 34) },
	{ Id = "Castanho", Name = "Brown", Color = Color3.fromRGB(120, 80, 52) },
	{ Id = "Loiro", Name = "Blonde", Color = Color3.fromRGB(222, 186, 108) },
	{ Id = "LoiroClaro", Name = "Light Blonde", Color = Color3.fromRGB(240, 214, 160) },
	{ Id = "Ruivo", Name = "Ginger", Color = Color3.fromRGB(176, 64, 36) },
	{ Id = "Vermelho", Name = "Red", Color = Color3.fromRGB(186, 28, 38) },
	{ Id = "Rosa", Name = "Pink", Color = Color3.fromRGB(232, 124, 160) },
	{ Id = "Roxo", Name = "Purple", Color = Color3.fromRGB(132, 86, 192) },
	{ Id = "Azul", Name = "Blue", Color = Color3.fromRGB(62, 102, 204) },
	{ Id = "Marinho", Name = "Navy", Color = Color3.fromRGB(40, 50, 92) },
	{ Id = "Verde", Name = "Green", Color = Color3.fromRGB(56, 130, 90) },
	{ Id = "Branco", Name = "White", Color = Color3.fromRGB(230, 230, 234) },
	{ Id = "Cinza", Name = "Gray", Color = Color3.fromRGB(130, 130, 138) },
}

-- Roupas (modelo clássico 585 x 559). Color = cor principal, só para o botão da tela.
AppearanceData.Shirts = {
	{ Id = "Terno", Name = "Suit", Template = 80405351703248, Color = Color3.fromRGB(24, 24, 28) },
	{ Id = "Social", Name = "Social", Template = 112698431367591, Color = Color3.fromRGB(236, 236, 240) },
	{ Id = "Moletom", Name = "Hoodie", Template = 98117803815548, Color = Color3.fromRGB(70, 72, 80) },
	{ Id = "Gakuran", Name = "Gakuran", Template = 99299578448801, Color = Color3.fromRGB(20, 22, 34) },
	{ Id = "Marinheiro", Name = "Sailor", Template = 93413778325867, Color = Color3.fromRGB(230, 232, 240) },
	{ Id = "Couro", Name = "Leather Jacket", Template = 103738061419711, Color = Color3.fromRGB(56, 32, 26) },
	{ Id = "Camiseta", Name = "T-Shirt", Template = 121783583694880, Color = Color3.fromRGB(28, 28, 30) },
	{ Id = "Regata", Name = "Tank Top", Template = 91591874733230, Color = Color3.fromRGB(240, 240, 240) },
}

AppearanceData.Pants = {
	{ Id = "Social", Name = "Social", Template = 127695061227303, Color = Color3.fromRGB(24, 24, 28) },
	{ Id = "Jeans", Name = "Jeans", Template = 85413271344844, Color = Color3.fromRGB(52, 78, 128) },
	{ Id = "Cargo", Name = "Cargo", Template = 94924169500616, Color = Color3.fromRGB(92, 98, 70) },
	{ Id = "Saia", Name = "Skirt", Template = 124721978903346, Color = Color3.fromRGB(40, 44, 70) },
	{ Id = "Short", Name = "Shorts", Template = 124339236236608, Color = Color3.fromRGB(60, 60, 66) },
	{ Id = "Moletom", Name = "Hoodie", Template = 130562915815561, Color = Color3.fromRGB(70, 72, 80) },
}

-- Campo da aparência -> lista de opções
AppearanceData.Fields = {
	Skin = AppearanceData.Skins,
	Face = AppearanceData.Faces,
	Hair = AppearanceData.Hairs,
	HairColor = AppearanceData.HairColors,
	Shirt = AppearanceData.Shirts,
	Pants = AppearanceData.Pants,
}

-- Visual de quem ainda não criou o personagem: caçador de terno (Segurança Pública)
AppearanceData.DefaultAppearance = {
	Skin = "Clara",
	Face = "Neutro",
	Hair = "Coque",
	HairColor = "Preto",
	Shirt = "Terno",
	Pants = "Social",
}

AppearanceData.HairFolderName = "Hair" -- ReplicatedStorage.VFX.Hair
AppearanceData.HairAttribute = "AppearanceHair" -- no Accessory do cabelo vestido: o Id do cabelo
AppearanceData.PhysicsTag = "SmartBone"
AppearanceData.ColliderTag = "SmartCollider"

-- Física do cabelo (SmartBone). Ele lê esses atributos da Handle na hora que a tag entra; um atributo já posto no modelo
-- (VFX.Hair) vale mais. O SmartBone simula em passos fixos sem suavizar entre eles: com menos passos que o FPS o cabelo
-- "pula". Os padrões dele (60 passos/s, caindo a partir de 15 studs da câmera e parando em 45) deixavam o cabelo travado.
AppearanceData.PhysicsSettings = {
	UpdateRate = 240, -- passos por segundo (acima do FPS: todo frame atualiza)
	ThrottleDistance = 45, -- até essa distância da câmera roda na taxa cheia
	ActivationDistance = 130, -- depois disso para
	Stiffness = 0.3, -- volta para a forma do penteado (o padrão 0,2 deixava as mechas moles demais)
	Damping = 0.12,
	-- Sem vento: o SmartBone segue o workspace.GlobalWind, que no place aponta para cima (0, 13, 0) e deixava as mechas
	-- em pé. MatchWorkspaceWind = false não funciona por atributo (o SmartBone faz "atributo or padrão" e o false vira true).
	WindInfluence = 0,
}
-- Partes do corpo que empurram o cabelo (o comprido não entra nas costas). Cada personagem tem a sua chave
-- (ColliderKey), para o cabelo de um não bater no corpo de outro.
local COLLIDER_PARTS = { "Torso" }

local NEON_DARKEN = 0.38 -- Neon aparece mais claro que a cor: os cabelos de anime usam a cor escurecida
local BODY_PARTS = { "Head", "Torso", "Left Arm", "Right Arm", "Left Leg", "Right Leg" }
local BODY_COLOR_PROPERTIES = { "HeadColor3", "TorsoColor3", "LeftArmColor3", "RightArmColor3", "LeftLegColor3", "RightLegColor3" }

local byId = {}
for field, list in AppearanceData.Fields do
	byId[field] = {}
	for index, entry in list do
		entry.Order = index
		byId[field][entry.Id] = entry
	end
end

-- Opção de um campo ("Hair", "Coque") ou nil
function AppearanceData.Get(field, id)
	local lookup = byId[field]
	return lookup and type(id) == "string" and lookup[id] or nil
end

-- Cópia da aparência padrão
function AppearanceData.Default()
	return table.clone(AppearanceData.DefaultAppearance)
end

-- Aparência válida a partir de qualquer valor (o que vem do cliente ou do DataStore): campo errado vira o padrão
function AppearanceData.Sanitize(value)
	local result = AppearanceData.Default()
	if type(value) == "table" then
		for field in AppearanceData.Fields do
			if AppearanceData.Get(field, value[field]) then
				result[field] = value[field]
			end
		end
	end
	return result
end

-- Aparência sorteada (botão ALEATÓRIO)
function AppearanceData.Random(rng)
	rng = rng or Random.new()
	local result = {}
	for field, list in AppearanceData.Fields do
		result[field] = list[rng:NextInteger(1, #list)].Id
	end
	return result
end

-- Accessory do cabelo em ReplicatedStorage.VFX.Hair (nil para careca ou se o modelo não existir)
function AppearanceData.FindHair(hairId)
	local entry = AppearanceData.Get("Hair", hairId)
	if not entry or not entry.Model then return nil end
	local vfx = ReplicatedStorage:FindFirstChild("VFX")
	local folder = vfx and vfx:FindFirstChild(AppearanceData.HairFolderName)
	local model = folder and folder:FindFirstChild(entry.Model)
	return if model and model:IsA("Accessory") then model else nil
end

-- O cabelo tem física (ossos com raízes para o SmartBone)?
function AppearanceData.HasPhysics(hairId)
	local model = AppearanceData.FindHair(hairId)
	local handle = model and model:FindFirstChild("Handle")
	return handle ~= nil and handle:GetAttribute("Roots") ~= nil
end

-- Cor que a Handle recebe (os de Neon escurecem para ficar com a mesma cara dos outros)
function AppearanceData.HairPaint(handle, color)
	return if handle.Material == Enum.Material.Neon then color:Lerp(Color3.new(0, 0, 0), NEON_DARKEN) else color
end

local function templateUri(id)
	return "rbxassetid://" .. tostring(id)
end

local function setClothing(character, className, property, template)
	local clothing
	for _, child in character:GetChildren() do
		if child:IsA(className) then
			if clothing then
				child:Destroy() -- só uma de cada
			else
				clothing = child
			end
		end
	end
	if not clothing then
		clothing = Instance.new(className)
		clothing.Name = className
	end
	clothing[property] = templateUri(template)
	clothing.Parent = character
end

-- Prende o acessório no attachment de mesmo nome de uma parte do corpo (como o Humanoid:AddAccessory, mas funciona
-- também na cópia local da prévia, que fica numa WorldModel)
local function weldAccessory(character, accessory)
	local handle = accessory:FindFirstChild("Handle")
	if not handle then return end
	for _, attachment in handle:GetChildren() do
		if not attachment:IsA("Attachment") then continue end
		for _, part in character:GetChildren() do
			local target = part:IsA("BasePart") and part:FindFirstChild(attachment.Name)
			if target and target:IsA("Attachment") then
				handle.CFrame = part.CFrame * target.CFrame * attachment.CFrame:Inverse()
				local weld = Instance.new("Weld")
				weld.Name = "AccessoryWeld"
				weld.Part0 = part
				weld.Part1 = handle
				weld.C0 = target.CFrame
				weld.C1 = attachment.CFrame
				weld.Parent = handle
				return
			end
		end
	end
end

-- Veste a aparência num personagem R6 (o de verdade ou a cópia da prévia). Os itens equipados (atributo EquippedItem)
-- e outros acessórios ficam; só o cabelo anterior sai.
-- options.Physics = true liga a física do cabelo (tag do SmartBone): só no personagem de verdade, nunca na prévia.
function AppearanceData.Apply(character, appearance, options)
	appearance = AppearanceData.Sanitize(appearance)
	options = options or {}

	-- Pele: BodyColors (vale para o personagem) e a cor direto nas partes (vale também na prévia)
	local skin = AppearanceData.Get("Skin", appearance.Skin).Color
	local bodyColors = character:FindFirstChildOfClass("BodyColors")
	if not bodyColors then
		bodyColors = Instance.new("BodyColors")
		bodyColors.Parent = character
	end
	for _, property in BODY_COLOR_PROPERTIES do
		bodyColors[property] = skin
	end
	for _, name in BODY_PARTS do
		local part = character:FindFirstChild(name)
		if part and part:IsA("BasePart") then
			part.Color = skin
		end
	end
	-- Pacotes de corpo do avatar (braços e pernas diferentes) não combinam com as roupas do jogo
	for _, child in character:GetChildren() do
		if child:IsA("CharacterMesh") or child:IsA("ShirtGraphic") then
			child:Destroy()
		end
	end

	-- Rosto
	local head = character:FindFirstChild("Head")
	if head then
		local face = head:FindFirstChild("face")
		if not (face and face:IsA("Decal")) then
			face = Instance.new("Decal")
			face.Name = "face"
			face.Face = Enum.NormalId.Front
			face.Parent = head
		end
		face.Texture = templateUri(AppearanceData.Get("Face", appearance.Face).Texture)
	end

	-- Roupas
	setClothing(character, "Shirt", "ShirtTemplate", AppearanceData.Get("Shirt", appearance.Shirt).Template)
	setClothing(character, "Pants", "PantsTemplate", AppearanceData.Get("Pants", appearance.Pants).Template)

	-- Cabelo: tira o anterior e veste o novo (com a cor escolhida; o contorno dos de anime continua preto)
	for _, child in character:GetChildren() do
		if child:IsA("Accessory") and child:GetAttribute(AppearanceData.HairAttribute) then
			child:Destroy()
		end
	end
	local model = AppearanceData.FindHair(appearance.Hair)
	if model then
		local hair = model:Clone()
		hair:SetAttribute(AppearanceData.HairAttribute, appearance.Hair)
		local handle = hair:FindFirstChild("Handle")
		if handle then
			handle.Color = AppearanceData.HairPaint(handle, AppearanceData.Get("HairColor", appearance.HairColor).Color)
			if options.Physics and handle:GetAttribute("Roots") then
				local key = "Hair_" .. character.Name
				for _, name in COLLIDER_PARTS do
					local part = character:FindFirstChild(name)
					if part and part:IsA("BasePart") then
						part:SetAttribute("ColliderKey", key)
						CollectionService:AddTag(part, AppearanceData.ColliderTag)
					end
				end
				for name, value in AppearanceData.PhysicsSettings do
					if handle:GetAttribute(name) == nil then
						handle:SetAttribute(name, value)
					end
				end
				handle:SetAttribute("ColliderKey", key)
				CollectionService:AddTag(handle, AppearanceData.PhysicsTag)
			end
		end
		weldAccessory(character, hair)
		hair.Parent = character
	end
end

return AppearanceData
