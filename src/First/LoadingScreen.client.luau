
local ContentProvider = game:GetService("ContentProvider")
local Players = game:GetService("Players")
local ReplicatedFirst = game:GetService("ReplicatedFirst")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- Mesmas cores e fontes do UITheme
local BACKGROUND = Color3.fromRGB(8, 6, 7)
local PANEL = Color3.fromRGB(17, 12, 13)
local ACCENT = Color3.fromRGB(214, 22, 32)
local ORANGE = Color3.fromRGB(255, 122, 24)
local GOLD = Color3.fromRGB(255, 204, 36)
local TEXT = Color3.fromRGB(242, 236, 226)
local TEXT_DIM = Color3.fromRGB(172, 160, 152)
local FONT_DISPLAY = Enum.Font.GothamBlack
local FONT_HORROR = Enum.Font.Creepster
local FONT_TITLE = Enum.Font.GothamBold
local FONT_BODY = Enum.Font.GothamMedium

local TOTAL_TIMEOUT = 30 -- nunca prende o jogador mais que isso
local SKIP_AFTER = 12 -- o botão PULAR aparece depois desse tempo

local TIPS = {
	"Segure F logo antes do golpe inimigo para dar um parry.",
	"Pule e dê o 4º soco do combo para lançar o inimigo para cima.",
	"Segure X para carregar o soco. Carregado no máximo, ele quebra a guarda.",
	"No level 25 você escolhe seu caminho: Caçador ou Infernal.",
	"Aperte M para distribuir seus pontos de status.",
	"Aperte N para ver suas missões.",
	"Q dá um dash; segure Ctrl para correr.",
	"Golpes pelas costas atravessam a guarda.",
}

local function new(className, props)
	local instance = Instance.new(className)
	local parent = props.Parent
	props.Parent = nil
	for key, value in props do
		instance[key] = value
	end
	instance.Parent = parent
	return instance
end

local function tween(instance, time, props, style)
	local t = TweenService:Create(instance, TweenInfo.new(time, style or Enum.EasingStyle.Quad, Enum.EasingDirection.Out), props)
	t:Play()
	return t
end

-- ================= Tela =================

local screenGui = new("ScreenGui", {
	Name = "LoadingScreen",
	IgnoreGuiInset = true,
	ResetOnSpawn = false,
	DisplayOrder = 100,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	Parent = playerGui,
})

ReplicatedFirst:RemoveDefaultLoadingScreen()

local background = new("Frame", {
	Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = Color3.fromRGB(75, 8, 12),
	BorderSizePixel = 0,
	Parent = screenGui,
})
new("UIGradient", {
	Rotation = 90,
	Color = ColorSequence.new(Color3.fromRGB(20, 20, 20), Color3.fromRGB(255, 255, 255)),
	Parent = background,
})

-- Faixas diagonais (as mesmas da tela de título), deslizando devagar
local stripes = {}
for _, info in {
	{ Y = 0.18, Height = 5, Transparency = 0.75, Speed = 0.012 },
	{ Y = 0.22, Height = 2, Transparency = 0.85, Speed = -0.02 },
	{ Y = 0.82, Height = 7, Transparency = 0.7, Speed = -0.01 },
	{ Y = 0.87, Height = 3, Transparency = 0.85, Speed = 0.018 },
} do
	local stripe = new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, info.Y),
		Size = UDim2.new(1.6, 0, 0, info.Height),
		Rotation = -8,
		BackgroundColor3 = ACCENT,
		BackgroundTransparency = info.Transparency,
		BorderSizePixel = 0,
		Parent = background,
	})
	table.insert(stripes, { Frame = stripe, Info = info })
end

local CONTENT_W, CONTENT_H = 700, 420
local content = new("Frame", {
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromOffset(CONTENT_W, CONTENT_H),
	BackgroundTransparency = 1,
	Parent = background,
})
local contentScale = new("UIScale", { Parent = content })
local function rescale()
	local camera = workspace.CurrentCamera
	local viewport = if camera then camera.ViewportSize else Vector2.new(1280, 720)
	contentScale.Scale = math.clamp(math.min(viewport.X / (CONTENT_W + 40), viewport.Y / (CONTENT_H + 40)), 0.45, 1.2)
end
rescale()

-- Serra girando (anel com um degradê que dá a volta)
local sawSize = 96
local saw = new("Frame", {
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 0),
	Size = UDim2.fromOffset(sawSize, sawSize),
	BackgroundTransparency = 1,
	Parent = content,
})
new("UICorner", { CornerRadius = UDim.new(0.5, 0), Parent = saw })
local sawStroke = new("UIStroke", { Color = ORANGE, Thickness = 6, Parent = saw })
local sawGradient = new("UIGradient", {
	Color = ColorSequence.new(ACCENT, GOLD),
	Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.55, 0.1),
		NumberSequenceKeypoint.new(0.75, 1),
		NumberSequenceKeypoint.new(1, 1),
	}),
	Parent = sawStroke,
})
local sawCore = new("Frame", {
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromOffset(sawSize * 0.42, sawSize * 0.42),
	BackgroundColor3 = ACCENT,
	Parent = saw,
})
new("UICorner", { CornerRadius = UDim.new(0.5, 0), Parent = sawCore })
new("UIStroke", { Color = Color3.fromRGB(0, 0, 0), Thickness = 3, Transparency = 0.3, Parent = sawCore })

-- Nome do jogo: fonte de terror, amarelo do logo e contorno preto
local title = new("TextLabel", {
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, sawSize + 18),
	Size = UDim2.fromOffset(CONTENT_W, 80),
	BackgroundTransparency = 1,
	Font = FONT_HORROR,
	TextSize = 72,
	TextColor3 = GOLD,
	Text = "CHAINSAW DEMONS",
	Parent = content,
})
new("UIStroke", { Color = Color3.fromRGB(0, 0, 0), Thickness = 5, Parent = title })

-- Dentes de motosserra nas bordas de cima e de baixo (a "mandíbula")
for _, edge in { "Top", "Bottom" } do
	local top = edge == "Top"
	local holder = new("Frame", {
		AnchorPoint = Vector2.new(0, if top then 0 else 1),
		Position = UDim2.fromScale(0, if top then 0 else 1),
		Size = UDim2.new(1, 0, 0, 22),
		BackgroundTransparency = 1,
		ClipsDescendants = true,
		Parent = background,
	})
	new("TextLabel", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = if top then Enum.TextYAlignment.Top else Enum.TextYAlignment.Bottom,
		Font = FONT_DISPLAY,
		TextSize = 28,
		TextColor3 = Color3.fromRGB(96, 6, 10),
		Text = string.rep(if top then "▼" else "▲", 320),
		Parent = holder,
	})
end

-- Barra de progresso
local BAR_W = 460
local statusLabel = new("TextLabel", {
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, sawSize + 116),
	Size = UDim2.fromOffset(BAR_W, 22),
	BackgroundTransparency = 1,
	Font = FONT_TITLE,
	TextSize = 16,
	TextColor3 = TEXT_DIM,
	TextXAlignment = Enum.TextXAlignment.Left,
	Text = "Iniciando...",
	Parent = content,
})
local percentLabel = new("TextLabel", {
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, sawSize + 116),
	Size = UDim2.fromOffset(BAR_W, 22),
	BackgroundTransparency = 1,
	Font = FONT_DISPLAY,
	TextSize = 16,
	TextColor3 = GOLD,
	TextXAlignment = Enum.TextXAlignment.Right,
	Text = "0%",
	Parent = content,
})
local barTrack = new("Frame", {
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, sawSize + 144),
	Size = UDim2.fromOffset(BAR_W, 14),
	BackgroundColor3 = PANEL,
	BorderSizePixel = 0,
	Parent = content,
})
new("UICorner", { CornerRadius = UDim.new(0, 7), Parent = barTrack })
new("UIStroke", { Color = Color3.fromRGB(0, 0, 0), Thickness = 2, Parent = barTrack })
local barFill = new("Frame", {
	Size = UDim2.fromScale(0, 1),
	BackgroundColor3 = TEXT,
	BorderSizePixel = 0,
	Parent = barTrack,
})
new("UICorner", { CornerRadius = UDim.new(0, 7), Parent = barFill })
new("UIGradient", { Color = ColorSequence.new(ACCENT, ORANGE), Parent = barFill })
-- Brilho que corre por cima da barra
local barShine = new("Frame", {
	Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = TEXT,
	BackgroundTransparency = 0,
	BorderSizePixel = 0,
	Parent = barFill,
})
new("UICorner", { CornerRadius = UDim.new(0, 7), Parent = barShine })
local shineGradient = new("UIGradient", {
	Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.45, 1),
		NumberSequenceKeypoint.new(0.5, 0.55),
		NumberSequenceKeypoint.new(0.55, 1),
		NumberSequenceKeypoint.new(1, 1),
	}),
	Parent = barShine,
})

local tipLabel = new("TextLabel", {
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, 0),
	Size = UDim2.fromOffset(CONTENT_W, 44),
	BackgroundTransparency = 1,
	Font = FONT_BODY,
	TextSize = 16,
	TextColor3 = TEXT_DIM,
	TextWrapped = true,
	RichText = true,
	Text = "",
	Parent = content,
})

local skipButton = new("TextButton", {
	AnchorPoint = Vector2.new(1, 1),
	Position = UDim2.new(1, -24, 1, -24),
	Size = UDim2.fromOffset(120, 40),
	BackgroundColor3 = PANEL,
	AutoButtonColor = true,
	Font = FONT_TITLE,
	TextSize = 16,
	TextColor3 = TEXT,
	Text = "PULAR ▶",
	Visible = false,
	Parent = background,
})
new("UICorner", { CornerRadius = UDim.new(0, 8), Parent = skipButton })
new("UIStroke", { Color = Color3.fromRGB(75, 75, 85), Thickness = 1.5, ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Parent = skipButton })

-- ================= Animação da tela =================

local target = 0 -- progresso real (0 a 1)
local shown = 0 -- progresso mostrado (anda suave até o real)
local skipped = false
local startTime = os.clock()

local renderConnection = RunService.RenderStepped:Connect(function(dt)
	local elapsed = os.clock() - startTime
	sawGradient.Rotation = (elapsed * 360) % 360
	shineGradient.Offset = Vector2.new(((elapsed * 0.6) % 1.6) - 0.8, 0)
	for _, stripe in stripes do
		stripe.Frame.Position = UDim2.fromScale(0.5 + math.sin(elapsed * 0.4) * stripe.Info.Speed * 4, stripe.Info.Y)
	end
	shown += (target - shown) * math.min(1, dt * 6)
	if target - shown < 0.002 then
		shown = target
	end
	barFill.Size = UDim2.fromScale(shown, 1)
	percentLabel.Text = `{math.floor(shown * 100 + 0.5)}%`
	rescale()
end)

-- Dicas trocando
task.spawn(function()
	local order = {}
	for index in TIPS do
		table.insert(order, index)
	end
	for i = #order, 2, -1 do
		local j = math.random(1, i)
		order[i], order[j] = order[j], order[i]
	end
	local index = 0
	while screenGui.Parent do
		index = index % #order + 1
		tipLabel.TextTransparency = 1
		tipLabel.Text = `<font color="#{GOLD:ToHex()}">DICA</font>  {TIPS[order[index]]}`
		tween(tipLabel, 0.4, { TextTransparency = 0 })
		task.wait(4.5)
		if not screenGui.Parent then break end
		tween(tipLabel, 0.3, { TextTransparency = 1 })
		task.wait(0.3)
	end
end)

task.delay(SKIP_AFTER, function()
	if screenGui.Parent then
		skipButton.Visible = true
	end
end)
skipButton.MouseButton1Click:Connect(function()
	skipped = true
end)

-- ================= Etapas do carregamento =================

local function timeLeft()
	return TOTAL_TIMEOUT - (os.clock() - startTime)
end

-- Espera a condição (ou o PULAR, ou o tempo limite da etapa / total)
local function waitUntil(condition, timeout)
	local deadline = os.clock() + math.min(timeout, math.max(0, timeLeft()))
	while not condition() and not skipped and os.clock() < deadline do
		task.wait(0.05)
	end
	return condition()
end

local function stage(text, from, to)
	statusLabel.Text = text
	target = math.max(target, from)
	return function(fraction)
		target = math.max(target, from + (to - from) * math.clamp(fraction, 0, 1))
	end
end

-- 1. Mapa e assets (a fila do ContentProvider esvaziando)
do
	local progress = stage("Carregando o mapa...", 0, 0.55)
	local biggestQueue = 1
	waitUntil(function()
		local queue = ContentProvider.RequestQueueSize
		biggestQueue = math.max(biggestQueue, queue)
		progress(if game:IsLoaded() then 1 else 0.9 * (1 - queue / biggestQueue))
		return game:IsLoaded()
	end, 20)
	progress(1)
end

-- 2. Animações e sons do combate (pré-carregados para não saírem atrasados na primeira vez)
do
	local progress = stage("Preparando animações e sons...", 0.55, 0.7)
	local ids, soundIds = {}, {}
	local function add(value, into)
		if type(value) == "number" and value > 0 then
			into[value] = true
		elseif type(value) == "table" then
			for _, inner in value do
				add(inner, into)
			end
		end
	end
	local combatModule = ReplicatedStorage:WaitForChild("CombatStyles", math.max(0.1, math.min(5, timeLeft())))
	local characterModule = ReplicatedStorage:WaitForChild("CharacterAnimations", math.max(0.1, math.min(5, timeLeft())))
	pcall(function()
		if combatModule then
			for _, style in require(combatModule).Styles do
				add(style.Animations, ids)
				add(style.Sounds, soundIds)
			end
		end
		if characterModule then
			local animations = require(characterModule)
			add(animations.Default, ids)
			add(animations.Movement, ids)
		end
	end)

	local assets = {}
	for id in ids do
		local animation = Instance.new("Animation")
		animation.AnimationId = "rbxassetid://" .. id
		table.insert(assets, animation)
	end
	for id in soundIds do
		local sound = Instance.new("Sound")
		sound.SoundId = "rbxassetid://" .. id
		table.insert(assets, sound)
	end
	if #assets > 0 and not skipped then
		local done = 0
		pcall(function()
			ContentProvider:PreloadAsync(assets, function()
				done += 1
				progress(done / #assets)
			end)
		end)
	end
	progress(1)
end

-- 3. Personagem
do
	stage("Criando seu personagem...", 0.7, 0.8)
	waitUntil(function()
		return player.Character ~= nil
	end, 15)
end

-- 4. Dados salvos (o servidor cria o leaderstats depois de carregar o perfil) e caminho
do
	local progress = stage("Carregando seus dados...", 0.8, 0.95)
	waitUntil(function()
		local leaderstats = player:FindFirstChild("leaderstats")
		return leaderstats ~= nil and leaderstats:FindFirstChild("Level") ~= nil
	end, 15)
	progress(0.6)
	waitUntil(function()
		return player:GetAttribute("Path") ~= nil
	end, 3)
	progress(1)
end

-- 5. Tela de título pronta por baixo
do
	stage("Quase lá...", 0.95, 1)
	waitUntil(function()
		return playerGui:FindFirstChild("TitleScreen") ~= nil
	end, 10)
end

-- ================= Saída =================

statusLabel.Text = "Pronto!"
statusLabel.TextColor3 = GOLD
target = 1
task.wait(0.35)

skipButton.Visible = false
local fadeTime = 0.5
for _, object in screenGui:GetDescendants() do
	if object:IsA("TextLabel") or object:IsA("TextButton") then
		tween(object, fadeTime * 0.6, { TextTransparency = 1, TextStrokeTransparency = 1, BackgroundTransparency = 1 })
	elseif object:IsA("UIStroke") then
		tween(object, fadeTime * 0.6, { Transparency = 1 })
	elseif object:IsA("Frame") then
		tween(object, fadeTime, { BackgroundTransparency = 1 })
	end
end
task.wait(fadeTime)
renderConnection:Disconnect()
screenGui:Destroy()
