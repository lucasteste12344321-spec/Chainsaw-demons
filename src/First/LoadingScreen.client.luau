
local ContentProvider = game:GetService("ContentProvider")
local Players = game:GetService("Players")
local ReplicatedFirst = game:GetService("ReplicatedFirst")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- Tela de carregamento (refeita em 2026-10-05, pedido do usuário: mais compacta e bonita). Mesmo visual do menu
-- principal, que vem logo depois: grafite, brilho laranja e Builder Sans; o nome do jogo na fonte de terror.
-- (ReplicatedFirst roda antes do UITheme existir: as cores ficam aqui.)
local PANEL = Color3.fromRGB(26, 26, 30)
local ORANGE = Color3.fromRGB(255, 122, 26) -- o laranja do menu principal
local ORANGE_DARK = Color3.fromRGB(128, 52, 8)
local TEXT = Color3.fromRGB(242, 242, 245)
local TEXT_DIM = Color3.fromRGB(158, 158, 166)
local FONT_HORROR = Enum.Font.Creepster
local FONT_HEAVY = Enum.Font.BuilderSansExtraBold
local FONT_BOLD = Enum.Font.BuilderSansBold
local FONT_BODY = Enum.Font.BuilderSansMedium

local TOTAL_TIMEOUT = 30 -- nunca prende o jogador mais que isso
local SKIP_AFTER = 12 -- o botão PULAR aparece depois desse tempo

local TIPS = {
	"Raise your guard (F) right before an enemy hit lands to parry it.",
	"Jump and land the 4th punch of the combo to launch the enemy upward.",
	"Hold X to charge your punch. At full charge it breaks guards.",
	"At level 25 you choose your path: Hunter or Fiend.",
	"Press M to open the skill tree and spend your points.",
	"Press G to open the inventory and wear boss items.",
	"Press N to collapse or expand the quest list.",
	"Q dashes. Running is automatic; hold Ctrl to walk.",
	"Hits from behind go through guards.",
	"Getting comboed? The dash breaks the combo even while stunned.",
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
	BackgroundColor3 = Color3.fromRGB(62, 62, 68),
	BorderSizePixel = 0,
	Parent = screenGui,
})
new("UIGradient", {
	Rotation = 90,
	Color = ColorSequence.new(Color3.fromRGB(50, 50, 55), Color3.fromRGB(180, 180, 188)),
	Parent = background,
})
-- Brilho laranja no meio: círculos quase transparentes um dentro do outro (respira devagar)
local glowRings = {}
for index = 1, 6 do
	local size = 1 - (index - 1) * 0.14
	local ring = new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.45),
		Size = UDim2.fromScale(0.62 * size, 1.1 * size),
		BackgroundColor3 = ORANGE,
		BackgroundTransparency = 0.965,
		BorderSizePixel = 0,
		Parent = background,
	})
	new("UICorner", { CornerRadius = UDim.new(0.5, 0), Parent = ring })
	table.insert(glowRings, ring)
end

local CONTENT_W, CONTENT_H = 520, 300
local content = new("Frame", {
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.48),
	Size = UDim2.fromOffset(CONTENT_W, CONTENT_H),
	BackgroundTransparency = 1,
	Parent = background,
})
local contentScale = new("UIScale", { Parent = content })
local function rescale()
	local camera = workspace.CurrentCamera
	local viewport = if camera then camera.ViewportSize else Vector2.new(1280, 720)
	contentScale.Scale = math.clamp(math.min(viewport.X / (CONTENT_W + 40), viewport.Y / (CONTENT_H + 120)), 0.5, 1.15)
end
rescale()

-- Nome do jogo: fonte de terror, branco com contorno preto e um sublinhado laranja
local title = new("TextLabel", {
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 40),
	Size = UDim2.fromOffset(CONTENT_W, 64),
	BackgroundTransparency = 1,
	Font = FONT_HORROR,
	TextSize = 60,
	TextColor3 = TEXT,
	Text = "CHAINSAW DEMONS",
	Parent = content,
})
new("UIStroke", { Color = Color3.fromRGB(0, 0, 0), Thickness = 4, Parent = title })
local underline = new("Frame", {
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 112),
	Size = UDim2.fromOffset(64, 3),
	BackgroundColor3 = ORANGE,
	BorderSizePixel = 0,
	Parent = content,
})
new("UICorner", { CornerRadius = UDim.new(0.5, 0), Parent = underline })

-- Barra de progresso fina, com o status à esquerda (e um anel girando) e a porcentagem à direita
local BAR_W = 340
local BAR_Y = 176
local spinner = new("Frame", {
	AnchorPoint = Vector2.new(0, 0.5),
	Position = UDim2.new(0.5, -BAR_W / 2, 0, BAR_Y - 14),
	Size = UDim2.fromOffset(12, 12),
	BackgroundTransparency = 1,
	Parent = content,
})
new("UICorner", { CornerRadius = UDim.new(0.5, 0), Parent = spinner })
local spinnerStroke = new("UIStroke", { Color = ORANGE, Thickness = 2, Parent = spinner })
local sawGradient = new("UIGradient", {
	Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.6, 0.2),
		NumberSequenceKeypoint.new(0.75, 1),
		NumberSequenceKeypoint.new(1, 1),
	}),
	Parent = spinnerStroke,
})
local statusLabel = new("TextLabel", {
	AnchorPoint = Vector2.new(0, 0.5),
	Position = UDim2.new(0.5, -BAR_W / 2 + 20, 0, BAR_Y - 14),
	Size = UDim2.fromOffset(BAR_W - 70, 18),
	BackgroundTransparency = 1,
	Font = FONT_BOLD,
	TextSize = 14,
	TextColor3 = TEXT_DIM,
	TextXAlignment = Enum.TextXAlignment.Left,
	Text = "Iniciando...",
	Parent = content,
})
local percentLabel = new("TextLabel", {
	AnchorPoint = Vector2.new(1, 0.5),
	Position = UDim2.new(0.5, BAR_W / 2, 0, BAR_Y - 14),
	Size = UDim2.fromOffset(60, 18),
	BackgroundTransparency = 1,
	Font = FONT_HEAVY,
	TextSize = 14,
	TextColor3 = TEXT,
	TextXAlignment = Enum.TextXAlignment.Right,
	Text = "0%",
	Parent = content,
})
local barTrack = new("Frame", {
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, BAR_Y),
	Size = UDim2.fromOffset(BAR_W, 4),
	BackgroundColor3 = PANEL,
	BackgroundTransparency = 0.2,
	BorderSizePixel = 0,
	ClipsDescendants = true,
	Parent = content,
})
new("UICorner", { CornerRadius = UDim.new(0.5, 0), Parent = barTrack })
local barFill = new("Frame", {
	Size = UDim2.fromScale(0, 1),
	BackgroundColor3 = TEXT,
	BorderSizePixel = 0,
	Parent = barTrack,
})
new("UICorner", { CornerRadius = UDim.new(0.5, 0), Parent = barFill })
new("UIGradient", { Color = ColorSequence.new(ORANGE_DARK, ORANGE), Parent = barFill })
-- Brilho que corre por cima da barra
local barShine = new("Frame", {
	Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = TEXT,
	BackgroundTransparency = 0,
	BorderSizePixel = 0,
	Parent = barFill,
})
local shineGradient = new("UIGradient", {
	Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.45, 1),
		NumberSequenceKeypoint.new(0.5, 0.5),
		NumberSequenceKeypoint.new(0.55, 1),
		NumberSequenceKeypoint.new(1, 1),
	}),
	Parent = barShine,
})

-- Dica embaixo, num cartão escuro discreto
local tipLabel = new("TextLabel", {
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, BAR_Y + 40),
	Size = UDim2.fromOffset(CONTENT_W - 40, 40),
	BackgroundTransparency = 1,
	Font = FONT_BODY,
	TextSize = 14,
	TextColor3 = TEXT_DIM,
	TextWrapped = true,
	RichText = true,
	Text = "",
	Parent = content,
})

local skipButton = new("TextButton", {
	AnchorPoint = Vector2.new(1, 1),
	Position = UDim2.new(1, -20, 1, -20),
	Size = UDim2.fromOffset(96, 32),
	BackgroundColor3 = PANEL,
	BackgroundTransparency = 0.2,
	AutoButtonColor = true,
	Font = FONT_BOLD,
	TextSize = 14,
	TextColor3 = TEXT,
	Text = "SKIP",
	Visible = false,
	Parent = background,
})
new("UICorner", { CornerRadius = UDim.new(0.5, 0), Parent = skipButton })
new("UIStroke", { Color = TEXT, Thickness = 1, Transparency = 0.85, ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Parent = skipButton })

-- ================= Animação da tela =================

local target = 0 -- progresso real (0 a 1)
local shown = 0 -- progresso mostrado (anda suave até o real)
local skipped = false
local startTime = os.clock()

local fading = false -- na saída o brilho para de "respirar" (senão brigava com o fade)
local renderConnection = RunService.RenderStepped:Connect(function(dt)
	local elapsed = os.clock() - startTime
	sawGradient.Rotation = (elapsed * 420) % 360
	shineGradient.Offset = Vector2.new(((elapsed * 0.6) % 1.6) - 0.8, 0)
	if not fading then
		local breath = 0.965 + math.sin(elapsed * 1.6) * 0.006
		for _, ring in glowRings do
			ring.BackgroundTransparency = breath
		end
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
		tipLabel.Text = `<font color="#{ORANGE:ToHex()}"><b>TIP</b></font>   {TIPS[order[index]]}`
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
	local progress = stage("Loading the map...", 0, 0.55)
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
	local progress = stage("Preparing animations and sounds...", 0.55, 0.7)
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
	stage("Creating your character...", 0.7, 0.8)
	waitUntil(function()
		return player.Character ~= nil
	end, 15)
end

-- 4. Saves: o perfil só carrega depois da escolha na tela de saves (SaveSelect.client, por baixo desta). Espera a
-- tela de saves existir (ou os dados, se o save já foi escolhido) e sai: a escolha acontece com esta tela fora.
do
	local progress = stage("Loading your saves...", 0.8, 0.95)
	waitUntil(function()
		local leaderstats = player:FindFirstChild("leaderstats")
		return (leaderstats ~= nil and leaderstats:FindFirstChild("Level") ~= nil)
			or playerGui:FindFirstChild("SaveSelect") ~= nil
	end, 15)
	progress(1)
end

-- 5. Tela de título pronta por baixo
do
	stage("Almost there...", 0.95, 1)
	waitUntil(function()
		return playerGui:FindFirstChild("TitleScreen") ~= nil
	end, 10)
end

-- ================= Saída =================

statusLabel.Text = "Pronto!"
statusLabel.TextColor3 = ORANGE
target = 1
task.wait(0.35)

skipButton.Visible = false
fading = true
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
