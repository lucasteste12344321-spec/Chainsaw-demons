-- Menu principal (a primeira tela depois do carregamento; substitui a antiga tela de título do TeamScript):
--   JOGAR, PERSONAGEM (criador com prévia 3D: pele, rosto, cabelo, cor do cabelo, camisa e calça), CLÃ (sorteio com
--   raridade; giros por código ou comprados com Gold), CÓDIGOS, PASSES (abre a loja do GamepassShop) e CONFIGURAÇÕES.
-- Primeiro acesso (atributo CharacterCreated = false): abre direto no criador e, depois de salvar, mostra o clã que
-- saiu no sorteio de nascença. Quem salva, sorteia e resgata é o servidor (CharacterService); esta tela só pede e mostra.
-- Enquanto está aberto: atributo MenuOpen = true no LocalPlayer (os scripts de tecla ignoram as teclas) e o controle
-- de movimento desligado. A HUD reabre pelo BindableEvent TitleScreen.Open (botão "Menu principal").
-- A ScreenGui continua com o nome "TitleScreen": a tela de carregamento (ReplicatedFirst) espera por ela.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local HttpService = game:GetService("HttpService")
local SoundService = game:GetService("SoundService")
local CollectionService = game:GetService("CollectionService")

local Remotes = require(ReplicatedStorage:WaitForChild("Remotes"))
local UITheme = require(ReplicatedStorage:WaitForChild("UITheme"))
local AppearanceData = require(ReplicatedStorage:WaitForChild("AppearanceData"))
local ClanData = require(ReplicatedStorage:WaitForChild("ClanData"))
local SkillTreeData = require(ReplicatedStorage:WaitForChild("SkillTreeData"))
local PathData = require(ReplicatedStorage:WaitForChild("PathData"))
local CombatStyles = require(ReplicatedStorage:WaitForChild("CombatStyles"))
local FastMode = require(script.Parent:WaitForChild("FastMode"))

local Colors = UITheme.Colors
local Fonts = UITheme.Fonts

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local DESIGN_W, DESIGN_H = 1280, 720
local LOAD_TIMEOUT = 15 -- segundos esperando os dados antes de liberar o menu mesmo assim
local CARD = Color3.fromRGB(20, 20, 24)
local CARD_LIGHT = Color3.fromRGB(30, 30, 36)
local LINE = Color3.fromRGB(56, 56, 62)
local WHITE = Colors.Text
local DIM = Colors.TextDim
-- Tema do menu (2026-09-30, pedido do usuário): laranja e branco sobre cinza. O resto da interface segue o UITheme.
local ACCENT = Color3.fromRGB(255, 122, 26) -- laranja
local LIGHT = Color3.fromRGB(255, 255, 255) -- no lugar do creme do tema (Colors.Gold)
-- Visual compacto (2026-10-05, pedido do usuário: "mais compacto e bonito"): Builder Sans nos textos e botões; o nome
-- do jogo continua com a fonte de terror
-- (numa tabela só: o script está perto do limite de 200 variáveis locais do Luau)
local MenuFont = { Heavy = Enum.Font.BuilderSansExtraBold, Bold = Enum.Font.BuilderSansBold, Medium = Enum.Font.BuilderSansMedium }
local BLACK = Colors.Black
local ROLL_FAST = 0.055 -- intervalo da roleta enquanto espera o servidor
local ROLL_TIMEOUT = 6
local CAMERA_FULL = CFrame.lookAt(Vector3.new(0, 0.3, 13.5), Vector3.new(0, -0.3, 0))
local CAMERA_HEAD = CFrame.lookAt(Vector3.new(0, 1.8, 5.6), Vector3.new(0, 1.5, 0))

local function new(className, props)
	return UITheme.new(className, props)
end

local function label(props)
	return UITheme.label(props)
end

local function round(frame, radius)
	UITheme.corner(frame, radius or UDim.new(0, 6))
	return frame
end

local function upper(textValue)
	return UITheme.upper(textValue)
end

-- 0.0786 -> "7,86%", 0.55 -> "55%", 0.005 -> "0,5%"
local function formatChance(chance)
	local percent = chance * 100
	local textValue = string.format(if percent >= 10 then "%.1f" else "%.2f", percent)
	textValue = string.gsub(textValue, "0+$", "")
	textValue = string.gsub(textValue, "%.$", "")
	return (string.gsub(textValue, "%.", ",")) .. "%"
end

-- ================= Estado vindo do servidor =================

local function readAppearance()
	local ok, value = pcall(function()
		return HttpService:JSONDecode(player:GetAttribute("Appearance") or "{}")
	end)
	return AppearanceData.Sanitize(if ok then value else nil)
end

local function currentClanId()
	local id = player:GetAttribute("Clan")
	return if ClanData.Get(id) then id else nil
end

local function spinsLeft()
	local value = player:GetAttribute("ClanSpins")
	return if type(value) == "number" then value else 0
end

local function goldAmount()
	local leaderstats = player:FindFirstChild("leaderstats")
	local gold = leaderstats and leaderstats:FindFirstChild("Gold")
	return if gold then gold.Value else 0
end

-- Conta com item aleatório pago restrito pelo Roblox (CharacterService, PolicyService): sem roleta, escolhe o clã.
-- Enquanto o servidor não responde, vale a regra mais segura (restrito), como no servidor.
-- O script está perto do limite de 200 variáveis locais do Luau: o que é da escolha de clã fica nesta tabela
local ClanChoice = {}

function ClanChoice.Restricted()
	return player:GetAttribute("RandomItemsRestricted") ~= false
end

local function isCreated()
	return player:GetAttribute("CharacterCreated") == true
end

-- ================= Tela =================

local screen = UITheme.screen("TitleScreen", 15, playerGui)
screen.IgnoreGuiInset = true
local openEvent = new("BindableEvent", { Name = "Open", Parent = screen })

-- Cortina preta das transições (acima do menu)
local curtainGui = UITheme.screen("MenuCurtain", 16, playerGui)
curtainGui.IgnoreGuiInset = true
local curtain = new("Frame", {
	Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = BLACK,
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	Parent = curtainGui,
})

-- Fundo: grafite escuro, um brilho laranja atrás da prévia e uma sombra atrás da coluna de botões. Já nasce opaco
-- para o mapa nunca aparecer depois do carregamento.
local background = new("Frame", {
	Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = Color3.fromRGB(62, 62, 68),
	BorderSizePixel = 0,
	Active = true, -- segura os cliques (a ferramenta equipada não recebe)
	Parent = screen,
})
UITheme.gradient(background, { Color3.fromRGB(50, 50, 55), Color3.fromRGB(180, 180, 188) })
-- Brilho atrás do personagem: círculos quase transparentes um dentro do outro (fica um degradê redondo e suave)
for index = 1, 6 do
	local size = 1 - (index - 1) * 0.14
	new("UICorner", {
		CornerRadius = UDim.new(0.5, 0),
		Parent = new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.72, 0.5),
			Size = UDim2.fromScale(0.62 * size, 1.1 * size),
			BackgroundColor3 = ACCENT,
			BackgroundTransparency = 0.965,
			BorderSizePixel = 0,
			Parent = background,
		}),
	})
end
-- Sombra à esquerda (os botões leem melhor)
do
	local leftShade = new("Frame", {
		Size = UDim2.fromScale(0.55, 1),
		BackgroundColor3 = BLACK,
		BorderSizePixel = 0,
		Parent = background,
	})
	new("UIGradient", {
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.35),
			NumberSequenceKeypoint.new(0.7, 0.8),
			NumberSequenceKeypoint.new(1, 1),
		}),
		Parent = leftShade,
	})
end
-- Kanji gigante de fundo (悪魔 = demônio), bem apagado atrás da prévia
label({
	AnchorPoint = Vector2.new(1, 0.5),
	Position = UDim2.new(1, -20, 0.5, 0),
	Size = UDim2.fromOffset(700, 700),
	TextXAlignment = Enum.TextXAlignment.Right,
	Font = Fonts.Title,
	TextSize = 330,
	TextColor3 = ACCENT,
	TextTransparency = 0.94,
	Text = "悪\n魔",
	LineHeight = 0.95,
	Parent = background,
})

local content = new("Frame", {
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromOffset(DESIGN_W, DESIGN_H),
	BackgroundTransparency = 1,
	Visible = false,
	Parent = screen,
})
UITheme.autoScale(content, DESIGN_W, DESIGN_H)

-- ================= Prévia do personagem (direita) =================

local stage = new("Frame", {
	Position = UDim2.fromOffset(640, 20),
	Size = UDim2.fromOffset(580, 680),
	BackgroundTransparency = 1,
	Parent = content,
})
local previewView = new("ViewportFrame", {
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 0),
	Size = UDim2.fromOffset(500, 580),
	BackgroundTransparency = 1,
	Ambient = Color3.fromRGB(170, 166, 168),
	LightColor = Color3.fromRGB(255, 244, 240),
	LightDirection = Vector3.new(-0.45, -0.8, -1),
	Active = true,
	Parent = stage,
})
local worldModel = new("WorldModel", { Parent = previewView })
local previewCamera = Instance.new("Camera")
previewCamera.FieldOfView = 28
previewCamera.CFrame = CAMERA_FULL
previewCamera.Parent = previewView
previewView.CurrentCamera = previewCamera
-- Sombra no chão
round(new("Frame", {
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.new(0.5, 0, 0, 548),
	Size = UDim2.fromOffset(190, 26),
	BackgroundColor3 = BLACK,
	BackgroundTransparency = 0.55,
	ZIndex = 0,
	Parent = stage,
}), UDim.new(0.5, 0))
local previewStatus = label({
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.new(0.5, 0, 0, 290),
	Size = UDim2.fromOffset(300, 30),
	TextXAlignment = Enum.TextXAlignment.Center,
	Font = Fonts.Body,
	TextSize = 15,
	TextColor3 = DIM,
	Text = "Carregando o personagem...",
	Parent = stage,
})
label({
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 584),
	Size = UDim2.fromOffset(560, 40),
	TextXAlignment = Enum.TextXAlignment.Center,
	Font = MenuFont.Heavy,
	TextSize = 28,
	TextStrokeTransparency = 0.6,
	Text = upper(player.DisplayName),
	Parent = stage,
})
local clanLine = label({
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 624),
	Size = UDim2.fromOffset(560, 24),
	TextXAlignment = Enum.TextXAlignment.Center,
	RichText = true,
	Font = MenuFont.Bold,
	TextSize = 16,
	Parent = stage,
})
label({
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 652),
	Size = UDim2.fromOffset(300, 18),
	TextXAlignment = Enum.TextXAlignment.Center,
	Font = Fonts.Light,
	TextSize = 12,
	TextColor3 = DIM,
	Text = "arraste o personagem para girar",
	Parent = stage,
})

local preview -- cópia do personagem na WorldModel
local previewYaw = math.pi -- de frente para a câmera
local previewSpin = true -- gira sozinho (tela inicial)
local draggingPreview, dragLastX = false, 0
local draft = AppearanceData.Default() -- aparência sendo montada no criador
local previewToken = 0

local PREVIEW_JUNK = { "LuaSourceContainer", "ForceField", "Sound", "BillboardGui", "ParticleEmitter", "Highlight",
	"BodyMover", "LinearVelocity", "AlignOrientation", "AlignPosition", "VectorForce", "Trail", "Beam", "Tool" }
local function isPreviewJunk(instance)
	for _, className in PREVIEW_JUNK do
		if instance:IsA(className) then return true end
	end
	-- Itens equipados ficam para o inventário: aqui só o visual do personagem
	return instance:IsA("Accessory") and instance:GetAttribute("EquippedItem") ~= nil
end

local function playPreviewIdle(model)
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	local animator = humanoid and humanoid:FindFirstChildOfClass("Animator")
	local idleId = CombatStyles.Animation(CombatStyles.Styles.Punhos, "Idle")
	if not animator or not idleId then return end
	local animation = Instance.new("Animation")
	animation.AnimationId = "rbxassetid://" .. idleId
	local ok, track = pcall(function()
		return animator:LoadAnimation(animation)
	end)
	if ok and track then
		track.Looped = true
		track:Play(0)
	end
end

local function applyDraftToPreview()
	if preview then
		AppearanceData.Apply(preview, draft)
	end
end

local function buildPreview()
	previewToken += 1
	if preview then
		preview:Destroy()
		preview = nil
	end
	local character = player.Character
	if not character or not character:FindFirstChild("HumanoidRootPart") or not character:FindFirstChild("Head") then
		previewStatus.Visible = true
		return
	end
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
	-- Sem física de cabelo dentro da prévia (o SmartBone pegaria qualquer peça com a tag)
	for _, descendant in clone:GetDescendants() do
		if CollectionService:HasTag(descendant, AppearanceData.PhysicsTag) then
			CollectionService:RemoveTag(descendant, AppearanceData.PhysicsTag)
		end
	end
	local root = clone:FindFirstChild("HumanoidRootPart")
	root.Anchored = true
	local humanoid = clone:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	end
	clone:PivotTo(CFrame.Angles(0, previewYaw, 0))
	clone.Parent = worldModel
	preview = clone
	previewStatus.Visible = false
	applyDraftToPreview()
	playPreviewIdle(clone)
end

previewView.InputBegan:Connect(function(input)
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
RunService.RenderStepped:Connect(function(dt)
	if not screen.Enabled or not preview or not preview.Parent then return end
	if previewSpin and not draggingPreview then
		previewYaw += 0.3 * dt
	end
	preview:PivotTo(CFrame.Angles(0, previewYaw, 0))
end)

local function setCamera(target, instant)
	if instant then
		previewCamera.CFrame = target
	else
		UITheme.tween(previewCamera, 0.45, { CFrame = target }, Enum.EasingStyle.Quint)
	end
end

-- Linha do clã embaixo do nome: kanji e nome na cor da raridade
local function refreshClanLine()
	local clan = ClanData.Get(currentClanId())
	if not clan then
		clanLine.Text = ""
		return
	end
	local color = ClanData.Color(clan.Id)
	clanLine.Text = `<font color="#{color:ToHex()}">{clan.Kanji}  Clã {clan.Name}</font>  <font color="#{DIM:ToHex()}">·  {clan.Rarity}</font>`
end

-- ================= Botões e peças =================

-- Botão da coluna da esquerda: compacto, com o kanji num quadradinho e o texto em Builder Sans. primary = laranja
-- cheio (JOGAR); os outros são cartões escuros que acendem no hover (barrinha laranja à esquerda).
local function slabButton(parent, order, glyph, textValue, primary)
	local height = if primary then 48 else 38
	local button = new("TextButton", {
		Size = UDim2.fromOffset(290, height),
		BackgroundColor3 = if primary then ACCENT else CARD,
		BackgroundTransparency = if primary then 0 else 0.35,
		AutoButtonColor = false,
		LayoutOrder = order,
		Text = "",
		Parent = parent,
	})
	round(button, UDim.new(0, 10))
	local stroke = UITheme.stroke(button, if primary then Color3.fromRGB(128, 52, 8) else WHITE, 1, if primary then 0.4 else 0.9)
	if primary then
		UITheme.gradient(button, { Color3.fromRGB(255, 255, 255), Color3.fromRGB(215, 205, 198) })
	end
	local bar = round(new("Frame", {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 0, 0.5, 0),
		Size = UDim2.new(0, 3, 0.5, 0),
		BackgroundColor3 = if primary then LIGHT else ACCENT,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Parent = button,
	}), UDim.new(0, 2))
	local glyphBox = round(new("Frame", {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 8, 0.5, 0),
		Size = UDim2.fromOffset(height - 14, height - 14),
		BackgroundColor3 = if primary then BLACK else ACCENT,
		BackgroundTransparency = if primary then 0.82 else 0.85,
		BorderSizePixel = 0,
		Parent = button,
	}), UDim.new(0, 7))
	local glyphLabel = label({
		Size = UDim2.fromScale(1, 1),
		TextXAlignment = Enum.TextXAlignment.Center,
		Font = Fonts.Title,
		TextSize = if primary then 18 else 15,
		TextColor3 = if primary then WHITE else ACCENT,
		Text = glyph,
		Parent = glyphBox,
	})
	local textX = height + 2
	local textLabel = label({
		Position = UDim2.fromOffset(textX, 0),
		Size = UDim2.new(1, -(textX + 40), 1, 0),
		Font = MenuFont.Heavy,
		TextSize = if primary then 20 else 16,
		TextColor3 = WHITE,
		Text = textValue,
		Parent = button,
	})
	button.MouseEnter:Connect(function()
		UITheme.tween(textLabel, 0.12, { Position = UDim2.fromOffset(textX + 5, 0) })
		UITheme.tween(bar, 0.12, { BackgroundTransparency = 0 })
		if not primary then
			UITheme.tween(button, 0.12, { BackgroundTransparency = 0.1 })
			stroke.Transparency = 0.7
		end
	end)
	button.MouseLeave:Connect(function()
		UITheme.tween(textLabel, 0.12, { Position = UDim2.fromOffset(textX, 0) })
		UITheme.tween(bar, 0.12, { BackgroundTransparency = 1 })
		if not primary then
			UITheme.tween(button, 0.12, { BackgroundTransparency = 0.35 })
			stroke.Transparency = 0.9
		end
	end)
	return button, textLabel, glyphLabel
end

-- Bolinha laranja com número (giros guardados no botão CLÃ)
local function badge(parent)
	local frame = round(new("Frame", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -14, 0.5, 0),
		Size = UDim2.fromOffset(20, 20),
		BackgroundColor3 = ACCENT,
		Visible = false,
		Parent = parent,
	}), UDim.new(0.5, 0))
	UITheme.stroke(frame, BLACK, 1.5)
	local value = label({
		Size = UDim2.fromScale(1, 1),
		TextXAlignment = Enum.TextXAlignment.Center,
		Font = MenuFont.Heavy,
		TextSize = 12,
		Parent = frame,
	})
	return frame, value
end

-- Cabeçalho das páginas: título, subtítulo e o × de voltar. Painel escuro de cantos redondos, a 92% do tamanho do
-- projeto (o conteúdo continua nas mesmas posições) e no meio da altura.
local function makePage(titleText, subtitleText)
	local page = new("Frame", {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.fromOffset(60, DESIGN_H / 2),
		Size = UDim2.fromOffset(540, 640),
		BackgroundColor3 = Color3.fromRGB(18, 18, 21),
		BackgroundTransparency = 0.06,
		BorderSizePixel = 0,
		Visible = false,
		Active = true,
		Parent = content,
	})
	round(page, UDim.new(0, 14))
	UITheme.stroke(page, WHITE, 1, 0.88)
	new("UIScale", { Scale = 0.92, Parent = page })
	local title = label({
		Position = UDim2.fromOffset(24, 18),
		Size = UDim2.fromOffset(420, 34),
		Font = MenuFont.Heavy,
		TextSize = 28,
		Text = titleText,
		Parent = page,
	})
	local subtitle = label({
		Position = UDim2.fromOffset(25, 54),
		Size = UDim2.fromOffset(440, 18),
		Font = MenuFont.Medium,
		TextSize = 14,
		TextColor3 = DIM,
		Text = subtitleText,
		Parent = page,
	})
	local close = round(new("TextButton", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -16, 0, 16),
		Size = UDim2.fromOffset(34, 34),
		BackgroundColor3 = CARD_LIGHT,
		BackgroundTransparency = 0.3,
		AutoButtonColor = false,
		Font = Fonts.Title,
		TextSize = 22,
		TextColor3 = DIM,
		Text = "×",
		Parent = page,
	}), UDim.new(0.5, 0))
	close.MouseEnter:Connect(function()
		close.TextColor3 = WHITE
		close.BackgroundColor3 = ACCENT
	end)
	close.MouseLeave:Connect(function()
		close.TextColor3 = DIM
		close.BackgroundColor3 = CARD_LIGHT
	end)
	local line = new("Frame", {
		Position = UDim2.fromOffset(24, 84),
		Size = UDim2.new(1, -48, 0, 1),
		BackgroundColor3 = WHITE,
		BackgroundTransparency = 0.85,
		BorderSizePixel = 0,
		Parent = page,
	})
	new("UIGradient", {
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0),
			NumberSequenceKeypoint.new(1, 1),
		}),
		Parent = line,
	})
	return { Frame = page, Title = title, Subtitle = subtitle, Close = close }
end

-- Botão comum (UITheme.button) com Builder Sans (antes era a fonte de pincel)
local function actionButton(parent, props, color)
	props.Font = props.Font or MenuFont.Heavy
	props.TextSize = math.min(props.TextSize or 18, 18)
	props.Parent = parent
	return UITheme.button(props, color or ACCENT, ACCENT)
end

local function setButtonEnabled(button, enabled)
	button.Active = enabled
	button.AutoButtonColor = false
	button.TextTransparency = if enabled then 0 else 0.5
	button.BackgroundTransparency = if enabled then 0 else 0.45
end

-- Janela de confirmação por cima de tudo. onYes só roda se o jogador confirmar.
local confirmLayer = new("Frame", {
	Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = BLACK,
	BackgroundTransparency = 0.45,
	BorderSizePixel = 0,
	Active = true,
	Visible = false,
	ZIndex = 50,
	Parent = screen,
})
local confirmPanel = round(new("Frame", {
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromOffset(460, 220),
	BackgroundColor3 = Color3.fromRGB(18, 18, 21),
	BackgroundTransparency = 0.04,
	BorderSizePixel = 0,
	ZIndex = 51,
	Parent = confirmLayer,
}), UDim.new(0, 14))
UITheme.stroke(confirmPanel, WHITE, 1, 0.85)
UITheme.autoScale(confirmPanel, 500, 260)
local confirmTitle = label({
	Position = UDim2.fromOffset(24, 18),
	Size = UDim2.fromOffset(412, 36),
	Font = MenuFont.Heavy,
	TextSize = 24,
	ZIndex = 52,
	Parent = confirmPanel,
})
local confirmText = label({
	Position = UDim2.fromOffset(24, 60),
	Size = UDim2.fromOffset(412, 80),
	TextYAlignment = Enum.TextYAlignment.Top,
	TextWrapped = true,
	RichText = true,
	Font = Fonts.Body,
	TextSize = 16,
	TextColor3 = DIM,
	ZIndex = 52,
	Parent = confirmPanel,
})
local confirmYes = actionButton(confirmPanel, {
	AnchorPoint = Vector2.new(1, 1),
	Position = UDim2.new(1, -24, 1, -20),
	Size = UDim2.fromOffset(190, 46),
	ZIndex = 52,
})
local confirmNo = actionButton(confirmPanel, {
	AnchorPoint = Vector2.new(0, 1),
	Position = UDim2.new(0, 24, 1, -20),
	Size = UDim2.fromOffset(190, 46),
	ZIndex = 52,
}, Colors.PanelLight)
local confirmCallbacks = {}
local function confirm(titleText, bodyText, yesText, noText, onYes, onNo)
	confirmTitle.Text = titleText
	confirmText.Text = bodyText
	confirmYes.Text = yesText
	confirmNo.Text = noText
	confirmCallbacks = { Yes = onYes, No = onNo }
	confirmLayer.Visible = true
end
confirmYes.MouseButton1Click:Connect(function()
	confirmLayer.Visible = false
	local callback = confirmCallbacks.Yes
	confirmCallbacks = {}
	if callback then callback() end
end)
confirmNo.MouseButton1Click:Connect(function()
	confirmLayer.Visible = false
	local callback = confirmCallbacks.No
	confirmCallbacks = {}
	if callback then callback() end
end)

-- ================= Tela inicial (esquerda) =================

local home = new("Frame", {
	Position = UDim2.fromOffset(80, 0),
	Size = UDim2.fromOffset(460, DESIGN_H),
	BackgroundTransparency = 1,
	Parent = content,
})
local logo = label({
	Position = UDim2.fromOffset(0, 112),
	Size = UDim2.fromOffset(460, 130),
	TextYAlignment = Enum.TextYAlignment.Top,
	Font = Fonts.Horror,
	TextSize = 66,
	LineHeight = 0.88,
	TextColor3 = LIGHT,
	Text = "CHAINSAW\nDEMONS",
	Parent = home,
})
new("UIStroke", { Color = BLACK, Thickness = 4, Parent = logo })
UITheme.drips(logo, { Color = ACCENT, Count = 5, MaxLength = 22, Seed = 21, From = 0.04, To = 0.5 })
local logoScale = new("UIScale", { Parent = logo })

local statusLabel = label({
	Position = UDim2.fromOffset(2, 248),
	Size = UDim2.fromOffset(440, 20),
	RichText = true,
	Font = MenuFont.Bold,
	TextSize = 16,
	TextColor3 = LIGHT,
	Text = "Carregando seus dados...",
	Parent = home,
})

local buttonList = new("Frame", {
	Position = UDim2.fromOffset(0, 284),
	Size = UDim2.fromOffset(300, 340),
	BackgroundTransparency = 1,
	Parent = home,
})
UITheme.list(buttonList, 6)
local playButton, playText = slabButton(buttonList, 1, "始", "JOGAR", true)
local characterButton = slabButton(buttonList, 2, "顔", "PERSONAGEM")
local clanButton = slabButton(buttonList, 3, "家", "CLÃ")
local codesButton = slabButton(buttonList, 4, "符", "CÓDIGOS")
local passesButton = slabButton(buttonList, 5, "券", "PASSES")
local settingsButton = slabButton(buttonList, 6, "設", "CONFIGURAÇÕES")
local spinBadge, spinBadgeText = badge(clanButton)
UITheme.tooltip(characterButton, UITheme.tipText("Personagem", "Pele, rosto, cabelo e roupas"))
UITheme.tooltip(clanButton, function()
	return UITheme.tipText("Clã", `Seu sobrenome dá um bônus pequeno. Giros guardados: {spinsLeft()}`)
end)
UITheme.tooltip(codesButton, UITheme.tipText("Códigos", "Resgate códigos para ganhar giros de clã"))
UITheme.tooltip(passesButton, UITheme.tipText("Passes e VIP", "Benefícios permanentes, giros diários e servidor VIP"))
-- Trocar de save (PlayerData "Switch": salva e entra num servidor novo, onde a tela de saves abre de novo).
-- Num bloco: o script está perto do limite de variáveis locais.
do
	local switchButton = slabButton(buttonList, 7, "替", "CHANGE SAVE")
	UITheme.tooltip(switchButton, UITheme.tipText("Change save", "Saves this character and opens the save list again"))
	switchButton.MouseButton1Click:Connect(function()
		confirm("CHANGE SAVE?", "Your progress is saved and you will rejoin the game to pick another save.", "CHANGE", "CANCEL", function()
			Remotes.SaveSlotAction:FireServer("Switch")
		end)
	end)
end

label({
	Position = UDim2.fromOffset(2, 612),
	Size = UDim2.fromOffset(440, 16),
	Font = MenuFont.Medium,
	TextSize = 12,
	TextColor3 = DIM,
	Text = "Enter: jogar   ·   no jogo, o botão ≡ da HUD tem \"Menu principal\"",
	Parent = home,
})

-- ================= Página: personagem =================

local characterPage = makePage("PERSONAGEM", "Monte o visual do seu caçador")
local creating = false -- primeiro acesso: sem voltar, termina no SALVAR

local tabsRow = new("Frame", {
	Position = UDim2.fromOffset(20, 96),
	Size = UDim2.fromOffset(500, 40),
	BackgroundTransparency = 1,
	Parent = characterPage.Frame,
})
UITheme.list(tabsRow, 8, Enum.FillDirection.Horizontal)
local tabContent = new("ScrollingFrame", {
	Position = UDim2.fromOffset(20, 146),
	Size = UDim2.fromOffset(500, 410),
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	ScrollBarThickness = 4,
	ScrollBarImageColor3 = ACCENT,
	AutomaticCanvasSize = Enum.AutomaticSize.Y,
	CanvasSize = UDim2.fromOffset(0, 0),
	Parent = characterPage.Frame,
})
UITheme.list(tabContent, 10)
UITheme.padding(tabContent, 2, 8, 8, 2)

local dirtyLabel = label({
	Position = UDim2.fromOffset(24, 566),
	Size = UDim2.fromOffset(300, 18),
	Font = Fonts.Body,
	TextSize = 13,
	TextColor3 = LIGHT,
	Text = "",
	Parent = characterPage.Frame,
})
local randomButton = actionButton(characterPage.Frame, {
	AnchorPoint = Vector2.new(0, 1),
	Position = UDim2.new(0, 20, 1, -18),
	Size = UDim2.fromOffset(200, 46),
	Text = "ALEATÓRIO",
	TextSize = 20,
}, Colors.PanelLight)
local saveButton = actionButton(characterPage.Frame, {
	AnchorPoint = Vector2.new(1, 1),
	Position = UDim2.new(1, -20, 1, -18),
	Size = UDim2.fromOffset(260, 46),
	Text = "SALVAR",
})

local sectionRefreshers = {} -- funções que repintam a seleção de cada seção
local tabButtons = {}
local tabSections = {} -- [tabId] = { frames }
local currentTab = "Corpo"

local function sectionTitle(parent, order, textValue)
	return label({
		Size = UDim2.fromOffset(480, 22),
		Font = Fonts.Title,
		TextSize = 15,
		TextColor3 = WHITE,
		Text = upper(textValue),
		LayoutOrder = order,
		Parent = parent,
	})
end

local function gridFrame(parent, order, cellSize, padding)
	local frame = new("Frame", {
		Size = UDim2.fromOffset(480, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		LayoutOrder = order,
		Parent = parent,
	})
	new("UIGridLayout", {
		CellSize = cellSize,
		CellPadding = padding or UDim2.fromOffset(8, 8),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = frame,
	})
	return frame
end

local refreshDirty -- definida depois

local function setDraft(field, id)
	if draft[field] == id then return end
	draft[field] = id
	applyDraftToPreview()
	for _, refresh in sectionRefreshers do
		refresh()
	end
	refreshDirty()
end

-- Bolinhas de cor (pele e cor do cabelo)
local function swatchSection(tabId, order, titleText, field, list)
	local title = sectionTitle(tabContent, order, titleText)
	local grid = gridFrame(tabContent, order + 1, UDim2.fromOffset(40, 40), UDim2.fromOffset(9, 9))
	local strokes = {}
	for index, entry in list do
		local button = round(new("TextButton", {
			BackgroundColor3 = entry.Color,
			AutoButtonColor = false,
			LayoutOrder = index,
			Parent = grid,
		}), UDim.new(0.5, 0))
		strokes[entry.Id] = UITheme.stroke(button, BLACK, 2)
		UITheme.tooltip(button, UITheme.tipText(entry.Name))
		button.MouseButton1Click:Connect(function()
			setDraft(field, entry.Id)
		end)
	end
	table.insert(sectionRefreshers, function()
		for id, stroke in strokes do
			local selected = draft[field] == id
			stroke.Color = if selected then WHITE else BLACK
			stroke.Thickness = if selected then 3 else 2
		end
	end)
	tabSections[tabId] = tabSections[tabId] or {}
	table.insert(tabSections[tabId], title)
	table.insert(tabSections[tabId], grid)
end

-- Rostos: a imagem do rosto em cima da cor da pele escolhida
local function faceSection(tabId, order)
	local title = sectionTitle(tabContent, order, "Rosto")
	local grid = gridFrame(tabContent, order + 1, UDim2.fromOffset(110, 110))
	local cells = {}
	for index, entry in AppearanceData.Faces do
		local button = round(new("TextButton", {
			BackgroundColor3 = CARD,
			AutoButtonColor = false,
			LayoutOrder = index,
			Parent = grid,
		}), UDim.new(0, 8))
		local stroke = UITheme.stroke(button, LINE, 1.5)
		local skin = round(new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0, 8),
			Size = UDim2.fromOffset(74, 74),
			BackgroundColor3 = AppearanceData.Skins[1].Color,
			Parent = button,
		}), UDim.new(0, 10))
		new("ImageLabel", {
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			Image = "rbxassetid://" .. entry.Texture,
			ScaleType = Enum.ScaleType.Fit,
			Parent = skin,
		})
		label({
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -4),
			Size = UDim2.fromOffset(104, 18),
			TextXAlignment = Enum.TextXAlignment.Center,
			Font = Fonts.Title,
			TextSize = 12,
			Text = entry.Name,
			Parent = button,
		})
		cells[entry.Id] = { Stroke = stroke, Skin = skin }
		button.MouseButton1Click:Connect(function()
			setDraft("Face", entry.Id)
		end)
	end
	table.insert(sectionRefreshers, function()
		local skinColor = AppearanceData.Get("Skin", draft.Skin).Color
		for id, cell in cells do
			local selected = draft.Face == id
			cell.Stroke.Color = if selected then ACCENT else LINE
			cell.Stroke.Thickness = if selected then 3 else 1.5
			cell.Skin.BackgroundColor3 = skinColor
		end
	end)
	tabSections[tabId] = tabSections[tabId] or {}
	table.insert(tabSections[tabId], title)
	table.insert(tabSections[tabId], grid)
end

-- Lista de opções com nome (cabelos e roupas). extra(entry, button) pode enfeitar o botão.
local function optionSection(tabId, order, titleText, field, list, extra)
	local title = sectionTitle(tabContent, order, titleText)
	local grid = gridFrame(tabContent, order + 1, UDim2.fromOffset(236, 40))
	local cells = {}
	for index, entry in list do
		local button = round(new("TextButton", {
			BackgroundColor3 = CARD,
			BackgroundTransparency = 0.05,
			AutoButtonColor = false,
			LayoutOrder = index,
			Parent = grid,
		}), UDim.new(0, 6))
		local stroke = UITheme.stroke(button, LINE, 1.5)
		local nameText = label({
			Position = UDim2.fromOffset(14, 0),
			Size = UDim2.new(1, -24, 1, 0),
			TextTruncate = Enum.TextTruncate.AtEnd,
			Font = Fonts.Title,
			TextSize = 14,
			Text = entry.Name,
			Parent = button,
		})
		if extra then
			extra(entry, button, nameText)
		end
		cells[entry.Id] = { Stroke = stroke, Button = button }
		button.MouseButton1Click:Connect(function()
			setDraft(field, entry.Id)
		end)
		button.MouseEnter:Connect(function()
			if draft[field] ~= entry.Id then
				button.BackgroundColor3 = CARD_LIGHT
			end
		end)
		button.MouseLeave:Connect(function()
			button.BackgroundColor3 = CARD
		end)
	end
	table.insert(sectionRefreshers, function()
		for id, cell in cells do
			local selected = draft[field] == id
			cell.Stroke.Color = if selected then ACCENT else LINE
			cell.Stroke.Thickness = if selected then 2.5 else 1.5
		end
	end)
	tabSections[tabId] = tabSections[tabId] or {}
	table.insert(tabSections[tabId], title)
	table.insert(tabSections[tabId], grid)
end

-- Chip com a cor principal da roupa, à esquerda do nome
local function clothingChip(entry, _button, nameText)
	local chip = round(new("Frame", {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 12, 0.5, 0),
		Size = UDim2.fromOffset(18, 18),
		BackgroundColor3 = entry.Color,
		Parent = nameText.Parent,
	}), UDim.new(0, 4))
	UITheme.stroke(chip, LINE, 1)
	nameText.Position = UDim2.fromOffset(40, 0)
	nameText.Size = UDim2.new(1, -50, 1, 0)
end

-- Selo "física" nos cabelos com SmartBone (espera os modelos de ReplicatedStorage.VFX.Hair chegarem)
local function addHairTag(entry, button, nameText)
	local tag = round(new("Frame", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -8, 0.5, 0),
		Size = UDim2.fromOffset(52, 20),
		BackgroundColor3 = BLACK,
		BackgroundTransparency = 0.3,
		Parent = button,
	}), UDim.new(0.5, 0))
	UITheme.stroke(tag, LIGHT, 1, 0.3)
	label({
		Size = UDim2.fromScale(1, 1),
		TextXAlignment = Enum.TextXAlignment.Center,
		Font = Fonts.Title,
		TextSize = 11,
		TextColor3 = LIGHT,
		Text = "física",
		Parent = tag,
	})
	nameText.Size = UDim2.new(1, -84, 1, 0)
	UITheme.tooltip(button, UITheme.tipText(entry.Name, "Balança com o movimento (SmartBone)"))
end
local function hairTag(entry, button, nameText)
	if not entry.Model then return end
	task.spawn(function()
		local vfx = ReplicatedStorage:WaitForChild("VFX", 30)
		local folder = vfx and vfx:WaitForChild(AppearanceData.HairFolderName, 30)
		local model = folder and folder:WaitForChild(entry.Model, 30)
		if model and AppearanceData.HasPhysics(entry.Id) then
			addHairTag(entry, button, nameText)
		end
	end)
end

swatchSection("Corpo", 10, "Pele", "Skin", AppearanceData.Skins)
faceSection("Corpo", 20)
optionSection("Cabelo", 30, "Estilo", "Hair", AppearanceData.Hairs, hairTag)
swatchSection("Cabelo", 40, "Cor do cabelo", "HairColor", AppearanceData.HairColors)
optionSection("Roupa", 50, "Camisa", "Shirt", AppearanceData.Shirts, clothingChip)
optionSection("Roupa", 60, "Calça", "Pants", AppearanceData.Pants, clothingChip)

local TABS = {
	{ Id = "Corpo", Text = "CORPO", Camera = CAMERA_HEAD },
	{ Id = "Cabelo", Text = "CABELO", Camera = CAMERA_HEAD },
	{ Id = "Roupa", Text = "ROUPA", Camera = CAMERA_FULL },
}

local function selectTab(tabId, instant)
	currentTab = tabId
	for id, frames in tabSections do
		for _, frame in frames do
			frame.Visible = id == tabId
		end
	end
	for id, button in tabButtons do
		local selected = id == tabId
		button.BackgroundColor3 = if selected then ACCENT else CARD
		button.TextColor3 = if selected then WHITE else DIM
	end
	tabContent.CanvasPosition = Vector2.zero
	for _, tab in TABS do
		if tab.Id == tabId then
			setCamera(tab.Camera, instant)
		end
	end
end

for index, tab in TABS do
	local button = round(new("TextButton", {
		Size = UDim2.fromOffset(158, 38),
		BackgroundColor3 = CARD,
		AutoButtonColor = false,
		Font = MenuFont.Heavy,
		TextSize = 16,
		TextColor3 = DIM,
		Text = tab.Text,
		LayoutOrder = index,
		Parent = tabsRow,
	}), UDim.new(0, 4))
	UITheme.stroke(button, BLACK, 1.5)
	tabButtons[tab.Id] = button
	button.MouseButton1Click:Connect(function()
		selectTab(tab.Id)
	end)
end

local function sameAppearance(a, b)
	for field in AppearanceData.Fields do
		if a[field] ~= b[field] then return false end
	end
	return true
end

function refreshDirty()
	local dirty = not sameAppearance(draft, readAppearance()) or not isCreated()
	dirtyLabel.Text = if dirty and isCreated() then "• alterações não salvas" else ""
	return dirty
end

-- ================= Página: clã =================

local clanPage = makePage("CLÃ", "Seu sobrenome dá um bônus pequeno para sempre")
local clanCard = round(new("Frame", {
	Position = UDim2.fromOffset(20, 98),
	Size = UDim2.fromOffset(500, 196),
	BackgroundColor3 = BLACK,
	BackgroundTransparency = 0.45,
	ClipsDescendants = true,
	Parent = clanPage.Frame,
}), UDim.new(0, 8))
local clanCardStroke = UITheme.stroke(clanCard, LINE, 1.5)
local kanjiBox = round(new("Frame", {
	Position = UDim2.fromOffset(16, 16),
	Size = UDim2.fromOffset(132, 132),
	BackgroundColor3 = CARD,
	Parent = clanCard,
}), UDim.new(0, 10))
local kanjiStroke = UITheme.stroke(kanjiBox, ACCENT, 3)
local kanjiScale = new("UIScale", { Parent = kanjiBox })
local kanjiLabel = label({
	Size = UDim2.fromScale(1, 1),
	TextXAlignment = Enum.TextXAlignment.Center,
	TextScaled = true,
	Font = Fonts.Title,
	Text = "?",
	Parent = kanjiBox,
})
new("UIPadding", {
	PaddingTop = UDim.new(0, 14),
	PaddingBottom = UDim.new(0, 14),
	PaddingLeft = UDim.new(0, 12),
	PaddingRight = UDim.new(0, 12),
	Parent = kanjiLabel,
})
new("UITextSizeConstraint", { MaxTextSize = 70, Parent = kanjiLabel })
-- Raios atrás do kanji na revelação de clã épico/lendário
local rays = new("Frame", {
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromOffset(82, 82),
	Size = UDim2.fromOffset(300, 300),
	BackgroundTransparency = 1,
	ZIndex = 0,
	Visible = false,
	Parent = clanCard,
})
for i = 1, 12 do
	new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(300, 10),
		Rotation = i * 15,
		BackgroundColor3 = WHITE,
		BackgroundTransparency = 0.7,
		BorderSizePixel = 0,
		ZIndex = 0,
		Parent = rays,
	})
end
local clanName = label({
	Position = UDim2.fromOffset(166, 14),
	Size = UDim2.fromOffset(320, 40),
	Font = MenuFont.Heavy,
	TextSize = 30,
	Text = "",
	Parent = clanCard,
})
local clanRarity = label({
	Position = UDim2.fromOffset(168, 54),
	Size = UDim2.fromOffset(320, 20),
	RichText = true,
	Font = Fonts.Title,
	TextSize = 15,
	Parent = clanCard,
})
local clanDescription = label({
	Position = UDim2.fromOffset(168, 78),
	Size = UDim2.fromOffset(316, 40),
	TextYAlignment = Enum.TextYAlignment.Top,
	TextWrapped = true,
	Font = Fonts.Body,
	TextSize = 13,
	TextColor3 = DIM,
	Parent = clanCard,
})
local clanPills = new("Frame", {
	Position = UDim2.fromOffset(166, 122),
	Size = UDim2.fromOffset(320, 60),
	BackgroundTransparency = 1,
	Parent = clanCard,
})
new("UIListLayout", {
	FillDirection = Enum.FillDirection.Horizontal,
	Wraps = true,
	Padding = UDim.new(0, 6),
	SortOrder = Enum.SortOrder.LayoutOrder,
	Parent = clanPills,
})
local flash = new("Frame", {
	Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = WHITE,
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	ZIndex = 5,
	Parent = clanCard,
})

-- Giros (créditos, nas contas sem sorteio pago)
ClanChoice.SpinsTitle = label({
	Position = UDim2.fromOffset(24, 306),
	Size = UDim2.fromOffset(120, 18),
	Font = Fonts.Title,
	TextSize = 13,
	TextColor3 = DIM,
	Text = "GIROS",
	Parent = clanPage.Frame,
})
local spinsValue = label({
	Position = UDim2.fromOffset(22, 322),
	Size = UDim2.fromOffset(120, 40),
	Font = Fonts.Number,
	TextSize = 36,
	Text = "0",
	Parent = clanPage.Frame,
})
local spinButton = actionButton(clanPage.Frame, {
	Position = UDim2.fromOffset(128, 310),
	Size = UDim2.fromOffset(170, 50),
	Text = "GIRAR",
	TextSize = 26,
})
local buyButton = actionButton(clanPage.Frame, {
	Position = UDim2.fromOffset(310, 310),
	Size = UDim2.fromOffset(210, 50),
	Font = Fonts.Title,
	TextSize = 15,
	Text = `+1 GIRO  ·  {UITheme.formatNumber(ClanData.SpinGoldCost)} Gold`,
}, Colors.PanelLight)
local clanHint = label({
	Position = UDim2.fromOffset(24, 366),
	Size = UDim2.fromOffset(496, 18),
	RichText = true,
	Font = Fonts.Body,
	TextSize = 13,
	TextColor3 = DIM,
	Parent = clanPage.Frame,
})
local continueButton = actionButton(clanPage.Frame, {
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, -18),
	Size = UDim2.fromOffset(300, 48),
	Text = "CONTINUAR",
	Visible = false,
})

label({
	Position = UDim2.fromOffset(24, 394),
	Size = UDim2.fromOffset(300, 20),
	Font = Fonts.Title,
	TextSize = 14,
	Text = "TODOS OS CLÃS",
	Parent = clanPage.Frame,
})
local clanList = new("ScrollingFrame", {
	Position = UDim2.fromOffset(20, 418),
	Size = UDim2.fromOffset(500, 204),
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	ScrollBarThickness = 4,
	ScrollBarImageColor3 = ACCENT,
	AutomaticCanvasSize = Enum.AutomaticSize.Y,
	CanvasSize = UDim2.fromOffset(0, 0),
	Parent = clanPage.Frame,
})
UITheme.list(clanList, 4)
local rolling = false
local refreshClanPage -- definida mais abaixo (o clique na lista usa)
local clanRows = {} -- [Id] = { Frame, Stroke, Value }
ClanChoice.Headers = {} -- [raridade] = rótulo do título da raridade
ClanChoice.Selected = nil -- contas sem sorteio pago: clã marcado na lista para escolher

local function effectsText(effects)
	local lines = {}
	for _, key in SkillTreeData.EffectOrder do
		local value = effects[key]
		if value ~= nil and value ~= 0 and value ~= false then
			table.insert(lines, SkillTreeData.EffectText(key, value))
		end
	end
	return table.concat(lines, "\n")
end

do
	local lastRarity
	local order = 0
	for _, clan in ClanData.Sorted() do
		local rarity = ClanData.GetRarity(clan.Rarity)
		if clan.Rarity ~= lastRarity then
			lastRarity = clan.Rarity
			order += 1
			ClanChoice.Headers[clan.Rarity] = label({
				Size = UDim2.fromOffset(480, 22),
				RichText = true,
				Font = Fonts.Title,
				TextSize = 13,
				Text = `<font color="#{rarity.Color:ToHex()}">{upper(rarity.Id)}</font>  <font color="#{DIM:ToHex()}">{formatChance(rarity.Chance)} no total</font>`,
				LayoutOrder = order,
				Parent = clanList,
			})
		end
		order += 1
		local row = round(new("Frame", {
			Size = UDim2.fromOffset(484, 32),
			BackgroundColor3 = CARD,
			BackgroundTransparency = 0.1,
			LayoutOrder = order,
			Parent = clanList,
		}), UDim.new(0, 5))
		local stroke = UITheme.stroke(row, LINE, 1)
		label({
			Position = UDim2.fromOffset(10, 0),
			Size = UDim2.new(0, 64, 1, 0),
			Font = Fonts.Title,
			TextSize = 15,
			TextColor3 = rarity.Color,
			Text = clan.Kanji,
			Parent = row,
		})
		label({
			Position = UDim2.fromOffset(80, 0),
			Size = UDim2.new(0, 150, 1, 0),
			Font = Fonts.Title,
			TextSize = 14,
			Text = clan.Name,
			Parent = row,
		})
		label({
			Position = UDim2.fromOffset(230, 0),
			Size = UDim2.new(0, 170, 1, 0),
			TextTruncate = Enum.TextTruncate.AtEnd,
			Font = Fonts.Body,
			TextSize = 12,
			TextColor3 = DIM,
			Text = (string.gsub(effectsText(clan.Effects), "\n", " · ")),
			Parent = row,
		})
		local value = label({
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -10, 0, 0),
			Size = UDim2.new(0, 84, 1, 0),
			TextXAlignment = Enum.TextXAlignment.Right,
			Font = Fonts.Number,
			TextSize = 13,
			TextColor3 = rarity.Color,
			Text = formatChance(ClanData.Chance(clan.Id)),
			Parent = row,
		})
		-- Clique marca o clã para escolher (só nas contas sem sorteio pago)
		local hit = new("TextButton", {
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			Text = "",
			AutoButtonColor = false,
			ZIndex = 3,
			Parent = row,
		})
		hit.MouseButton1Click:Connect(function()
			if ClanChoice.Restricted() and not rolling then
				ClanChoice.Selected = if clan.Id == currentClanId() then nil else clan.Id
				refreshClanPage()
			end
		end)
		UITheme.tooltip(hit, UITheme.tipText(`{clan.Kanji}  {clan.Name}  ·  {clan.Rarity}`, clan.Description .. "\n" .. effectsText(clan.Effects)))
		clanRows[clan.Id] = { Frame = row, Stroke = stroke, Value = value }
	end
end

local function clearPills()
	for _, child in clanPills:GetChildren() do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end
end

-- Mostra um clã no cartão. reel = true: só kanji, nome e cor (quadros da roleta)
local function showClan(clanId, reel)
	local clan = ClanData.Get(clanId)
	clearPills()
	if not clan then
		kanjiLabel.Text = "?"
		kanjiLabel.TextColor3 = DIM
		kanjiStroke.Color = LINE
		clanName.Text = "SEM CLÃ"
		clanRarity.Text = ""
		clanDescription.Text = ""
		return
	end
	local color = ClanData.Color(clan.Id)
	kanjiLabel.Text = clan.Kanji
	kanjiLabel.TextColor3 = color
	kanjiStroke.Color = color
	clanCardStroke.Color = if reel then LINE else color
	clanName.Text = upper(clan.Name)
	if reel then
		clanRarity.Text = `<font color="#{color:ToHex()}">{upper(clan.Rarity)}</font>`
		clanDescription.Text = ""
		return
	end
	local detail = if ClanChoice.Restricted()
		then `{UITheme.formatNumber(ClanData.ChooseGoldCost[clan.Rarity] or 0)} Gold para escolher`
		else `{formatChance(ClanData.Chance(clan.Id))} de chance`
	clanRarity.Text = `<font color="#{color:ToHex()}">{upper(clan.Rarity)}</font>  <font color="#{DIM:ToHex()}">·  {detail}</font>`
	clanDescription.Text = clan.Description
	for index, key in SkillTreeData.EffectOrder do
		local value = clan.Effects[key]
		if value ~= nil then
			local info = SkillTreeData.EffectInfo[key] or {}
			local pill = UITheme.pill({ LayoutOrder = index, Parent = clanPills }, info.Icon or "•", SkillTreeData.ShortValue(key, value))
			UITheme.tooltip(pill, UITheme.tipText(info.Name or key, SkillTreeData.EffectText(key, value)))
		end
	end
end

local revealing = false -- primeiro acesso: mostrando o clã de nascença

-- Preço de escolher o clã em texto ("2 créditos + 3.000 Gold") e o Gold que falta pagar
function ClanChoice.CostText(clanId)
	local credits, gold = ClanData.ChooseCost(clanId, spinsLeft())
	local parts = {}
	if credits > 0 then
		table.insert(parts, `{credits} {if credits == 1 then "crédito" else "créditos"}`)
	end
	if gold > 0 or credits == 0 then
		table.insert(parts, `{UITheme.formatNumber(gold)} Gold`)
	end
	return table.concat(parts, " + "), gold
end

function refreshClanPage()
	local clanId = currentClanId()
	local choosing = ClanChoice.Restricted()
	if not choosing or ClanChoice.Selected == clanId then
		ClanChoice.Selected = nil
	end
	if not rolling then
		showClan(ClanChoice.Selected or clanId, false)
	end
	for id, row in clanRows do
		local current = id == clanId
		local selected = id == ClanChoice.Selected
		row.Stroke.Color = if selected then ACCENT elseif current then ClanData.Color(id) else LINE
		row.Stroke.Thickness = if current or selected then 2 else 1
		local clan = ClanData.Get(id)
		row.Value.Text = if choosing
			then UITheme.formatNumber(ClanData.ChooseGoldCost[clan.Rarity] or 0) .. " G"
			else formatChance(ClanData.Chance(id))
	end
	for rarityId, header in ClanChoice.Headers do
		local rarity = ClanData.GetRarity(rarityId)
		local detail = if choosing
			then `{UITheme.formatNumber(ClanData.ChooseGoldCost[rarityId] or 0)} Gold cada`
			else `{formatChance(rarity.Chance)} no total`
		header.Text = `<font color="#{rarity.Color:ToHex()}">{upper(rarity.Id)}</font>  <font color="#{DIM:ToHex()}">{detail}</font>`
	end
	spinsValue.Text = tostring(spinsLeft())
	ClanChoice.SpinsTitle.Text = if choosing then "CRÉDITOS" else "GIROS"
	buyButton.Visible = not choosing
	if choosing then
		spinButton.Text = "ESCOLHER"
		local gold = if ClanChoice.Selected then select(2, ClanChoice.CostText(ClanChoice.Selected)) else 0
		setButtonEnabled(spinButton, not rolling and ClanChoice.Selected ~= nil and goldAmount() >= gold)
		if not rolling then
			if ClanChoice.Selected then
				local clan = ClanData.Get(ClanChoice.Selected)
				clanHint.Text = `Escolher <b>{clan.Name}</b>: {ClanChoice.CostText(ClanChoice.Selected)} (você tem <b>{UITheme.formatNumber(goldAmount())}</b> Gold).`
			else
				clanHint.Text = `Sem sorteio na sua conta: toque num clã da lista para escolher. Cada crédito vale {UITheme.formatNumber(ClanData.SpinGoldCost)} Gold.`
			end
		end
		return
	end
	spinButton.Text = "GIRAR"
	local canSpin = not rolling and spinsLeft() > 0
	setButtonEnabled(spinButton, canSpin)
	setButtonEnabled(buyButton, not rolling and goldAmount() >= ClanData.SpinGoldCost)
	if not rolling then
		if spinsLeft() > 0 then
			clanHint.Text = `Você tem <b>{UITheme.formatNumber(goldAmount())}</b> Gold. Cada giro troca o seu clã pelo que sair.`
		else
			clanHint.Text = `Sem giros: resgate um código ou compre com Gold (você tem <b>{UITheme.formatNumber(goldAmount())}</b>).`
		end
	end
end

-- Revelação: flash, o kanji estoura e encolhe e, se for épico ou lendário, raios girando
local function reveal(clanId)
	local clan = ClanData.Get(clanId)
	showClan(clanId, false)
	flash.BackgroundTransparency = 0.1
	UITheme.tween(flash, 0.5, { BackgroundTransparency = 1 })
	kanjiScale.Scale = 1.35
	UITheme.tween(kanjiScale, 0.45, { Scale = 1 }, Enum.EasingStyle.Back)
	if clan and ClanData.IsPrecious(clanId) then
		local color = ClanData.Color(clanId)
		for _, ray in rays:GetChildren() do
			ray.BackgroundColor3 = color
		end
		rays.Visible = true
		rays.Rotation = 0
		UITheme.tween(rays, 3, { Rotation = 90 }, Enum.EasingStyle.Linear)
		task.delay(3, function()
			rays.Visible = false
		end)
		-- Tremida na tela
		task.spawn(function()
			local base = content.Position
			for i = 1, 8 do
				content.Position = base + UDim2.fromOffset(math.random(-6, 6), math.random(-4, 4))
				task.wait(0.03)
			end
			content.Position = base
		end)
	end
end

local pendingResult -- nil = esperando; false = sem giro; string = Id sorteado
local function runReel(onDone)
	rolling = true
	refreshClanPage()
	clanHint.Text = "Girando..."
	local clans = ClanData.Clans
	local started = os.clock()
	local last
	-- Rápido enquanto o servidor não responde
	while pendingResult == nil and os.clock() - started < ROLL_TIMEOUT do
		local pick = clans[math.random(1, #clans)]
		if pick.Id ~= last then
			last = pick.Id
			showClan(pick.Id, true)
		end
		task.wait(ROLL_FAST)
	end
	local result = pendingResult
	-- Freando até parar no resultado
	if result then
		local elapsed = 0
		local interval = ROLL_FAST
		while elapsed < 1.7 do
			local pick = clans[math.random(1, #clans)]
			if pick.Id ~= result then
				showClan(pick.Id, true)
			end
			task.wait(interval)
			elapsed += interval
			interval *= 1.22
		end
	end
	rolling = false
	if result then
		reveal(result)
	end
	refreshClanPage()
	onDone(result)
end

local function spin()
	if rolling or spinsLeft() < 1 then return end
	local function go()
		pendingResult = nil
		Remotes.ClanSpin:FireServer()
		task.spawn(runReel, function(result)
			if result == nil then
				clanHint.Text = "O servidor não respondeu. Tente de novo."
			elseif result == false then
				clanHint.Text = "Sem giros: resgate um código ou compre com Gold."
			else
				local clan = ClanData.Get(result)
				clanHint.Text = `Novo clã: <b>{clan.Name}</b> ({clan.Rarity}). Giros restantes: {spinsLeft()}.`
			end
		end)
	end
	local current = currentClanId()
	if current and ClanData.IsPrecious(current) then
		local clan = ClanData.Get(current)
		confirm("TROCAR DE CLÃ?", `Você vai perder o clã <b>{clan.Name}</b> ({clan.Rarity}). O giro troca pelo que sair, mesmo que seja pior.`, "GIRAR", "CANCELAR", go)
	else
		go()
	end
end

-- Escolha direta (contas sem sorteio pago): confirma o preço, pede ao servidor e revela o clã escolhido
function ClanChoice.Choose()
	local clanId = ClanChoice.Selected
	local clan = ClanData.Get(clanId)
	if rolling or not clan or clanId == currentClanId() then return end
	local current = ClanData.Get(currentClanId())
	local loses = if current then ` Você deixa o clã <b>{current.Name}</b>.` else ""
	confirm("ESCOLHER CLÃ?", `Trocar para <b>{clan.Name}</b> ({clan.Rarity}) por {ClanChoice.CostText(clanId)}.{loses}`, "ESCOLHER", "CANCELAR", function()
		task.spawn(function()
			pendingResult = nil
			rolling = true
			refreshClanPage()
			clanHint.Text = "Trocando..."
			Remotes.ClanChoose:FireServer(clanId)
			local started = os.clock()
			while pendingResult == nil and os.clock() - started < ROLL_TIMEOUT do
				task.wait(0.05)
			end
			rolling = false
			local result = pendingResult
			if result then
				ClanChoice.Selected = nil
				reveal(result)
			end
			refreshClanPage()
			if result == nil then
				clanHint.Text = "O servidor não respondeu. Tente de novo."
			elseif result == false then
				clanHint.Text = "Não deu para trocar: falta Gold."
			else
				clanHint.Text = `Novo clã: <b>{ClanData.Get(result).Name}</b> ({ClanData.Get(result).Rarity}).`
			end
		end)
	end)
end

Remotes.ClanResult.OnClientEvent:Connect(function(clanId)
	pendingResult = if ClanData.Get(clanId) then clanId else false
end)
spinButton.MouseButton1Click:Connect(function()
	if spinButton.Active then
		if ClanChoice.Restricted() then
			ClanChoice.Choose()
		else
			spin()
		end
	end
end)
buyButton.MouseButton1Click:Connect(function()
	if buyButton.Active and not rolling then
		Remotes.BuySpin:FireServer()
	end
end)

-- ================= Página: códigos =================

local codesPage = makePage("CÓDIGOS", "Códigos saem nas atualizações e nos avisos do jogo")
local codeBox = round(new("TextBox", {
	Position = UDim2.fromOffset(20, 110),
	Size = UDim2.fromOffset(500, 56),
	BackgroundColor3 = CARD,
	ClearTextOnFocus = false,
	Font = Fonts.Title,
	TextSize = 22,
	TextColor3 = WHITE,
	PlaceholderText = "Digite o código",
	PlaceholderColor3 = DIM,
	Text = "",
	Parent = codesPage.Frame,
}), UDim.new(0, 6))
local codeStroke = UITheme.stroke(codeBox, LINE, 1.5)
local redeemButton = actionButton(codesPage.Frame, {
	Position = UDim2.fromOffset(20, 180),
	Size = UDim2.fromOffset(500, 50),
	Text = "RESGATAR",
	TextSize = 24,
})
local codeResult = label({
	Position = UDim2.fromOffset(24, 244),
	Size = UDim2.fromOffset(496, 44),
	TextYAlignment = Enum.TextYAlignment.Top,
	TextWrapped = true,
	Font = Fonts.Title,
	TextSize = 16,
	Parent = codesPage.Frame,
})
label({
	Position = UDim2.fromOffset(24, 300),
	Size = UDim2.fromOffset(496, 60),
	TextYAlignment = Enum.TextYAlignment.Top,
	TextWrapped = true,
	Font = Fonts.Body,
	TextSize = 13,
	TextColor3 = DIM,
	Text = "Cada código vale uma vez por conta. Os giros de clã ganhos aqui ficam guardados até você usar na aba CLÃ.",
	Parent = codesPage.Frame,
})

local redeeming = false
local function redeem()
	local code = codeBox.Text
	if redeeming or string.gsub(code, "%s", "") == "" then return end
	redeeming = true
	setButtonEnabled(redeemButton, false)
	codeResult.TextColor3 = DIM
	codeResult.Text = "Conferindo..."
	Remotes.RedeemCode:FireServer(code)
	task.delay(4, function()
		if redeeming then
			redeeming = false
			setButtonEnabled(redeemButton, true)
			codeResult.Text = "Sem resposta do servidor. Tente de novo."
		end
	end)
end
redeemButton.MouseButton1Click:Connect(redeem)
codeBox.FocusLost:Connect(function(enterPressed)
	codeStroke.Color = LINE
	if enterPressed then
		redeem()
	end
end)
codeBox.Focused:Connect(function()
	codeStroke.Color = ACCENT
end)
Remotes.CodeResult.OnClientEvent:Connect(function(ok, message)
	redeeming = false
	setButtonEnabled(redeemButton, true)
	codeResult.TextColor3 = if ok then Colors.Green else ACCENT
	codeResult.Text = tostring(message or "")
	if ok then
		codeBox.Text = ""
	end
end)

-- ================= Página: configurações =================

local settingsPage = makePage("CONFIGURAÇÕES", "Gráficos, movimento e som")
local settingsList = new("Frame", {
	Position = UDim2.fromOffset(20, 100),
	Size = UDim2.fromOffset(500, 260),
	BackgroundTransparency = 1,
	Parent = settingsPage.Frame,
})
UITheme.list(settingsList, 10)

-- Linha com interruptor: getter() diz se está ligado, toggle() troca
local toggleRefreshers = {}
local function toggleRow(order, titleText, description, getter, toggle)
	local row = round(new("TextButton", {
		Size = UDim2.fromOffset(500, 62),
		BackgroundColor3 = CARD,
		AutoButtonColor = false,
		LayoutOrder = order,
		Parent = settingsList,
	}), UDim.new(0, 6))
	UITheme.stroke(row, LINE, 1)
	label({
		Position = UDim2.fromOffset(16, 10),
		Size = UDim2.fromOffset(380, 22),
		Font = Fonts.Title,
		TextSize = 16,
		Text = titleText,
		Parent = row,
	})
	label({
		Position = UDim2.fromOffset(16, 32),
		Size = UDim2.fromOffset(380, 18),
		Font = Fonts.Body,
		TextSize = 12,
		TextColor3 = DIM,
		Text = description,
		Parent = row,
	})
	local track = round(new("Frame", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -16, 0.5, 0),
		Size = UDim2.fromOffset(54, 28),
		BackgroundColor3 = LINE,
		Parent = row,
	}), UDim.new(0.5, 0))
	local knob = round(new("Frame", {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 3, 0.5, 0),
		Size = UDim2.fromOffset(22, 22),
		BackgroundColor3 = WHITE,
		Parent = track,
	}), UDim.new(0.5, 0))
	local function refresh()
		local on = getter()
		UITheme.tween(track, 0.15, { BackgroundColor3 = if on then ACCENT else LINE })
		UITheme.tween(knob, 0.15, { Position = if on then UDim2.new(1, -25, 0.5, 0) else UDim2.new(0, 3, 0.5, 0) })
	end
	row.MouseButton1Click:Connect(function()
		toggle()
		task.defer(refresh)
	end)
	table.insert(toggleRefreshers, refresh)
	refresh()
end

-- Música do menu (LobbyMusic do SoundService, tocada pelo script de som do lobby): desligar zera o volume
local lobbyMusic = SoundService:FindFirstChild("LobbyMusic")
local musicVolume = if lobbyMusic then lobbyMusic.Volume else 0.5
local musicOn = true
local function applyMusic()
	if lobbyMusic then
		lobbyMusic.Volume = if musicOn then musicVolume else 0
	end
end

toggleRow(1, "Fast Mode", "Menos efeitos e sombras: mais FPS em PC fraco e celular", function()
	return FastMode.IsEnabled()
end, function()
	FastMode.Toggle()
end)
toggleRow(2, "Corrida automática", "Anda correndo; segure Ctrl para andar devagar", function()
	return player:GetAttribute("AutoRun") ~= false
end, function()
	local event = script.Parent:FindFirstChild("MovementAction")
	if event and event:IsA("BindableEvent") then
		event:Fire("AutoRun", player:GetAttribute("AutoRun") == false)
	end
end)
toggleRow(3, "Música do menu", "A música que toca quando você entra no jogo", function()
	return musicOn
end, function()
	musicOn = not musicOn
	applyMusic()
	Remotes.SaveSetting:FireServer("Music", musicOn)
end)
FastMode.Changed:Connect(function()
	for _, refresh in toggleRefreshers do
		refresh()
	end
end)
player:GetAttributeChangedSignal("AutoRun"):Connect(function()
	for _, refresh in toggleRefreshers do
		refresh()
	end
end)

label({
	Position = UDim2.fromOffset(24, 330),
	Size = UDim2.fromOffset(300, 20),
	Font = Fonts.Title,
	TextSize = 14,
	Text = "CONTROLES",
	Parent = settingsPage.Frame,
})
label({
	Position = UDim2.fromOffset(24, 356),
	Size = UDim2.fromOffset(496, 220),
	TextYAlignment = Enum.TextYAlignment.Top,
	TextWrapped = true,
	RichText = true,
	LineHeight = 1.25,
	Font = Fonts.Body,
	TextSize = 14,
	TextColor3 = DIM,
	Text = "<b>Clique</b>: golpes   ·   <b>F</b>: defender (parry no começo)   ·   <b>Z / X / C</b>: skills do estilo\n"
		.. "<b>Q</b>: dash   ·   <b>Ctrl</b>: andar/correr   ·   <b>Espaço</b> + 4º golpe: golpe aéreo\n"
		.. "<b>V / B</b>: poderes do caminho (level 25)   ·   <b>M</b>: árvore de habilidades   ·   <b>G</b>: inventário\n"
		.. "<b>N</b>: missões   ·   <b>E</b> perto do NPC: falar   ·   <b>1–5</b>: estilos de combate",
	Parent = settingsPage.Frame,
})

-- ================= Navegação =================

local pages = { characterPage, clanPage, codesPage, settingsPage }
local ready = false
local closing = false
local hasPlayed = false

local function refreshHome()
	local leaderstats = player:FindFirstChild("leaderstats")
	local level = leaderstats and leaderstats:FindFirstChild("Level")
	if not ready then
		statusLabel.TextColor3 = DIM
		statusLabel.Text = "Carregando seus dados..."
	elseif level then
		local info = PathData.Paths[PathData.FromPlayer(player)]
		statusLabel.TextColor3 = LIGHT
		statusLabel.Text = `Level {level.Value}  ·  <font color="#{info.Color:ToHex()}">{info.DisplayName}</font>`
	else
		statusLabel.Text = ""
	end
	playText.Text = if not isCreated() then "CRIAR PERSONAGEM" elseif hasPlayed then "VOLTAR AO JOGO" else "JOGAR"
	playText.TextSize = if isCreated() then 20 else 17
	local spins = spinsLeft()
	spinBadge.Visible = spins > 0
	spinBadgeText.Text = if spins > 99 then "99+" else tostring(spins)
	refreshClanLine()
end

local function slideIn(frame)
	local target = frame.Position
	frame.Position = target - UDim2.fromOffset(30, 0)
	frame.Visible = true
	UITheme.tween(frame, 0.25, { Position = target }, Enum.EasingStyle.Quint)
end

local function hideAll()
	home.Visible = false
	for _, page in pages do
		page.Frame.Visible = false
	end
	continueButton.Visible = false
end

-- Controle (Xbox): a tela inicial já começa com o JOGAR selecionado (A aperta; analógico/direcional navega)
local GuiService = game:GetService("GuiService")
local function usingGamepad()
	return string.sub(UserInputService:GetLastInputType().Name, 1, 7) == "Gamepad"
end

local function showHome()
	if rolling then return end
	hideAll()
	draft = readAppearance()
	applyDraftToPreview()
	previewSpin = true
	setCamera(CAMERA_FULL)
	refreshHome()
	slideIn(home)
	if usingGamepad() then
		GuiService.SelectedObject = playButton
	end
end

local function showCharacter(creationMode)
	hideAll()
	creating = creationMode == true
	characterPage.Title.Text = if creating then "CRIE SEU PERSONAGEM" else "PERSONAGEM"
	characterPage.Subtitle.Text = if creating then "Escolha o visual do seu caçador. Dá para mudar depois no menu." else "Monte o visual do seu caçador"
	characterPage.Close.Visible = not creating
	saveButton.Text = if creating then "CRIAR" else "SALVAR"
	draft = readAppearance()
	applyDraftToPreview()
	previewSpin = false
	previewYaw = math.pi
	for _, refresh in sectionRefreshers do
		refresh()
	end
	refreshDirty()
	selectTab(currentTab)
	slideIn(characterPage.Frame)
end

local function showClanPage(revealMode)
	hideAll()
	revealing = revealMode == true
	clanPage.Title.Text = if revealing then "SEU CLÃ" else "CLÃ"
	clanPage.Subtitle.Text = if revealing then "O sobrenome que você recebeu ao nascer" else "Seu sobrenome dá um bônus pequeno para sempre"
	clanPage.Close.Visible = not revealing
	continueButton.Visible = revealing
	previewSpin = true
	setCamera(CAMERA_FULL)
	refreshClanPage()
	slideIn(clanPage.Frame)
	if revealing then
		-- Roleta de mentira até o clã que já saiu no primeiro acesso
		pendingResult = currentClanId() or false
		task.spawn(runReel, function(result)
			local clan = ClanData.Get(result)
			if clan then
				clanHint.Text = `Você nasceu no clã <b>{clan.Name}</b>. Tem <b>{spinsLeft()}</b> giros para tentar outro quando quiser.`
			end
		end)
	end
end

local function showSimplePage(page)
	hideAll()
	previewSpin = true
	setCamera(CAMERA_FULL)
	slideIn(page.Frame)
end

local function leaveCharacterPage()
	if creating then return end
	if refreshDirty() then
		confirm("SAIR SEM SALVAR?", "As mudanças no visual vão se perder.", "SALVAR", "DESCARTAR", function()
			Remotes.SaveAppearance:FireServer(draft)
			showHome()
		end, function()
			showHome()
		end)
	else
		showHome()
	end
end

characterPage.Close.MouseButton1Click:Connect(leaveCharacterPage)
clanPage.Close.MouseButton1Click:Connect(showHome)
codesPage.Close.MouseButton1Click:Connect(showHome)
settingsPage.Close.MouseButton1Click:Connect(showHome)
continueButton.MouseButton1Click:Connect(function()
	if not rolling then
		revealing = false
		showHome()
	end
end)

randomButton.MouseButton1Click:Connect(function()
	local random = AppearanceData.Random()
	for field in AppearanceData.Fields do
		draft[field] = random[field]
	end
	applyDraftToPreview()
	for _, refresh in sectionRefreshers do
		refresh()
	end
	refreshDirty()
end)

local saving = false
saveButton.MouseButton1Click:Connect(function()
	if saving then return end
	saving = true
	local wasCreating = creating
	Remotes.SaveAppearance:FireServer(draft)
	saveButton.Text = "SALVO!"
	-- Espera o servidor confirmar (atributos Appearance/CharacterCreated)
	local deadline = os.clock() + 3
	while os.clock() < deadline and (not isCreated() or not sameAppearance(draft, readAppearance())) do
		task.wait(0.1)
	end
	task.wait(if wasCreating then 0.3 else 1.4)
	saving = false
	saveButton.Text = if creating then "CRIAR" else "SALVAR"
	refreshDirty()
	if wasCreating and characterPage.Frame.Visible then
		creating = false
		showClanPage(true)
	end
end)

characterButton.MouseButton1Click:Connect(function()
	showCharacter(not isCreated())
end)
clanButton.MouseButton1Click:Connect(function()
	showClanPage(false)
end)
codesButton.MouseButton1Click:Connect(function()
	codeResult.Text = ""
	showSimplePage(codesPage)
end)
-- A loja de passes é do GamepassShop (ScreenGui por cima do menu); ela escuta o BindableEvent "Toggle"
passesButton.MouseButton1Click:Connect(function()
	local shop = playerGui:FindFirstChild("GamepassShop")
	local toggle = shop and shop:FindFirstChild("Toggle")
	if toggle and toggle:IsA("BindableEvent") then
		toggle:Fire()
	end
end)
settingsButton.MouseButton1Click:Connect(function()
	for _, refresh in toggleRefreshers do
		refresh()
	end
	showSimplePage(settingsPage)
end)

-- ================= Abrir e fechar =================

local controls -- ControlModule do PlayerModule (desliga o movimento com o menu aberto)
local function setControlsEnabled(enabled)
	task.spawn(function()
		if controls == nil then
			local playerScripts = player:WaitForChild("PlayerScripts")
			local module = playerScripts:WaitForChild("PlayerModule", 10)
			local ok, result = pcall(function()
				return require(module):GetControls()
			end)
			controls = if ok and result then result else false
		end
		if controls then
			if enabled then
				controls:Enable()
			else
				controls:Disable()
			end
		end
	end)
end

local function setMenuState(open)
	player:SetAttribute("MenuOpen", if open then true else nil)
	setControlsEnabled(not open)
end

local function fadeCurtain(target, time)
	UITheme.tween(curtain, time, { BackgroundTransparency = target }).Completed:Wait()
end

local function play()
	if closing or not ready or not screen.Enabled or rolling then return end
	if not isCreated() then
		showCharacter(true)
		return
	end
	closing = true
	fadeCurtain(0, 0.22)
	screen.Enabled = false
	if GuiService.SelectedObject and GuiService.SelectedObject:IsDescendantOf(screen) then
		GuiService.SelectedObject = nil
	end
	setMenuState(false)
	hasPlayed = true
	fadeCurtain(1, 0.35)
	closing = false
end

playButton.MouseButton1Click:Connect(function()
	task.spawn(play)
end)

-- Enter joga (só na tela inicial e sem estar digitando)
UserInputService.InputBegan:Connect(function(input, processed)
	if processed or not screen.Enabled then return end
	if (input.KeyCode == Enum.KeyCode.Return or input.KeyCode == Enum.KeyCode.KeypadEnter) and home.Visible then
		task.spawn(play)
	end
end)

openEvent.Event:Connect(function()
	if screen.Enabled or closing then return end
	closing = true
	fadeCurtain(0, 0.2)
	screen.Enabled = true
	setMenuState(true)
	buildPreview()
	showHome()
	fadeCurtain(1, 0.3)
	closing = false
end)

-- ================= Atualizações =================

player:GetAttributeChangedSignal("Clan"):Connect(function()
	refreshClanLine()
	if clanPage.Frame.Visible then
		refreshClanPage()
	end
end)
player:GetAttributeChangedSignal("RandomItemsRestricted"):Connect(function()
	if clanPage.Frame.Visible then
		refreshClanPage()
	end
end)
player:GetAttributeChangedSignal("ClanSpins"):Connect(function()
	refreshHome()
	if clanPage.Frame.Visible then
		refreshClanPage()
	end
end)
player:GetAttributeChangedSignal("CharacterCreated"):Connect(refreshHome)
player:GetAttributeChangedSignal("Path"):Connect(refreshHome)
player:GetAttributeChangedSignal("SettingMusic"):Connect(function()
	musicOn = player:GetAttribute("SettingMusic") ~= false
	applyMusic()
end)
if player:GetAttribute("SettingMusic") ~= nil then
	musicOn = player:GetAttribute("SettingMusic") ~= false
	applyMusic()
end

task.spawn(function()
	-- O perfil só carrega depois da tela de saves (SaveSelect.client): espera a escolha antes de contar o tempo
	while player:GetAttribute("SaveSlot") == nil do
		player:GetAttributeChangedSignal("SaveSlot"):Wait()
	end
	local leaderstats = player:WaitForChild("leaderstats", LOAD_TIMEOUT)
	if leaderstats then
		leaderstats:WaitForChild("Level", 5)
		local gold = leaderstats:WaitForChild("Gold", 5)
		if gold then
			gold.Changed:Connect(function()
				if clanPage.Frame.Visible then
					refreshClanPage()
				end
			end)
		end
		local level = leaderstats:FindFirstChild("Level")
		if level then
			level.Changed:Connect(refreshHome)
		end
	end
	-- Aparência e clã chegam logo depois do perfil (CharacterService)
	local deadline = os.clock() + 5
	while player:GetAttribute("CharacterCreated") == nil and os.clock() < deadline do
		task.wait(0.1)
	end
	ready = true
	refreshHome()
end)

-- A prévia acompanha o personagem (ao renascer o servidor veste a aparência de novo)
player.CharacterAdded:Connect(function(character)
	character:WaitForChild("Head", 10)
	task.wait(0.5)
	if screen.Enabled then
		buildPreview()
	end
end)

-- ================= Entrada =================

setMenuState(true)
selectTab(currentTab, true)
if not game:IsLoaded() then
	game.Loaded:Wait()
end

-- Espera a tela de carregamento sair (ela fica por cima desta até tudo estar pronto)
local loadingDeadline = os.clock() + 40
while playerGui:FindFirstChild("LoadingScreen") and os.clock() < loadingDeadline do
	task.wait(0.05)
end
while player:GetAttribute("SaveSlot") == nil do
	player:GetAttributeChangedSignal("SaveSlot"):Wait()
end
local dataDeadline = os.clock() + LOAD_TIMEOUT
while not ready and os.clock() < dataDeadline do
	task.wait(0.1)
end
ready = true

content.Visible = true
if not player.Character then
	player.CharacterAdded:Wait()
end
if player.Character then
	player.Character:WaitForChild("Head", 10)
end
buildPreview()

if isCreated() then
	showHome()
	logoScale.Scale = 0.7
	UITheme.tween(logoScale, 0.45, { Scale = 1 }, Enum.EasingStyle.Back)
	-- Botões entrando um por um
	for index, button in { playButton, characterButton, clanButton, codesButton, passesButton, settingsButton } do
		local scale = button:FindFirstChildOfClass("UIScale") or new("UIScale", { Parent = button })
		scale.Scale = 0.6
		task.delay(0.08 * index, function()
			UITheme.tween(scale, 0.35, { Scale = 1 }, Enum.EasingStyle.Back)
		end)
	end
else
	showCharacter(true)
end
