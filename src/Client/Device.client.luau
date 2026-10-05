-- Aparelho do caminho: o TABLET do Caçador (e do Humano, antes de escolher) ou o KOG do Infernal. Duas abas: DAILY
-- (missões diárias, DailyService, Remotes.DailyAction/DailyState, e o chefe global pelos atributos GlobalBoss_* do
-- ReplicatedStorage) e MILESTONES (marcos, MilestoneService/MilestoneData, Remotes.MilestoneAction/MilestoneState).
-- É por ele que chegam os avisos do chefe (Remotes.DeviceAlert).
-- Abre com T, pelo botão da HUD (HUB_GUI) ou pelo BindableEvent Device.Toggle.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local UI = require(ReplicatedStorage:WaitForChild("UITheme"))
local Remotes = require(ReplicatedStorage:WaitForChild("Remotes"))
local MilestoneData = require(ReplicatedStorage:WaitForChild("MilestoneData"))
local Icons = require(ReplicatedStorage:WaitForChild("Icons"))

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
	Kog = {
		Name = "KOG",
		Glyph = "金",
		Accent = Color3.fromRGB(255, 190, 60),
		Bezel = Color3.fromRGB(40, 24, 10),
		Screen = Color3.fromRGB(24, 16, 10),
		Speaker = "Kog",
	},
}

local function styleOf()
	return if player:GetAttribute("Path") == "Fiend" then STYLES.Kog else STYLES.Tablet
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

-- Abas
local TAB_H = if TOUCH then 38 else 30
local tabs = {}
local tabRow = UI.new("Frame", { Parent = screen, Position = UDim2.fromOffset(12, 40), Size = UDim2.new(1, -24, 0, TAB_H),
	BackgroundTransparency = 1 })
UI.list(tabRow, 8, Enum.FillDirection.Horizontal)
for index, info in { { Id = "Daily", Text = "DAILY" }, { Id = "Milestones", Text = "MILESTONES" } } do
	local tab = UI.button({ Parent = tabRow, LayoutOrder = index, Size = UDim2.new(0.5, -4, 1, 0), Text = info.Text,
		TextSize = if TOUCH then 14 else 12 }, C.PanelLight)
	local dot = UI.new("Frame", { Parent = tab, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(1, -8, 0, 6),
		Size = UDim2.fromOffset(10, 10), BackgroundColor3 = C.Accent, BorderSizePixel = 0, Visible = false })
	UI.corner(dot, UDim.new(1, 0))
	tabs[info.Id] = { Button = tab, Dot = dot }
end

local body = UI.new("ScrollingFrame", { Parent = screen, Position = UDim2.fromOffset(12, 48 + TAB_H), Size = UDim2.new(1, -24, 1, -(60 + TAB_H)),
	BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 4, AutomaticCanvasSize = Enum.AutomaticSize.Y,
	CanvasSize = UDim2.new() })
UI.list(body, 8)

UI.fitTouchPanel(bezel, 520, 560, body)

local state = nil -- DailyState
local milestoneState = nil -- MilestoneState: { Tracks = { { Id, Progress, Claimed } } }
local currentTab = "Daily"
local selectedTrack = MilestoneData.Tracks[1].Id

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

-- Fala do Kog (no tablet é só o texto)
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
local render, renderMilestones -- (definidas mais abaixo; uma chama a outra)

local function bossText()
	for name, value in ReplicatedStorage:GetAttributes() do
		local bossType = string.match(name, "^GlobalBoss_(.+)$")
		if bossType and type(value) == "number" then
			local bossTitle = ReplicatedStorage:GetAttribute("GlobalBossTitle_" .. bossType) or bossType
			if ReplicatedStorage:GetAttribute("GlobalBossActive_" .. bossType) == true then
				return `{bossTitle} IS ON THE MAP! Follow the marker above his spot.`
			end
			return `{bossTitle} shows up in {formatTime(value - workspace:GetServerTimeNow())}.`
		end
	end
	return "No global boss scheduled."
end

-- Aba MILESTONES: escolha da trilha e os níveis dela (como a referência do usuário: texto (x/meta), barra, prêmio e
-- o botão de resgatar; em ordem)
local function trackState(id)
	if not milestoneState then return nil end
	for _, entry in milestoneState.Tracks do
		if entry.Id == id then return entry end
	end
	return nil
end

local function trackClaimable(track)
	local entry = trackState(track.Id)
	local nextTier = entry and track.Tiers[entry.Claimed + 1]
	return nextTier ~= nil and entry.Progress >= nextTier.Goal
end

function renderMilestones(style)
	local order = 1
	if style.Speaker then
		speech(order, "Big goals, big pay. Bring me proof and I will pay up.")
		order += 1
	end
	-- Trilhas (botões com o kanji)
	local picker = UI.new("Frame", { Parent = body, LayoutOrder = order, Size = UDim2.new(1, -6, 0, if TOUCH then 46 else 40),
		BackgroundTransparency = 1 })
	order += 1
	UI.list(picker, 6, Enum.FillDirection.Horizontal)
	local count = #MilestoneData.Tracks
	for index, track in MilestoneData.Tracks do
		local active = track.Id == selectedTrack
		local button = UI.button({ Parent = picker, LayoutOrder = index, Size = UDim2.new(1 / count, -6 * (count - 1) / count, 1, 0),
			Text = track.Glyph, TextSize = if TOUCH then 22 else 18, Font = UI.Fonts.Title },
			if active then style.Accent else C.PanelLight)
		button.TextColor3 = if active then C.Black else C.Text
		Icons.Apply(button, track.Icon, 0.72)
		UI.tooltip(button, UI.tipText(track.Name, string.format(track.Text, track.Tiers[1].Goal)))
		if trackClaimable(track) then
			local dot = UI.new("Frame", { Parent = button, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(1, -7, 0, 7),
				Size = UDim2.fromOffset(10, 10), BackgroundColor3 = C.Accent, BorderSizePixel = 0 })
			UI.corner(dot, UDim.new(1, 0))
		end
		button.Activated:Connect(function()
			selectedTrack = track.Id
			render()
		end)
	end

	local track = MilestoneData.Get(selectedTrack) or MilestoneData.Tracks[1]
	local entry = trackState(track.Id)
	UI.label({ Parent = body, LayoutOrder = order, Size = UDim2.new(1, -6, 0, 22), TextSize = 15, Font = UI.Fonts.Title,
		Text = if entry then `{string.upper(track.Name)} · {entry.Claimed}/{#track.Tiers}` else `{string.upper(track.Name)} · loading...` })
	order += 1
	if not entry then return end

	for index, tier in track.Tiers do
		local claimed = index <= entry.Claimed
		local reached = entry.Progress >= tier.Goal
		local canClaim = not claimed and reached and index == entry.Claimed + 1
		local shown = math.min(entry.Progress, tier.Goal)
		local frame = card(order, CARD_H + 8)
		order += 1
		textLine(frame, { Position = UDim2.fromOffset(10, 6), Size = UDim2.new(1, -(BUTTON_W + 24), 0, 20), TextSize = 14,
			Text = `{MilestoneData.TierText(track, tier)} ({UI.formatNumber(shown)}/{UI.formatNumber(tier.Goal)})`,
			TextColor3 = if claimed then C.TextDim else C.Text })
		local barBack = UI.new("Frame", { Parent = frame, Position = UDim2.fromOffset(10, 30), Size = UDim2.new(1, -(BUTTON_W + 24), 0, 8),
			BackgroundColor3 = C.Black, BackgroundTransparency = 0.2, BorderSizePixel = 0 })
		UI.corner(barBack, UDim.new(1, 0))
		local fill = UI.new("Frame", { Parent = barBack, Size = UDim2.fromScale(math.clamp(shown / tier.Goal, 0, 1), 1),
			BackgroundColor3 = style.Accent, BorderSizePixel = 0 })
		UI.corner(fill, UDim.new(1, 0))
		textLine(frame, { Position = UDim2.fromOffset(10, 42), Size = UDim2.new(1, -(BUTTON_W + 24), 0, 18), TextSize = 12,
			Font = UI.Fonts.Title, TextColor3 = C.Gold, Text = MilestoneData.RewardText(tier) })
		local button = UI.button({ Parent = frame, AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -10, 0.5, 0),
			Size = UDim2.fromOffset(BUTTON_W, BUTTON_H), TextSize = if TOUCH then 14 else 12,
			Text = if claimed then "✓ CLAIMED" elseif canClaim then "CLAIM" elseif reached then "CLAIM PREVIOUS" else "LOCKED" },
			if canClaim then style.Accent else C.PanelLight)
		if canClaim then
			button.TextColor3 = C.Black
			button.Activated:Connect(function()
				Remotes.MilestoneAction:FireServer("Claim", track.Id)
			end)
		end
	end
end

function render()
	local style = styleOf()
	bezel.BackgroundColor3 = style.Bezel
	bezelStroke.Color = style.Accent
	screen.BackgroundColor3 = style.Screen
	glyph.Text = style.Glyph
	if style.Speaker then
		Icons.Clear(glyph)
	else
		Icons.Apply(glyph, "tablet", 0.95)
	end
	glyph.TextColor3 = style.Accent
	local pathName = if player:GetAttribute("Path") == "Hunter" then "HUNTER" elseif style.Speaker then "FIEND" else "HUMAN"
	title.Text = if style.Speaker then style.Name else `{style.Name} · {pathName}`
	title.TextColor3 = style.Accent
	for id, tab in tabs do
		local active = id == currentTab
		tab.Button.BackgroundColor3 = if active then style.Accent else C.PanelLight
		tab.Button.TextColor3 = if active then C.Black else C.Text
	end
	clearBody()
	if currentTab == "Milestones" then
		renderMilestones(style)
		return
	end

	local order = 1
	if style.Speaker then
		speech(order, "Hey! I brought today's jobs. Do them right and the pay is good.")
		order += 1
	end

	-- Chefe global
	local boss = card(order, 54)
	order += 1
	textLine(boss, { Position = UDim2.fromOffset(10, 4), Size = UDim2.new(1, -20, 0, 18), Text = "GLOBAL BOSS", TextSize = 12,
		Font = UI.Fonts.Title, TextColor3 = style.Accent })
	bossLabel = textLine(boss, { Position = UDim2.fromOffset(10, 22), Size = UDim2.new(1, -20, 0, 28), Text = bossText(),
		TextSize = 13 })

	-- Missões
	local header = UI.label({ Parent = body, LayoutOrder = order, Size = UDim2.new(1, -6, 0, 22), Text = "TODAY'S QUESTS",
		TextSize = 15, Font = UI.Fonts.Title })
	order += 1
	if not state then
		header.Text = "TODAY'S QUESTS · loading..."
		return
	end
	header.Text = `TODAY'S QUESTS · reset in {formatTime(state.NextDayAt - workspace:GetServerTimeNow())}`
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
			Text = if mission.Claimed then "✓ DONE" elseif done then "CLAIM" else `{mission.Progress}/{mission.Goal}` },
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
	local streakText = if state.StreakGold > 0 then ` (+{math.floor(state.StreakGold * 100 + 0.5)}% streak)` else ""
	textLine(reward, { Position = UDim2.fromOffset(10, 0), Size = UDim2.new(1, -20, 1, 0), TextSize = 12, TextColor3 = C.TextDim,
		Text = `Each quest: {state.Gold} Gold{streakText} and {state.XP} XP` })

	-- Bônus de completar as três
	local bonus = card(order, CARD_H)
	order += 1
	textLine(bonus, { Position = UDim2.fromOffset(10, 6), Size = UDim2.new(1, -(BUTTON_W + 24), 0, CARD_H - 12), TextSize = 13,
		Text = `Complete all 3: +{state.BonusSpins} clan spin.\nStreak: {state.Streak} day(s) in a row.` })
	local bonusButton = UI.button({ Parent = bonus, AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -10, 0.5, 0),
		Size = UDim2.fromOffset(BUTTON_W, BUTTON_H), TextSize = if TOUCH then 14 else 12,
		Text = if state.BonusClaimed then "✓ CLAIMED" elseif allClaimed then "CLAIM BONUS" else "NOT YET" },
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
		Remotes.MilestoneAction:FireServer("State")
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
Remotes.MilestoneState.OnClientEvent:Connect(function(data)
	if type(data) ~= "table" or type(data.Tracks) ~= "table" then return end
	milestoneState = data
	if bezel.Visible then render() end
end)
for id, tab in tabs do
	tab.Button.Activated:Connect(function()
		currentTab = id
		render()
	end)
end
local function updateTabDots()
	tabs.Daily.Dot.Visible = player:GetAttribute("DailyClaimable") == true
	tabs.Milestones.Dot.Visible = player:GetAttribute("MilestoneClaimable") == true
end
player:GetAttributeChangedSignal("DailyClaimable"):Connect(updateTabDots)
player:GetAttributeChangedSignal("MilestoneClaimable"):Connect(updateTabDots)
updateTabDots()
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
