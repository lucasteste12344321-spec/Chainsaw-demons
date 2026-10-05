-- Inventário (tecla G, botão da HUD ou "Inventário" na árvore de habilidades). Visual escuro, vermelho e branco:
--   esquerda: o personagem com o que está vestido (pose de luta, girando devagar; arraste para virar), as casas de
--     equipamento (ItemData.Slots) e os bônus somados dos itens vestidos
--   direita: os estilos de combate (cartões com o kanji; GUARDAR tira da hotbar, EQUIPAR põe de volta, e com a fusão do
--     contrato só o estilo dela fica liberado: Remotes.EquipStyle, atributos Styles/EquippedStyles/StyleFusion), os
--     itens girando em 3D e, embaixo, o escolhido com raridade, bônus e o botão EQUIPAR/TIRAR
-- Vestir soma os bônus do item nos stats e mostra o acessório no personagem: quem faz é o servidor
-- (Remotes.EquipItem); a tela se atualiza pelo atributo Equipped (JSON { [Slot] = Id }) e pela pasta Inventory.
-- Modelos: Accessories em ReplicatedStorage.VFX.Items (ItemData.FindModel), já no tamanho de jogador.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local HttpService = game:GetService("HttpService")
local CollectionService = game:GetService("CollectionService")

local Remotes = require(ReplicatedStorage:WaitForChild("Remotes"))
local UITheme = require(ReplicatedStorage:WaitForChild("UITheme"))
local ItemData = require(ReplicatedStorage:WaitForChild("ItemData"))
local SkillTreeData = require(ReplicatedStorage:WaitForChild("SkillTreeData"))
local CombatStyles = require(ReplicatedStorage:WaitForChild("CombatStyles"))
local ContractData = require(ReplicatedStorage:WaitForChild("ContractData"))
local PathData = require(ReplicatedStorage:WaitForChild("PathData"))

local Colors = UITheme.Colors
local Fonts = UITheme.Fonts

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local inventoryFolder = player:WaitForChild("Inventory", math.huge)

local CARD = Color3.fromRGB(20, 20, 24)
local LINE = Color3.fromRGB(56, 56, 62)
local WHITE = Colors.Text
local DIM = Colors.TextDim
local RED = Colors.Accent
local BLACK = Colors.Black

local PANEL_W, PANEL_H = 960, 560
local CARD_W, CARD_H = 112, 138
local SPIN_SPEED = 0.9 -- radianos por segundo dos itens girando
local PREVIEW_SPIN = 0.35 -- giro do personagem quando ninguém está arrastando
local PREVIEW_REFRESH = 0.35 -- espera o servidor vestir o item antes de copiar o personagem de novo
local SLOT_GLYPHS = { Head = "頭", Hat = "角", Neck = "首", ShoulderLeft = "肩", ShoulderRight = "肩" }
local STYLE_GLYPHS = { Punhos = "拳", Katana = "刀", Motosserra = "鋸" }
local STYLE_PREFIX = "style:" -- ids dos cartões de estilo (os de item são o Id do ItemData)
-- Telas escondidas enquanto o inventário está aberto (o minimapa some junto com a HUD)
local HIDE_WHILE_OPEN = { "HUD", "QuestTracker", "BossBar" }

local function new(className, props)
	return UITheme.new(className, props)
end

local function round(frame, radius)
	UITheme.corner(frame, radius or UDim.new(0, 6))
	return frame
end

local function text(props)
	props.BackgroundTransparency = 1
	props.TextColor3 = props.TextColor3 or WHITE
	props.Font = props.Font or Fonts.Title
	return new("TextLabel", props)
end

-- ================= Estado =================

local function readEquipped()
	local ok, value = pcall(function()
		return HttpService:JSONDecode(player:GetAttribute("Equipped") or "{}")
	end)
	local equipped = {}
	if ok and type(value) == "table" then
		for slotId, id in value do
			if type(slotId) == "string" and type(id) == "string" then
				equipped[slotId] = id
			end
		end
	end
	return equipped
end

local function isEquipped(equipped, id)
	local item = ItemData.Get(id)
	return item ~= nil and equipped[item.Slot] == id
end

local function decodeList(attribute)
	local ok, value = pcall(function()
		return HttpService:JSONDecode(player:GetAttribute(attribute) or "[]")
	end)
	return if ok and type(value) == "table" then value else {}
end

-- Estilos: (aprendidos, com ferramenta agora, estilo travado pela fusão do contrato ou nil)
local function styleState()
	local learned = decodeList("Styles")
	if #learned == 0 then
		learned = table.clone(CombatStyles.StartingStyles)
	end
	local fusion = player:GetAttribute("StyleFusion")
	return learned, decodeList("EquippedStyles"), if type(fusion) == "string" then fusion else nil
end

-- Nome, kanji e dados do estilo como o jogador luta com ele (o fundido, se tiver a fusão do contrato)
local function styleView(name)
	local path, contracts, _, form = PathData.FromPlayer(player)
	if path == "Hunter" then
		local fusion, fusionStyle = ContractData.Fusion(contracts[1], form)
		local fused = CombatStyles.Fused[contracts[1]] and CombatStyles.Fused[contracts[1]][form]
		if fusion and fusionStyle == name and fused then
			local contract = PathData.Contracts[contracts[1]]
			return fusion.DisplayName or name, contract and contract.Glyph or STYLE_GLYPHS[name] or "?", fused
		end
	end
	local style = CombatStyles.Styles[name]
	return style and style.DisplayName or name, STYLE_GLYPHS[name] or string.sub(name, 1, 2), style
end

-- Itens que o jogador tem, do mais raro para o mais comum
local function ownedItems()
	local list = {}
	for _, value in inventoryFolder:GetChildren() do
		if value:IsA("IntValue") and value.Value > 0 and ItemData.Get(value.Name) then
			table.insert(list, { Id = value.Name, Count = value.Value, Item = ItemData.Get(value.Name) })
		end
	end
	table.sort(list, function(a, b)
		local ra, rb = ItemData.RarityOrder[a.Item.Rarity] or 0, ItemData.RarityOrder[b.Item.Rarity] or 0
		if ra ~= rb then return ra > rb end
		return a.Item.Name < b.Item.Name
	end)
	return list
end

-- ================= Tela =================

local screen = UITheme.screen("Inventory", 5, playerGui)
screen.IgnoreGuiInset = true
screen.Enabled = false
local toggleEvent = new("BindableEvent", { Name = "Toggle", Parent = screen })

new("Frame", {
	Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = BLACK,
	BackgroundTransparency = 0.4,
	BorderSizePixel = 0,
	Parent = screen,
})

local panel = round(new("Frame", {
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromOffset(PANEL_W, PANEL_H),
	BackgroundColor3 = Colors.Panel,
	BackgroundTransparency = 0.06,
	Active = true,
	Parent = screen,
}), UDim.new(0, 8))
local panelStroke = UITheme.stroke(panel, WHITE, 1.5)
new("UIGradient", {
	Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Colors.AccentDark),
		ColorSequenceKeypoint.new(0.5, RED),
		ColorSequenceKeypoint.new(1, Colors.AccentDark),
	}),
	Rotation = 35,
	Parent = panelStroke,
})
UITheme.autoScale(panel, PANEL_W + 40, PANEL_H + 40)

-- Cabeçalho
text({
	Position = UDim2.fromOffset(26, 12),
	Size = UDim2.fromOffset(300, 40),
	TextXAlignment = Enum.TextXAlignment.Left,
	Font = Fonts.Marker,
	TextSize = 32,
	Text = "INVENTORY",
	Parent = panel,
})
local countLabel = text({
	Position = UDim2.fromOffset(250, 24),
	Size = UDim2.fromOffset(200, 20),
	TextXAlignment = Enum.TextXAlignment.Left,
	Font = Fonts.Body,
	TextSize = 13,
	TextColor3 = DIM,
	Parent = panel,
})
local closeButton = new("TextButton", {
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, -16, 0, 14),
	Size = UDim2.fromOffset(34, 34),
	BackgroundTransparency = 1,
	AutoButtonColor = false,
	Font = Fonts.Title,
	TextSize = 26,
	TextColor3 = DIM,
	Text = "×",
	Parent = panel,
})
UITheme.keyLabel({
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, -54, 0, 20),
	TextColor3 = DIM,
	Text = "G",
	Parent = panel,
})
-- Linha vermelha sob o cabeçalho, sumindo nas pontas
local headerLine = new("Frame", {
	Position = UDim2.fromOffset(20, 58),
	Size = UDim2.new(1, -40, 0, 2),
	BackgroundColor3 = RED,
	BorderSizePixel = 0,
	Parent = panel,
})
new("UIGradient", {
	Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.2),
		NumberSequenceKeypoint.new(0.6, 0.6),
		NumberSequenceKeypoint.new(1, 1),
	}),
	Parent = headerLine,
})

-- ----- Esquerda: personagem, casas e bônus -----
local left = new("Frame", {
	Position = UDim2.fromOffset(20, 72),
	Size = UDim2.fromOffset(300, 470),
	BackgroundTransparency = 1,
	Parent = panel,
})
local characterView = round(new("ViewportFrame", {
	Size = UDim2.fromOffset(300, 318),
	BackgroundColor3 = BLACK,
	BackgroundTransparency = 0.55,
	Ambient = Color3.fromRGB(175, 172, 172),
	LightColor = Color3.fromRGB(255, 244, 240),
	LightDirection = Vector3.new(-0.4, -0.8, -1),
	Active = true,
	Parent = left,
}), UDim.new(0, 8))
local worldModel = new("WorldModel", { Parent = characterView })
local characterCamera = Instance.new("Camera")
characterCamera.FieldOfView = 30
characterCamera.CFrame = CFrame.lookAt(Vector3.new(0, 0.3, 15), Vector3.new(0, -0.3, 0))
characterCamera.Parent = characterView
characterView.CurrentCamera = characterCamera
text({
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, -6),
	Size = UDim2.fromOffset(200, 14),
	TextXAlignment = Enum.TextXAlignment.Center,
	Font = Fonts.Light,
	TextSize = 11,
	TextColor3 = DIM,
	Text = "drag to rotate",
	Parent = characterView,
})

local slotRow = new("Frame", {
	Position = UDim2.fromOffset(0, 328),
	Size = UDim2.fromOffset(300, 76),
	BackgroundTransparency = 1,
	Parent = left,
})
UITheme.list(slotRow, 10, Enum.FillDirection.Horizontal, Enum.HorizontalAlignment.Center)

local bonusArea = new("Frame", {
	Position = UDim2.fromOffset(0, 410),
	Size = UDim2.fromOffset(300, 60),
	BackgroundTransparency = 1,
	Parent = left,
})
new("UIListLayout", {
	FillDirection = Enum.FillDirection.Horizontal,
	Wraps = true,
	Padding = UDim.new(0, 6),
	HorizontalAlignment = Enum.HorizontalAlignment.Center,
	SortOrder = Enum.SortOrder.LayoutOrder,
	Parent = bonusArea,
})

-- ----- Direita: grade e detalhes -----
local right = new("Frame", {
	Position = UDim2.fromOffset(340, 72),
	Size = UDim2.fromOffset(600, 470),
	BackgroundTransparency = 1,
	Parent = panel,
})
local grid = new("ScrollingFrame", {
	Size = UDim2.fromOffset(600, 290),
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	ScrollBarThickness = 4,
	ScrollBarImageColor3 = RED,
	AutomaticCanvasSize = Enum.AutomaticSize.Y,
	CanvasSize = UDim2.fromOffset(0, 0),
	Parent = right,
})
new("UIGridLayout", {
	CellSize = UDim2.fromOffset(CARD_W, CARD_H),
	CellPadding = UDim2.fromOffset(9, 10),
	SortOrder = Enum.SortOrder.LayoutOrder,
	Parent = grid,
})
new("UIPadding", { PaddingTop = UDim.new(0, 2), PaddingLeft = UDim.new(0, 2), Parent = grid })
local emptyLabel = text({
	AnchorPoint = Vector2.new(0.5, 0.5),
	Size = UDim2.fromOffset(460, 60),
	TextXAlignment = Enum.TextXAlignment.Center,
	TextWrapped = true,
	Font = Fonts.Body,
	TextSize = 15,
	TextColor3 = DIM,
	Text = "No items yet. Defeat bosses (the Goblin King, for example) to get drops.",
	Position = UDim2.fromOffset(300, 215), -- abaixo da fileira dos estilos
	Visible = false,
	Parent = right,
})

local details = round(new("Frame", {
	Position = UDim2.fromOffset(0, 302),
	Size = UDim2.fromOffset(600, 168),
	BackgroundColor3 = BLACK,
	BackgroundTransparency = 0.55,
	Parent = right,
}), UDim.new(0, 8))
local detailsView -- ViewportFrame do item escolhido (refeito a cada escolha)
local detailsViewHolder = new("Frame", {
	Position = UDim2.fromOffset(10, 10),
	Size = UDim2.fromOffset(148, 148),
	BackgroundTransparency = 1,
	Parent = details,
})
local detailsName = text({
	Position = UDim2.fromOffset(172, 12),
	Size = UDim2.fromOffset(410, 24),
	TextXAlignment = Enum.TextXAlignment.Left,
	TextTruncate = Enum.TextTruncate.AtEnd,
	Font = Fonts.Title,
	TextSize = 20,
	Parent = details,
})
local detailsRarity = text({
	Position = UDim2.fromOffset(172, 38),
	Size = UDim2.fromOffset(410, 16),
	TextXAlignment = Enum.TextXAlignment.Left,
	RichText = true,
	Font = Fonts.Title,
	TextSize = 13,
	Parent = details,
})
local detailsDescription = text({
	Position = UDim2.fromOffset(172, 58),
	Size = UDim2.fromOffset(410, 34),
	TextXAlignment = Enum.TextXAlignment.Left,
	TextYAlignment = Enum.TextYAlignment.Top,
	TextWrapped = true,
	Font = Fonts.Body,
	TextSize = 13,
	TextColor3 = DIM,
	Parent = details,
})
local detailsBonuses = new("Frame", {
	Position = UDim2.fromOffset(172, 96),
	Size = UDim2.fromOffset(240, 60),
	BackgroundTransparency = 1,
	Parent = details,
})
new("UIListLayout", {
	FillDirection = Enum.FillDirection.Horizontal,
	Wraps = true,
	Padding = UDim.new(0, 6),
	SortOrder = Enum.SortOrder.LayoutOrder,
	Parent = detailsBonuses,
})
local equipButton = UITheme.button({
	AnchorPoint = Vector2.new(1, 1),
	Position = UDim2.new(1, -14, 1, -14),
	Size = UDim2.fromOffset(158, 40),
	Font = Fonts.Marker,
	TextSize = 20,
	Text = "EQUIP",
	Parent = details,
}, RED)

-- ================= Modelos 3D =================

local spinners = {} -- [ViewportFrame] = Model girando

-- Item girando numa ViewportFrame (cópia da Handle do Accessory). Sem modelo, mostra o kanji da casa.
local function itemViewport(parent, itemId, size)
	local viewport = new("ViewportFrame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Ambient = Color3.fromRGB(185, 182, 182),
		LightColor = Color3.fromRGB(255, 248, 242),
		LightDirection = Vector3.new(-0.5, -1, -0.7),
		Parent = parent,
	})
	local accessory = ItemData.FindModel(itemId)
	local handle = accessory and accessory:FindFirstChild("Handle")
	if not handle then
		local item = ItemData.Get(itemId)
		text({
			Size = UDim2.fromScale(1, 1),
			TextXAlignment = Enum.TextXAlignment.Center,
			Font = Fonts.Title,
			TextSize = math.floor((size or 80) * 0.45),
			Text = item and SLOT_GLYPHS[item.Slot] or "?",
			Parent = viewport,
		})
		return viewport
	end
	local model = Instance.new("Model")
	local copy = handle:Clone()
	for _, child in copy:GetChildren() do
		if not (child:IsA("DataModelMesh") or child:IsA("SurfaceAppearance") or child:IsA("Decal")) then
			child:Destroy()
		end
	end
	copy.Anchored = true
	copy.CFrame = CFrame.new()
	copy.Parent = model
	model.PrimaryPart = copy
	model.Parent = viewport
	-- Enquadra pelo tamanho da peça (a malha dos acessórios ocupa a caixa da Handle)
	local camera = Instance.new("Camera")
	camera.FieldOfView = 32
	local radius = copy.Size.Magnitude / 2
	local distance = radius / math.sin(math.rad(camera.FieldOfView / 2)) * 1.05
	camera.CFrame = CFrame.lookAt(Vector3.new(0, radius * 0.45, distance), Vector3.zero)
	camera.Parent = viewport
	viewport.CurrentCamera = camera
	spinners[viewport] = model
	viewport.Destroying:Connect(function()
		spinners[viewport] = nil
	end)
	return viewport
end

-- ----- Personagem -----
local preview -- cópia do personagem na WorldModel
local previewYaw = math.pi -- de frente para a câmera
local draggingPreview, dragLastX = false, 0
local previewToken = 0

local PREVIEW_JUNK = { "LuaSourceContainer", "ForceField", "Sound", "BillboardGui", "ParticleEmitter", "Highlight",
	"BodyMover", "LinearVelocity", "AlignOrientation", "AlignPosition", "VectorForce", "Trail", "Beam" }
local function isPreviewJunk(instance)
	for _, className in PREVIEW_JUNK do
		if instance:IsA(className) then return true end
	end
	return false
end

local function buildPreview()
	previewToken += 1
	if preview then
		preview:Destroy()
		preview = nil
	end
	local character = player.Character
	if not character or not character:FindFirstChild("HumanoidRootPart") then return end
	local wasArchivable = character.Archivable
	character.Archivable = true
	local ok, clone = pcall(function()
		return character:Clone()
	end)
	character.Archivable = wasArchivable
	if not ok or not clone then return end
	for _, descendant in clone:GetDescendants() do
		if descendant.Parent and isPreviewJunk(descendant) then
			descendant:Destroy()
		end
	end
	-- Sem física de cabelo na prévia (o SmartBone pegaria qualquer peça com a tag, até dentro da tela)
	for _, descendant in clone:GetDescendants() do
		if CollectionService:HasTag(descendant, "SmartBone") then
			CollectionService:RemoveTag(descendant, "SmartBone")
		end
	end
	local root = clone:FindFirstChild("HumanoidRootPart")
	if root then
		root.Anchored = true
	end
	local humanoid = clone:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	end
	clone:PivotTo(CFrame.Angles(0, previewYaw, 0))
	clone.Parent = worldModel
	preview = clone
	-- Pose de luta dos Punhos (parado)
	local animator = humanoid and humanoid:FindFirstChildOfClass("Animator")
	local idleId = CombatStyles.Animation(CombatStyles.Styles.Punhos, "Idle")
	if animator and idleId then
		local animation = Instance.new("Animation")
		animation.AnimationId = "rbxassetid://" .. idleId
		local loaded, track = pcall(function()
			return animator:LoadAnimation(animation)
		end)
		if loaded and track then
			track.Looped = true
			track:Play(0)
		end
	end
end

-- O servidor veste o item um instante depois do atributo mudar
local function refreshPreviewSoon()
	previewToken += 1
	local token = previewToken
	task.delay(PREVIEW_REFRESH, function()
		if token == previewToken and screen.Enabled then
			buildPreview()
		end
	end)
end

characterView.InputBegan:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
		draggingPreview = true
		dragLastX = input.Position.X
	end
end)
UserInputService.InputChanged:Connect(function(input)
	if not draggingPreview then return end
	if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
		previewYaw += (input.Position.X - dragLastX) * 0.012
		dragLastX = input.Position.X
	end
end)
UserInputService.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
		draggingPreview = false
	end
end)

-- ================= Desenho =================

local selectedId
local cards = {} -- [Id] = { Frame, Stroke, Tag }
local renderAll -- definida depois

local function bonusPills(parent, effects, order)
	for _, child in parent:GetChildren() do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end
	local count = 0
	for index, key in SkillTreeData.EffectOrder do
		local value = effects[key]
		if value ~= nil and value ~= 0 and value ~= false then
			count += 1
			local info = SkillTreeData.EffectInfo[key] or {}
			local pill = UITheme.pill({ LayoutOrder = (order or 0) + index, Parent = parent }, info.Icon or "•",
				SkillTreeData.ShortValue(key, value))
			pill.Name = key
			UITheme.tooltip(pill, UITheme.tipText(info.Name or key, SkillTreeData.EffectText(key, value)))
		end
	end
	return count
end

local FUSION_COLOR = Color3.fromRGB(255, 140, 30)
local GREY = Color3.fromRGB(46, 46, 52)

local function isStyleId(id)
	return type(id) == "string" and string.sub(id, 1, #STYLE_PREFIX) == STYLE_PREFIX
end

-- Detalhes de um estilo de combate: kanji, estado (equipado, guardado, fundido, bloqueado), o que ele é e as técnicas
local function paintStyle(name)
	local _, equippedList, fusion = styleState()
	local displayName, glyph, data = styleView(name)
	local equipped = table.find(equippedList, name) ~= nil
	details.Visible = true
	detailsView = text({
		Size = UDim2.fromScale(1, 1),
		TextXAlignment = Enum.TextXAlignment.Center,
		Font = Fonts.Title,
		TextSize = 84,
		TextColor3 = if fusion == name then FUSION_COLOR else WHITE,
		Text = glyph,
		Parent = detailsViewHolder,
	})
	detailsName.Text = displayName
	local stateText, stateColor
	if fusion == name then
		stateText, stateColor = "FUSED WITH THE CONTRACT", FUSION_COLOR
	elseif fusion then
		stateText, stateColor = "LOCKED BY THE FUSION", DIM
	elseif equipped then
		stateText, stateColor = "EQUIPPED", RED
	else
		stateText, stateColor = "STORED", DIM
	end
	detailsRarity.Text = `<font color="#{stateColor:ToHex()}">COMBAT STYLE  ·  {stateText}</font>`
	local node = SkillTreeData.Get(name)
	local lines = { if node and node.Flavor then node.Flavor else "" }
	local skills = {}
	for _, slot in CombatStyles.SkillSlots do
		local skill = data and data.Skills and data.Skills[slot]
		if skill then
			table.insert(skills, `{slot}: {skill.Name}`)
		end
	end
	if #skills > 0 then
		table.insert(lines, "Techniques  " .. table.concat(skills, "   "))
	end
	if fusion and fusion ~= name then
		table.insert(lines, "With the contract fusion, only the fused style can be used.")
	elseif not fusion then
		table.insert(lines, if equipped then "Storing removes the style from the hotbar (1 to 5)." else "Equipping puts the style back on the hotbar.")
	end
	detailsDescription.Size = UDim2.fromOffset(410, 96)
	detailsDescription.Text = table.concat(lines, "\n")
	bonusPills(detailsBonuses, {}, 0)
	if fusion then
		equipButton.Text = if fusion == name then "FUSED" else "LOCKED"
		equipButton.BackgroundColor3 = GREY
	else
		equipButton.Text = if equipped then "STORE" else "EQUIP"
		equipButton.BackgroundColor3 = if equipped then GREY else RED
	end
end

local function paintDetails(equipped)
	if detailsView then
		detailsView:Destroy()
		detailsView = nil
	end
	if isStyleId(selectedId) then
		paintStyle(string.sub(selectedId, #STYLE_PREFIX + 1))
		return
	end
	detailsDescription.Size = UDim2.fromOffset(410, 34)
	local item = selectedId and ItemData.Get(selectedId)
	details.Visible = item ~= nil
	if not item then return end
	detailsView = itemViewport(detailsViewHolder, selectedId, 148)
	detailsName.Text = item.Name
	local slot = ItemData.GetSlot(item.Slot)
	local color = ItemData.RarityColors[item.Rarity] or WHITE
	detailsRarity.Text = `<font color="#{color:ToHex()}">{UITheme.upper(item.Rarity)}</font>  <font color="#{DIM:ToHex()}">·  {if slot then slot.Name else "-"}</font>`
	detailsDescription.Text = item.Description or ""
	bonusPills(detailsBonuses, item.Effects or {}, 0)
	local worn = isEquipped(equipped, selectedId)
	equipButton.Text = if worn then "REMOVE" else "EQUIP"
	equipButton.BackgroundColor3 = if worn then Color3.fromRGB(46, 46, 52) else RED
end

local function selectItem(id)
	selectedId = id
	local equipped = readEquipped()
	for cardId, card in cards do
		local selected = cardId == id
		card.Stroke.Color = if selected then WHITE else LINE
		card.Stroke.Thickness = if selected then 2 else 1
	end
	paintDetails(equipped)
end

local function makeCard(entry, order, equipped)
	local item = entry.Item
	local color = ItemData.RarityColors[item.Rarity] or WHITE
	local card = round(new("TextButton", {
		BackgroundColor3 = CARD,
		BackgroundTransparency = 0.1,
		AutoButtonColor = false,
		Text = "",
		LayoutOrder = order,
		Parent = grid,
	}), UDim.new(0, 8))
	local stroke = UITheme.stroke(card, LINE, 1)
	-- Brilho da raridade atrás do item
	local glow = new("Frame", {
		Size = UDim2.new(1, 0, 0, 92),
		BackgroundColor3 = color,
		BackgroundTransparency = 0.5,
		BorderSizePixel = 0,
		Parent = card,
	})
	round(glow, UDim.new(0, 8))
	new("UIGradient", {
		Rotation = 90,
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.55, 0.85),
			NumberSequenceKeypoint.new(1, 0.55),
		}),
		Parent = glow,
	})
	local viewHolder = new("Frame", {
		Size = UDim2.new(1, 0, 0, 92),
		BackgroundTransparency = 1,
		Parent = card,
	})
	itemViewport(viewHolder, entry.Id, 92)
	text({
		Position = UDim2.fromOffset(8, 94),
		Size = UDim2.new(1, -16, 0, 34),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		TextWrapped = true,
		Font = Fonts.Title,
		TextSize = 12,
		Text = item.Name,
		Parent = card,
	})
	new("Frame", {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -3),
		Size = UDim2.new(1, -16, 0, 3),
		BackgroundColor3 = color,
		BorderSizePixel = 0,
		Parent = card,
	})
	if entry.Count > 1 then
		text({
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -8, 0, 6),
			Size = UDim2.fromOffset(40, 16),
			TextXAlignment = Enum.TextXAlignment.Right,
			Font = Fonts.Number,
			TextSize = 13,
			TextStrokeTransparency = 0.4,
			Text = `x{entry.Count}`,
			Parent = card,
		})
	end
	local tag = round(new("Frame", {
		Position = UDim2.fromOffset(6, 6),
		Size = UDim2.fromOffset(62, 16),
		BackgroundColor3 = RED,
		Visible = isEquipped(equipped, entry.Id),
		Parent = card,
	}), UDim.new(0, 4))
	text({
		Size = UDim2.fromScale(1, 1),
		TextXAlignment = Enum.TextXAlignment.Center,
		Font = Fonts.Title,
		TextSize = 9,
		Text = "EQUIPPED",
		Parent = tag,
	})
	card.MouseEnter:Connect(function()
		if selectedId ~= entry.Id then
			stroke.Color = DIM
		end
	end)
	card.MouseLeave:Connect(function()
		if selectedId ~= entry.Id then
			stroke.Color = LINE
		end
	end)
	card.Activated:Connect(function()
		selectItem(entry.Id)
	end)
	local slot = ItemData.GetSlot(item.Slot)
	UITheme.tooltip(card, UITheme.tipText(item.Name,
		`<font color="#{color:ToHex()}">{item.Rarity}</font> · {if slot then slot.Name else "-"}\nClick to see its bonuses and wear it.`))
	cards[entry.Id] = { Frame = card, Stroke = stroke, Tag = tag }
end

-- Cartão de estilo de combate: kanji grande, nome e o estado no canto
local function makeStyleCard(name, order, equippedList, fusion)
	local id = STYLE_PREFIX .. name
	local displayName, glyph = styleView(name)
	local equipped = table.find(equippedList, name) ~= nil
	local locked = fusion ~= nil and fusion ~= name
	local color = if fusion == name then FUSION_COLOR elseif locked then DIM else WHITE
	local card = round(new("TextButton", {
		BackgroundColor3 = CARD,
		BackgroundTransparency = 0.1,
		AutoButtonColor = false,
		Text = "",
		LayoutOrder = order,
		Parent = grid,
	}), UDim.new(0, 8))
	local stroke = UITheme.stroke(card, LINE, 1)
	text({
		Size = UDim2.new(1, 0, 0, 92),
		TextXAlignment = Enum.TextXAlignment.Center,
		Font = Fonts.Title,
		TextSize = 54,
		TextColor3 = color,
		TextTransparency = if locked or not equipped then 0.45 else 0,
		Text = glyph,
		Parent = card,
	})
	text({
		Position = UDim2.fromOffset(8, 94),
		Size = UDim2.new(1, -16, 0, 34),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		TextWrapped = true,
		Font = Fonts.Title,
		TextSize = 12,
		TextColor3 = if locked then DIM else WHITE,
		Text = displayName,
		Parent = card,
	})
	new("Frame", {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -3),
		Size = UDim2.new(1, -16, 0, 3),
		BackgroundColor3 = if fusion == name then FUSION_COLOR else RED,
		BackgroundTransparency = if locked then 0.7 else 0,
		BorderSizePixel = 0,
		Parent = card,
	})
	local tagText = if fusion == name then "FUSED" elseif locked then "LOCKED" elseif equipped then "EQUIPPED" else "STORED"
	local tag = round(new("Frame", {
		Position = UDim2.fromOffset(6, 6),
		Size = UDim2.fromOffset(66, 16),
		BackgroundColor3 = if fusion == name then FUSION_COLOR elseif equipped and not locked then RED else GREY,
		Parent = card,
	}), UDim.new(0, 4))
	text({
		Size = UDim2.fromScale(1, 1),
		TextXAlignment = Enum.TextXAlignment.Center,
		Font = Fonts.Title,
		TextSize = 9,
		Text = tagText,
		Parent = tag,
	})
	card.MouseEnter:Connect(function()
		if selectedId ~= id then
			stroke.Color = DIM
		end
	end)
	card.MouseLeave:Connect(function()
		if selectedId ~= id then
			stroke.Color = LINE
		end
	end)
	card.Activated:Connect(function()
		selectItem(id)
	end)
	UITheme.tooltip(card, UITheme.tipText(displayName, `Combat style · {string.lower(tagText)}\nClick to see its techniques and store or equip it.`))
	cards[id] = { Frame = card, Stroke = stroke, Tag = tag }
end

local function makeSlot(slot, equipped)
	local holder = new("Frame", {
		Size = UDim2.fromOffset(52, 72),
		BackgroundTransparency = 1,
		LayoutOrder = slot.Order,
		Parent = slotRow,
	})
	local box = round(new("TextButton", {
		Size = UDim2.fromOffset(52, 52),
		BackgroundColor3 = CARD,
		BackgroundTransparency = 0.1,
		AutoButtonColor = false,
		Text = "",
		Parent = holder,
	}), UDim.new(0, 8))
	local id = equipped[slot.Id]
	UITheme.stroke(box, if id then RED else LINE, if id then 1.5 else 1)
	local worn = id and ItemData.Get(id)
	UITheme.tooltip(box, UITheme.tipText(slot.Name, if worn then `Vestindo: {worn.Name}` else "Vazio"))
	if id then
		itemViewport(box, id, 52)
		box.Activated:Connect(function()
			selectItem(id)
		end)
	else
		text({
			Size = UDim2.fromScale(1, 1),
			TextXAlignment = Enum.TextXAlignment.Center,
			Font = Fonts.Title,
			TextSize = 20,
			TextColor3 = LINE,
			Text = SLOT_GLYPHS[slot.Id] or "·",
			Parent = box,
		})
	end
	text({
		Position = UDim2.fromOffset(-10, 55),
		Size = UDim2.fromOffset(72, 14),
		TextXAlignment = Enum.TextXAlignment.Center,
		Font = Fonts.Title,
		TextSize = 10,
		TextColor3 = DIM,
		Text = slot.Name,
		Parent = holder,
	})
end

function renderAll()
	local equipped = readEquipped()
	for _, child in grid:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	table.clear(cards)
	-- Estilos de combate primeiro, depois os itens
	local learned, equippedList, fusion = styleState()
	for index, name in learned do
		makeStyleCard(name, index, equippedList, fusion)
	end
	local list = ownedItems()
	local total = 0
	for index, entry in list do
		total += entry.Count
		makeCard(entry, 100 + index, equipped)
	end
	emptyLabel.Visible = #list == 0
	countLabel.Text = if total == 1 then "1 item" else `{total} items`

	for _, child in slotRow:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	for _, slot in ItemData.Slots do
		makeSlot(slot, equipped)
	end

	local oldHint = bonusArea:FindFirstChild("Hint")
	if oldHint then
		oldHint:Destroy()
	end
	if bonusPills(bonusArea, ItemData.Compute(equipped), 0) == 0 then
		text({
			Name = "Hint",
			Size = UDim2.fromOffset(300, 20),
			TextXAlignment = Enum.TextXAlignment.Center,
			Font = Fonts.Body,
			TextSize = 12,
			TextColor3 = DIM,
			Text = "Wear an item to get its bonuses.",
			Parent = bonusArea,
		})
	end

	-- Mantém a escolha (ou pega o primeiro item; sem itens, o primeiro estilo)
	if not selectedId or not cards[selectedId] then
		selectedId = if list[1] then list[1].Id elseif learned[1] then STYLE_PREFIX .. learned[1] else nil
	end
	selectItem(selectedId)
end

-- ================= Ações =================

equipButton.MouseButton1Click:Connect(function()
	if not selectedId then return end
	if isStyleId(selectedId) then
		-- Com a fusão do contrato os estilos ficam travados (o servidor também confere)
		local _, equippedList, fusion = styleState()
		if fusion then return end
		local name = string.sub(selectedId, #STYLE_PREFIX + 1)
		Remotes.EquipStyle:FireServer(name, table.find(equippedList, name) == nil)
		return
	end
	Remotes.EquipItem:FireServer(selectedId, not isEquipped(readEquipped(), selectedId))
end)

local isOpen = false
local hiddenGuis = {}
local blur

local function setOpen(open)
	if open == isOpen then return end
	isOpen = open
	if open then
		-- A árvore de habilidades fecha (as duas usam o mesmo espaço)
		local tree = playerGui:FindFirstChild("SkillTree")
		if tree and tree.Enabled then
			local toggle = tree:FindFirstChild("Toggle")
			if toggle then
				toggle:Fire()
			end
		end
		for _, name in HIDE_WHILE_OPEN do
			local gui = playerGui:FindFirstChild(name)
			if gui and gui:IsA("ScreenGui") and gui.Enabled then
				gui.Enabled = false
				table.insert(hiddenGuis, gui)
			end
		end
		blur = new("BlurEffect", { Size = 0, Parent = workspace.CurrentCamera })
		UITheme.tween(blur, 0.2, { Size = 14 })
		screen.Enabled = true
		renderAll()
		buildPreview()
	else
		screen.Enabled = false
		for _, gui in hiddenGuis do
			if gui.Parent then
				gui.Enabled = true
			end
		end
		table.clear(hiddenGuis)
		if blur then
			blur:Destroy()
			blur = nil
		end
		if preview then
			preview:Destroy()
			preview = nil
		end
		draggingPreview = false
	end
end

closeButton.MouseButton1Click:Connect(function()
	setOpen(false)
end)
closeButton.MouseEnter:Connect(function()
	closeButton.TextColor3 = RED
end)
closeButton.MouseLeave:Connect(function()
	closeButton.TextColor3 = DIM
end)
toggleEvent.Event:Connect(function()
	setOpen(not isOpen)
end)

UserInputService.InputBegan:Connect(function(input, processed)
	if processed or player:GetAttribute("MenuOpen") then return end
	if input.KeyCode == Enum.KeyCode.G then
		setOpen(not isOpen)
	end
end)

-- Mudou o que tem ou o que está vestido: redesenha (e copia o personagem de novo, já com o item)
local function onInventoryChanged()
	if isOpen then
		renderAll()
	end
end
player:GetAttributeChangedSignal("Equipped"):Connect(function()
	if isOpen then
		renderAll()
		refreshPreviewSoon()
	end
end)
local function watchValue(value)
	if value:IsA("IntValue") then
		value.Changed:Connect(onInventoryChanged)
	end
	onInventoryChanged()
end
-- Estilos guardados/equipados ou fusão do contrato: os cartões de estilo mudam
for _, attribute in { "Styles", "EquippedStyles", "StyleFusion" } do
	player:GetAttributeChangedSignal(attribute):Connect(onInventoryChanged)
end
inventoryFolder.ChildAdded:Connect(watchValue)
inventoryFolder.ChildRemoved:Connect(onInventoryChanged)
for _, value in inventoryFolder:GetChildren() do
	watchValue(value)
end
player.CharacterAdded:Connect(function()
	if isOpen then
		refreshPreviewSoon()
	end
end)

-- Giro dos itens e do personagem
RunService.RenderStepped:Connect(function(dt)
	if not isOpen then return end
	local angle = os.clock() * SPIN_SPEED
	for viewport, model in spinners do
		if model.Parent and viewport.Visible then
			model:PivotTo(CFrame.Angles(0.18, angle, 0))
		end
	end
	if preview and preview.Parent then
		if not draggingPreview then
			previewYaw += PREVIEW_SPIN * dt
		end
		preview:PivotTo(CFrame.Angles(0, previewYaw, 0))
	end
end)
