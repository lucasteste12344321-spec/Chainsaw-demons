-- Aparelho do caminho: o TABLET do Caçador (e do Humano, antes de escolher) ou a KOGANE do Infernal. Mostra as missões
-- diárias (DailyService, Remotes.DailyAction/DailyState) e o chefe global (atributos GlobalBoss_* do ReplicatedStorage,
-- escritos pelo BossService), e é por ele que chegam os avisos do chefe (Remotes.DeviceAlert).
-- Abre com T, pelo botão da HUD (HUB_GUI) ou pelo BindableEvent Device.Toggle.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local UI = require(ReplicatedStorage:WaitForChild("UITheme"))
local Remotes = require(ReplicatedStorage:WaitForChild("Remotes"))

local player = Players.LocalPlayer
local C = UI.Colors
local TOUCH = UI.isTouch() -- celular: botões maiores e o painel com a altura da tela (UITheme.fitTouchPanel)
local BUTTON_W, BUTTON_H = if TOUCH then 128 else 116, if TOUCH then 42 else 34
local CARD_H = if TOUCH then 72 else 64

-- Visual de cada aparelho
local STYLES = {
	Tablet = {
		Name = "TABLET",
		Glyph = "▣",
		Accent = Color3.fromRGB(80, 170, 255),
		Bezel = Color3.fromRGB(18, 20, 26),
		Screen = Color3.fromRGB(12, 18, 28),
		Speaker = nil,
	},
	Kogane = {
		Name = "KOGANE",
		Glyph = "金",
		Accent = Color3.fromRGB(255, 190, 60),
		Bezel = Color3.fromRGB(40, 24, 10),
		Screen = Color3.fromRGB(24, 16, 10),
		Speaker = "Kogane",
	},
}

local function styleOf()
	return if player:GetAttribute("Path") == "Fiend" then STYLES.Kogane else STYLES.Tablet
end

local gui = UI.screen("Device", 55, player:WaitForChild("PlayerGui"))
local toggle = UI.new("BindableEvent", { Name = "Toggle", Parent = gui })

-- ================= Painel =================

local bezel = UI.new("Frame", { Name = "Bezel", Parent = gui, AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(470, 560), BorderSizePixel = 0, Visible = false })
UI.corner(bezel, UDim.new(0, 22))
local bezelStroke = UI.stroke(bezel, C.White, 2, 0.2)
if not TOUCH then
	UI.autoScale(bezel, 520, 620)
end
local screen = UI.new("Frame", { Name = "Screen", Parent = bezel, Position = UDim2.fromOffset(14, 14),
	Size = UDim2.new(1, -28, 1, -28), BorderSizePixel = 0, ClipsDescendants = true })
UI.corner(screen, UDim.new(0, 12))

-- Barra de cima: nome do aparelho, hora e fechar
local glyph = UI.label({ Parent = screen, Position = UDim2.fromOffset(12, 6), Size = UDim2.fromOffset(28, 28), TextSize = 20,
	Font = UI.Fonts.Title, TextXAlignment = Enum.TextXAlignment.Center })
local title = UI.label({ Parent = screen, Position = UDim2.fromOffset(44, 6), Size = UDim2.fromOffset(240, 28), TextSize = 18,
	Font = UI.Fonts.Title })
local clock = UI.label({ Parent = screen, Position = UDim2.new(1, if TOUCH then -160 else -150, 0, 8), Size = UDim2.fromOffset(100, 24), TextSize = 13,
	TextColor3 = C.TextDim, TextXAlignment = Enum.TextXAlignment.Right })
local close = UI.button({ Parent = screen, Position = UDim2.new(1, if TOUCH then -48 else -40, 0, 4),
	Size = if TOUCH then UDim2.fromOffset(40, 34) else UDim2.fromOffset(30, 28), Text = "X",
	TextSize = 14 }, C.PanelLight)

local body = UI.new("ScrollingFrame", { Parent = screen, Position = UDim2.fromOffset(12, 42), Size = UDim2.new(1, -24, 1, -54),
	BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 4, AutomaticCanvasSize = Enum.AutomaticSize.Y,
	CanvasSize = UDim2.new() })
UI.list(body, 8)

UI.fitTouchPanel(bezel, 520, 560, body)

local state = nil -- DailyState

local function formatTime(seconds)
	seconds = math.max(0, math.floor(seconds))
	local hours = math.floor(seconds / 3600)
	local minutes = math.floor(seconds % 3600 / 60)
	if hours > 0 then return `{hours}h {minutes}min` end
	if minutes > 0 then return `{minutes}min {seconds % 60}s` end
	return `{seconds}s`
end

local function clearBody()
	for _, child in body:GetChildren() do
		if child:IsA("GuiObject") then child:Destroy() end
	end
end

local function card(order, height)
	local frame = UI.new("Frame", { Parent = body, LayoutOrder = order, Size = UDim2.new(1, -6, 0, height),
		BackgroundColor3 = C.Black, BackgroundTransparency = 0.45, BorderSizePixel = 0 })
	UI.corner(frame, UDim.new(0, 8))
	return frame
end

local function textLine(parent, props)
	props.Parent = parent
	props.TextWrapped = true
	return UI.label(props)
end

-- Fala da Kogane (no tablet é só o texto)
local function speech(order, text)
	local style = styleOf()
	local frame = card(order, 0)
	frame.AutomaticSize = Enum.AutomaticSize.Y
	UI.padding(frame, 8, 10, 8, 10)
	textLine(frame, { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, TextSize = 13,
		TextColor3 = if style.Speaker then style.Accent else C.TextDim,
		Text = if style.Speaker then `{style.Speaker}: "{text}"` else text })
end

local bossLabel -- texto do chefe global (atualizado a cada segundo)

local function bossText()
	for name, value in ReplicatedStorage:GetAttributes() do
		local bossType = string.match(name, "^GlobalBoss_(.+)$")
		if bossType and type(value) == "number" then
			local bossTitle = ReplicatedStorage:GetAttribute("GlobalBossTitle_" .. bossType) or bossType
			if ReplicatedStorage:GetAttribute("GlobalBossActive_" .. bossType) == true then
				return `{bossTitle} ESTÁ NO MAPA! Siga o marcador em cima do lugar dele.`
			end
			return `{bossTitle} aparece em {formatTime(value - workspace:GetServerTimeNow())}.`
		end
	end
	return "Nenhum chefe global agendado."
end

local function render()
	local style = styleOf()
	bezel.BackgroundColor3 = style.Bezel
	bezelStroke.Color = style.Accent
	screen.BackgroundColor3 = style.Screen
	glyph.Text = style.Glyph
	glyph.TextColor3 = style.Accent
	local pathName = if player:GetAttribute("Path") == "Hunter" then "CAÇADOR" elseif style.Speaker then "INFERNAL" else "HUMANO"
	title.Text = if style.Speaker then style.Name else `{style.Name} · {pathName}`
	title.TextColor3 = style.Accent
	clearBody()

	local order = 1
	if style.Speaker then
		speech(order, "Ei! Trouxe o serviço de hoje. Faça direitinho que o pagamento é bom.")
		order += 1
	end

	-- Chefe global
	local boss = card(order, 54)
	order += 1
	textLine(boss, { Position = UDim2.fromOffset(10, 4), Size = UDim2.new(1, -20, 0, 18), Text = "CHEFE GLOBAL", TextSize = 12,
		Font = UI.Fonts.Title, TextColor3 = style.Accent })
	bossLabel = textLine(boss, { Position = UDim2.fromOffset(10, 22), Size = UDim2.new(1, -20, 0, 28), Text = bossText(),
		TextSize = 13 })

	-- Missões
	local header = UI.label({ Parent = body, LayoutOrder = order, Size = UDim2.new(1, -6, 0, 22), Text = "MISSÕES DE HOJE",
		TextSize = 15, Font = UI.Fonts.Title })
	order += 1
	if not state then
		header.Text = "MISSÕES DE HOJE · carregando..."
		return
	end
	header.Text = `MISSÕES DE HOJE · renovam em {formatTime(state.NextDayAt - workspace:GetServerTimeNow())}`
	local allClaimed = #state.Missions > 0
	for _, mission in state.Missions do
		local done = mission.Progress >= mission.Goal
		allClaimed = allClaimed and mission.Claimed
		local frame = card(order, CARD_H)
		order += 1
		textLine(frame, { Position = UDim2.fromOffset(10, 6), Size = UDim2.new(1, -(BUTTON_W + 24), 0, 32), Text = mission.Text, TextSize = 14,
			TextColor3 = if mission.Claimed then C.TextDim else C.Text })
		local barBack = UI.new("Frame", { Parent = frame, Position = UDim2.new(0, 10, 1, -18), Size = UDim2.new(1, -(BUTTON_W + 24), 0, 8),
			BackgroundColor3 = C.Black, BackgroundTransparency = 0.2, BorderSizePixel = 0 })
		UI.corner(barBack, UDim.new(1, 0))
		local fill = UI.new("Frame", { Parent = barBack, Size = UDim2.fromScale(mission.Progress / mission.Goal, 1),
			BackgroundColor3 = style.Accent, BorderSizePixel = 0 })
		UI.corner(fill, UDim.new(1, 0))
		local button = UI.button({ Parent = frame, AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -10, 0.5, 0),
			Size = UDim2.fromOffset(BUTTON_W, BUTTON_H), TextSize = if TOUCH then 14 else 12,
			Text = if mission.Claimed then "✓ FEITO" elseif done then "RESGATAR" else `{mission.Progress}/{mission.Goal}` },
			if done and not mission.Claimed then style.Accent else C.PanelLight)
		if done and not mission.Claimed then
			button.TextColor3 = C.Black
			button.Activated:Connect(function()
				Remotes.DailyAction:FireServer("Claim", mission.Index)
			end)
		end
	end
	local reward = card(order, 26)
	order += 1
	local streakText = if state.StreakGold > 0 then ` (+{math.floor(state.StreakGold * 100 + 0.5)}% de sequência)` else ""
	textLine(reward, { Position = UDim2.fromOffset(10, 0), Size = UDim2.new(1, -20, 1, 0), TextSize = 12, TextColor3 = C.TextDim,
		Text = `Cada missão: {state.Gold} Gold{streakText} e {state.XP} XP` })

	-- Bônus de completar as três
	local bonus = card(order, CARD_H)
	order += 1
	textLine(bonus, { Position = UDim2.fromOffset(10, 6), Size = UDim2.new(1, -(BUTTON_W + 24), 0, CARD_H - 12), TextSize = 13,
		Text = `Complete as 3: +{state.BonusSpins} giro de clã.\nSequência: {state.Streak} dia(s) seguidos.` })
	local bonusButton = UI.button({ Parent = bonus, AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -10, 0.5, 0),
		Size = UDim2.fromOffset(BUTTON_W, BUTTON_H), TextSize = if TOUCH then 14 else 12,
		Text = if state.BonusClaimed then "✓ RECEBIDO" elseif allClaimed then "PEGAR BÔNUS" else "FALTA" },
		if allClaimed and not state.BonusClaimed then style.Accent else C.PanelLight)
	if allClaimed and not state.BonusClaimed then
		bonusButton.TextColor3 = C.Black
		bonusButton.Activated:Connect(function()
			Remotes.DailyAction:FireServer("Bonus")
		end)
	end
end

local function show(visible)
	bezel.Visible = visible
	if visible then
		Remotes.DailyAction:FireServer("State")
		render()
	end
end

toggle.Event:Connect(function() show(not bezel.Visible) end)
close.Activated:Connect(function() show(false) end)
Remotes.DailyState.OnClientEvent:Connect(function(data)
	if type(data) ~= "table" or type(data.Missions) ~= "table" then return end
	state = data
	if bezel.Visible then render() end
end)
player:GetAttributeChangedSignal("Path"):Connect(function()
	if bezel.Visible then render() end
end)

UserInputService.InputBegan:Connect(function(input, processed)
	if processed or player:GetAttribute("MenuOpen") then return end
	if input.KeyCode == Enum.KeyCode.T then
		show(not bezel.Visible)
	elseif input.KeyCode == Enum.KeyCode.Escape and bezel.Visible then
		show(false)
	end
end)

-- Relógio e contador do chefe enquanto aberto
task.spawn(function()
	while true do
		task.wait(1)
		if bezel.Visible then
			clock.Text = os.date("%H:%M")
			if bossLabel and bossLabel.Parent then
				bossLabel.Text = bossText()
			end
		end
	end
end)

-- ================= Avisos (chefe global) =================

local toast = UI.new("Frame", { Name = "Alert", Parent = gui, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 360, 0, 120),
	Size = UDim2.fromOffset(330, 78), BorderSizePixel = 0, Visible = false })
UI.corner(toast, UDim.new(0, 14))
local toastStroke = UI.stroke(toast, C.White, 2, 0.1)
local toastGlyph = UI.label({ Parent = toast, Position = UDim2.fromOffset(10, 0), Size = UDim2.fromOffset(40, 78), TextSize = 28,
	Font = UI.Fonts.Title, TextXAlignment = Enum.TextXAlignment.Center })
local toastTitle = UI.label({ Parent = toast, Position = UDim2.fromOffset(56, 8), Size = UDim2.new(1, -66, 0, 20), TextSize = 14,
	Font = UI.Fonts.Title })
local toastText = UI.label({ Parent = toast, Position = UDim2.fromOffset(56, 28), Size = UDim2.new(1, -66, 0, 44), TextSize = 13,
	TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top })
local toastToken = 0

Remotes.DeviceAlert.OnClientEvent:Connect(function(alertTitle, text)
	local style = styleOf()
	toastToken += 1
	local token = toastToken
	toast.BackgroundColor3 = style.Bezel
	toastStroke.Color = style.Accent
	toastGlyph.Text = style.Glyph
	toastGlyph.TextColor3 = style.Accent
	toastTitle.Text = `{style.Name} · {tostring(alertTitle)}`
	toastTitle.TextColor3 = style.Accent
	toastText.Text = if style.Speaker then `"{tostring(text)}"` else tostring(text)
	toast.Visible = true
	toast.Position = UDim2.new(1, 360, 0, 120)
	TweenService:Create(toast, TweenInfo.new(0.35, Enum.EasingStyle.Back), { Position = UDim2.new(1, -16, 0, 120) }):Play()
	task.delay(8, function()
		if toastToken ~= token then return end
		local out = TweenService:Create(toast, TweenInfo.new(0.3), { Position = UDim2.new(1, 360, 0, 120) })
		out:Play()
		out.Completed:Wait()
		if toastToken == token then toast.Visible = false end
	end)
	if bezel.Visible then render() end
end)
