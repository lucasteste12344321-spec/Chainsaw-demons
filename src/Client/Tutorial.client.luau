-- Tutorial guiado (passos em ReplicatedStorage.TutorialData; quem salva e dá a recompensa é o TutorialService).
-- Começa sozinho depois do JOGAR quando o atributo TutorialDone do player é false, e pausa com o menu principal aberto.
-- Cada passo mostra um painel (título, texto com as teclas destacadas, barra de avanço) e, quando tem, destaca um
-- elemento da interface (atributo TutorialAnchor, ex.: "Slot_Q", "TreeButton") e aponta um alvo no mapa (marcador em
-- cima do alvo e seta na borda da tela quando ele está fora de vista).
-- A conferência é feita aqui, pelo estado do jogo (tabela Checks): ninguém precisa avisar o tutorial do que aconteceu.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local CollectionService = game:GetService("CollectionService")

local Remotes = require(ReplicatedStorage:WaitForChild("Remotes"))
local UITheme = require(ReplicatedStorage:WaitForChild("UITheme"))
local TutorialData = require(ReplicatedStorage:WaitForChild("TutorialData"))

local Colors = UITheme.Colors
local Fonts = UITheme.Fonts

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local touchOnly = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled

local ACCENT = Colors.Orange
local DONE_COLOR = Colors.Green
local KEY_HEX = Colors.Orange:ToHex()
local PANEL_WIDTH = if touchOnly then 360 else 440
local PANEL_TOP = 74 -- abaixo da barra do Roblox
local STEP_PAUSE = 0.9 -- tempo mostrando o "✓" antes do próximo passo
local COMBO_GAP = 1.4 -- golpes com até este intervalo contam como o mesmo combo (ComboReset do estilo é 1,2 s)
local NEAR_GOBLINS = 35 -- distância da borda da zona dos Goblins que já conta como "chegou"
local GOBLIN_SEARCH = 250 -- Goblin vivo até esta distância vira o alvo (senão, a zona)
local DUMMY_RETRY = 3 -- pede o boneco de novo se ele não aparecer
local EDGE_MARGIN = 64

----------------------------------------------------------------------------------------------------
-- Interface
----------------------------------------------------------------------------------------------------

local function new(className, props)
	return UITheme.new(className, props)
end

local screen = UITheme.screen("Tutorial", 12, playerGui) -- acima da HUD, árvore e diálogos; abaixo do menu e avisos
screen.IgnoreGuiInset = true -- a seta da borda usa as coordenadas da tela inteira (WorldToViewportPoint)
screen.Enabled = false

local panel = UITheme.panel({
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, PANEL_TOP),
	Size = UDim2.fromOffset(PANEL_WIDTH, 0),
	AutomaticSize = Enum.AutomaticSize.Y,
	ZIndex = 5,
	Parent = screen,
})
UITheme.padding(panel, 10, 16, 12, 16)
UITheme.list(panel, 6)
UITheme.autoScale(panel, 1100, 700)
local panelStroke = panel:FindFirstChildOfClass("UIStroke")
local panelGradient = panelStroke and panelStroke:FindFirstChildOfClass("UIGradient") -- borda vermelha do tema

local header = new("Frame", {
	Size = UDim2.new(1, 0, 0, 18),
	BackgroundTransparency = 1,
	LayoutOrder = 1,
	ZIndex = 5,
	Parent = panel,
})
local chapterLabel = UITheme.label({
	Size = UDim2.new(1, -120, 1, 0),
	Font = Fonts.Marker,
	TextSize = 14,
	TextColor3 = ACCENT,
	ZIndex = 6,
	Parent = header,
})
local skipButton = new("TextButton", {
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.fromScale(1, 0),
	Size = UDim2.fromOffset(120, 18),
	BackgroundTransparency = 1,
	Font = Fonts.Body,
	TextSize = 12,
	TextColor3 = Colors.TextDim,
	TextXAlignment = Enum.TextXAlignment.Right,
	RichText = true,
	Text = "<u>Pular tutorial</u>",
	ZIndex = 6,
	Parent = header,
})

local titleLabel = UITheme.label({
	Size = UDim2.new(1, 0, 0, 0),
	AutomaticSize = Enum.AutomaticSize.Y,
	Font = Fonts.Marker,
	TextSize = 24,
	TextWrapped = true,
	LayoutOrder = 2,
	ZIndex = 6,
	Parent = panel,
})

local bodyLabel = UITheme.label({
	Size = UDim2.new(1, 0, 0, 0),
	AutomaticSize = Enum.AutomaticSize.Y,
	Font = Fonts.Body,
	TextSize = 15,
	TextWrapped = true,
	RichText = true,
	TextYAlignment = Enum.TextYAlignment.Top,
	LineHeight = 1.1,
	LayoutOrder = 3,
	ZIndex = 6,
	Parent = panel,
})

local progressBar = UITheme.bar({
	Size = UDim2.new(1, 0, 0, 16),
	LayoutOrder = 4,
	Visible = false,
	ZIndex = 6,
	Parent = panel,
}, Colors.XP, 11)

local buttonRow = new("Frame", {
	Size = UDim2.new(1, 0, 0, 36),
	BackgroundTransparency = 1,
	LayoutOrder = 5,
	Visible = false,
	ZIndex = 5,
	Parent = panel,
})
local continueButton = UITheme.button({
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.fromScale(1, 0),
	Size = UDim2.fromOffset(170, 34),
	Font = Fonts.Marker,
	TextSize = 18,
	Text = "CONTINUAR",
	ZIndex = 6,
	Parent = buttonRow,
}, Colors.Accent)
local enterHint = UITheme.label({
	Size = UDim2.new(1, -180, 1, 0),
	Font = Fonts.Light,
	TextSize = 12,
	TextColor3 = Colors.TextDim,
	Text = if touchOnly then "" else "Enter também continua",
	ZIndex = 6,
	Parent = buttonRow,
})

-- Avanço geral (uma tira fina no pé do painel)
local overall = new("Frame", {
	Size = UDim2.new(1, 0, 0, 3),
	BackgroundColor3 = Colors.PanelLight,
	BorderSizePixel = 0,
	LayoutOrder = 6,
	ZIndex = 6,
	Parent = panel,
})
local overallFill = new("Frame", {
	Size = UDim2.fromScale(0, 1),
	BackgroundColor3 = ACCENT,
	BorderSizePixel = 0,
	ZIndex = 7,
	Parent = overall,
})

-- Destaque de um elemento da interface: moldura pulsando e uma setinha
local ring = new("Frame", {
	BackgroundTransparency = 1,
	Visible = false,
	ZIndex = 3,
	Parent = screen,
})
UITheme.corner(ring, UDim.new(0, 10))
local ringStroke = UITheme.stroke(ring, ACCENT, 3, 0)
local ringArrow = UITheme.label({
	AnchorPoint = Vector2.new(0.5, 0.5),
	Size = UDim2.fromOffset(40, 40),
	TextXAlignment = Enum.TextXAlignment.Center,
	Font = Fonts.Number,
	TextSize = 30,
	TextColor3 = ACCENT,
	TextStrokeTransparency = 0.2,
	Text = "▼",
	Visible = false,
	ZIndex = 4,
	Parent = screen,
})

-- Seta na borda da tela quando o alvo no mapa está fora de vista
local edgeArrow = UITheme.label({
	AnchorPoint = Vector2.new(0.5, 0.5),
	Size = UDim2.fromOffset(46, 46),
	TextXAlignment = Enum.TextXAlignment.Center,
	Font = Fonts.Number,
	TextSize = 40,
	TextColor3 = ACCENT,
	TextStrokeTransparency = 0.1,
	Text = "▲",
	Visible = false,
	ZIndex = 4,
	Parent = screen,
})
local edgeDistance = UITheme.label({
	AnchorPoint = Vector2.new(0.5, 0.5),
	Size = UDim2.fromOffset(90, 18),
	TextXAlignment = Enum.TextXAlignment.Center,
	Font = Fonts.Number,
	TextSize = 13,
	TextStrokeTransparency = 0.3,
	Visible = false,
	ZIndex = 4,
	Parent = screen,
})

-- Marcador em cima do alvo no mapa
local marker = new("BillboardGui", {
	Name = "TutorialMarker",
	AlwaysOnTop = true,
	LightInfluence = 0,
	Size = UDim2.fromOffset(170, 64),
	StudsOffsetWorldSpace = Vector3.new(0, 4, 0),
	Enabled = false,
	ResetOnSpawn = false,
	Parent = playerGui,
})
local markerName = UITheme.label({
	Size = UDim2.new(1, 0, 0, 20),
	TextXAlignment = Enum.TextXAlignment.Center,
	Font = Fonts.Title,
	TextSize = 15,
	TextStrokeTransparency = 0.2,
	Parent = marker,
})
local markerArrow = UITheme.label({
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 20),
	Size = UDim2.fromOffset(40, 40),
	TextXAlignment = Enum.TextXAlignment.Center,
	Font = Fonts.Number,
	TextSize = 34,
	TextColor3 = ACCENT,
	TextStrokeTransparency = 0.1,
	Text = "▼",
	Parent = marker,
})

local completeSound = new("Sound", {
	SoundId = "rbxassetid://" .. TutorialData.CompleteSound,
	Volume = 0.5,
	Parent = screen,
})

----------------------------------------------------------------------------------------------------
-- Utilidades
----------------------------------------------------------------------------------------------------

local function getCharacter()
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if humanoid and root and humanoid.Health > 0 then
		return character, humanoid, root
	end
	return nil
end

-- {Tecla} vira texto destacado; $REWARD, a recompensa (ou "já recebida")
local function formatText(text)
	local reward
	if player:GetAttribute("TutorialRewarded") == true then
		reward = "já recebida antes"
	else
		local parts = {}
		if (TutorialData.Reward.Gold or 0) > 0 then
			table.insert(parts, `\{+{TutorialData.Reward.Gold} Gold}`)
		end
		local spins = TutorialData.Reward.Spins or 0
		if spins > 0 then
			table.insert(parts, if spins == 1 then "{1 giro de clã}" else `\{{spins} giros de clã}`)
		end
		reward = table.concat(parts, " e ")
	end
	text = string.gsub(text, "%$REWARD", reward)
	text = UITheme.escape(text)
	return (string.gsub(text, "{(.-)}", function(key)
		return `<font color="#{KEY_HEX}"><b>{key}</b></font>`
	end))
end

local function guiByName(name)
	local gui = playerGui:FindFirstChild(name)
	return if gui and gui:IsA("ScreenGui") then gui else nil
end

local function guiOpen(name)
	local gui = guiByName(name)
	return gui ~= nil and gui.Enabled
end

local function menuOpen()
	if player:GetAttribute("MenuOpen") == true then return true end
	return guiOpen("TitleScreen")
end

-- O elemento está na tela de verdade (a tela dele ligada e todos os pais visíveis)?
local function isShown(object)
	if not object:IsDescendantOf(playerGui) then return false end
	local gui = object:FindFirstAncestorOfClass("ScreenGui")
	if not gui or not gui.Enabled then return false end
	local current = object
	while current and current ~= gui do
		if current:IsA("GuiObject") and not current.Visible then return false end
		current = current.Parent
	end
	return object.AbsoluteSize.X > 1 and object.AbsoluteSize.Y > 1
end

local anchorCache = {}
local function findAnchor(name)
	local cached = anchorCache[name]
	if cached and cached:IsDescendantOf(playerGui) then return cached end
	for _, object in playerGui:GetDescendants() do
		if object:IsA("GuiObject") and object:GetAttribute("TutorialAnchor") == name then
			anchorCache[name] = object
			return object
		end
	end
	return nil
end

local function partOf(model)
	if not model then return nil end
	return model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart", true)
end

local function findDummy()
	local enemies = workspace:FindFirstChild("Enemies")
	if not enemies then return nil end
	for _, model in enemies:GetChildren() do
		if model:GetAttribute("TrainingDummy") == player.UserId then
			return model
		end
	end
	return nil
end

-- Zona dos Goblins mais perto (EnemySpawns; o Spawner escreve o tipo em ZoneType)
local function goblinZone(from)
	local spawns = workspace:FindFirstChild("EnemySpawns")
	if not spawns then return nil end
	local best, bestDistance
	for _, part in spawns:GetDescendants() do
		if part:IsA("BasePart") and (part:GetAttribute("ZoneType") == "Goblin" or part:GetAttribute("EnemyType") == "Goblin") then
			local distance = (part.Position - from).Magnitude
			if not bestDistance or distance < bestDistance then
				best, bestDistance = part, distance
			end
		end
	end
	return best
end

local function nearestGoblin(from, maxDistance)
	local enemies = workspace:FindFirstChild("Enemies")
	if not enemies then return nil end
	local best, bestDistance
	for _, model in enemies:GetChildren() do
		local humanoid = model:FindFirstChildOfClass("Humanoid")
		local root = model:FindFirstChild("HumanoidRootPart")
		if model:GetAttribute("EnemyType") == "Goblin" and humanoid and humanoid.Health > 0 and root then
			local distance = (root.Position - from).Magnitude
			if distance <= maxDistance and (not bestDistance or distance < bestDistance) then
				best, bestDistance = root, distance
			end
		end
	end
	return best
end

local function npcPart(npcId)
	for _, model in CollectionService:GetTagged("QuestGiver") do
		if model:GetAttribute("NPCId") == npcId and model:IsDescendantOf(workspace) then
			return partOf(model)
		end
	end
	return nil
end

-- Alvo no mapa do passo: devolve (Part, nome mostrado, studs acima da parte)
local function resolveTarget(target)
	local _, _, root = getCharacter()
	local from = if root then root.Position else Vector3.zero
	if target == "Dummy" then
		local dummy = findDummy()
		return dummy and (dummy:FindFirstChild("Head") or partOf(dummy)), "BONECO DE TREINO", 2
	elseif target == "GoblinZone" or target == "Goblin" then
		local goblin = target == "Goblin" and nearestGoblin(from, GOBLIN_SEARCH)
		if goblin then
			return goblin, "GOBLIN", 3.5
		end
		return goblinZone(from), "GOBLINS", 6
	elseif type(target) == "string" and string.sub(target, 1, 4) == "NPC:" then
		local npcId = string.sub(target, 5)
		return npcPart(npcId), if npcId == "Mestre" then "MESTRE ESPADACHIM" else string.upper(npcId), 4
	end
	return nil
end

----------------------------------------------------------------------------------------------------
-- Conferência dos passos
----------------------------------------------------------------------------------------------------
-- Cada Check recebe o estado do passo e pode devolver uma função chamada a cada quadro (dt).
-- state.Add(n) / state.Set(n) mexem no avanço (o passo termina ao chegar no Goal); state.Complete() termina na hora;
-- state.Connect(signal, fn) e state.ForCharacter(fn) guardam as conexões para limpar no fim do passo.

local Checks = {}

Checks.Move = function(state)
	local last
	return function()
		local _, humanoid, root = getCharacter()
		if not root then
			last = nil
			return
		end
		local position = Vector3.new(root.Position.X, 0, root.Position.Z)
		if last and humanoid.MoveDirection.Magnitude > 0.1 then
			local moved = (position - last).Magnitude
			if moved < 10 then -- teleporte ou renascer não contam
				state.Add(moved)
			end
		end
		last = position
	end
end

Checks.Camera = function(state)
	local lastYaw
	return function()
		local camera = workspace.CurrentCamera
		if not camera then return end
		local look = camera.CFrame.LookVector
		local yaw = math.atan2(-look.X, -look.Z)
		if lastYaw then
			local delta = (yaw - lastYaw + math.pi) % (math.pi * 2) - math.pi
			state.Add(math.deg(math.abs(delta)))
		end
		lastYaw = yaw
	end
end

Checks.Jump = function(state)
	state.ForCharacter(function(humanoid)
		return humanoid.StateChanged:Connect(function(_, newState)
			if newState == Enum.HumanoidStateType.Jumping then
				state.Add(1)
			end
		end)
	end)
end

Checks.Dash = function(state)
	state.Connect(player:GetAttributeChangedSignal("DashReadyAt"), function()
		state.Add(1)
	end)
end

-- Golpes no boneco: a vida dele desce (e volta sozinha); só conta o que não foi de outro jogador
local function watchDummy(state, onHit)
	local bound
	return function()
		local dummy = findDummy()
		local humanoid = dummy and dummy:FindFirstChildOfClass("Humanoid")
		if humanoid == bound or not humanoid then return end
		bound = humanoid
		local lastHealth = humanoid.Health
		state.Connect(humanoid.HealthChanged, function(health)
			local attacker = humanoid:GetAttribute("LastAttacker")
			if health < lastHealth and (attacker == nil or attacker == player.UserId) then
				onHit()
			end
			lastHealth = health
		end)
	end
end

Checks.DummyHits = function(state)
	return watchDummy(state, function()
		state.Add(1)
	end)
end

Checks.DummyCombo = function(state)
	local chain, lastHit = 0, 0
	return watchDummy(state, function()
		local now = os.clock()
		chain = if now - lastHit <= COMBO_GAP then chain + 1 else 1
		lastHit = now
		state.Set(chain)
	end)
end

Checks.Block = function(state)
	return function(dt)
		local character = getCharacter()
		if character and character:GetAttribute("Blocking") == true then
			state.Add(dt)
		end
	end
end

Checks.ReachGoblins = function(state)
	return function()
		local _, _, root = getCharacter()
		if not root then return end
		if nearestGoblin(root.Position, 45) then
			state.Complete()
			return
		end
		local zone = goblinZone(root.Position)
		if zone then
			local offset = zone.Position - root.Position
			local flat = Vector3.new(offset.X, 0, offset.Z).Magnitude
			if flat <= math.max(zone.Size.X, zone.Size.Z) / 2 + NEAR_GOBLINS then
				state.Complete()
			end
		end
	end
end

-- Inimigo (de verdade, não o boneco) que morre com o jogador como último atacante
Checks.Kill = function(state)
	local watched = {}
	local function watch(model)
		if watched[model] or model:GetAttribute("TrainingDummy") ~= nil then return end
		local humanoid = model:FindFirstChildOfClass("Humanoid")
		if not humanoid then return end
		watched[model] = true
		local counted = false
		state.Connect(humanoid.HealthChanged, function(health)
			if counted or health > 0 then return end
			counted = true
			if humanoid:GetAttribute("LastAttacker") == player.UserId then
				state.Add(1)
			end
		end)
	end
	local enemies = workspace:FindFirstChild("Enemies")
	if enemies then
		for _, model in enemies:GetChildren() do
			watch(model)
		end
		state.Connect(enemies.ChildAdded, function(model)
			model:WaitForChild("Humanoid", 5)
			watch(model)
		end)
	else
		-- A pasta nasce com o primeiro inimigo
		state.Connect(workspace.ChildAdded, function(child)
			if child.Name == "Enemies" then
				state.Connect(child.ChildAdded, function(model)
					model:WaitForChild("Humanoid", 5)
					watch(model)
				end)
			end
		end)
	end
end

-- Level 2: a barra mostra o XP até lá
Checks.Level = function(state)
	local leaderstats = player:WaitForChild("leaderstats", 10)
	local progress = player:WaitForChild("Progress", 10)
	local level = leaderstats and leaderstats:FindFirstChild("Level")
	local xp = progress and progress:FindFirstChild("XP")
	local needed = progress and progress:FindFirstChild("XPNeeded")
	if not level then
		state.Complete()
		return
	end
	local function refresh()
		if level.Value >= state.Step.Goal then
			state.Complete()
		elseif xp and needed then
			state.Show(xp.Value / math.max(1, needed.Value), `XP {xp.Value}/{needed.Value}`)
		end
	end
	state.Connect(level.Changed, refresh)
	if xp then state.Connect(xp.Changed, refresh) end
	refresh()
	-- Subiu com o menu aberto (passo pausado): confere de novo quando voltar
	return function()
		if level.Value >= state.Step.Goal then
			state.Complete()
		end
	end
end

local function watchGui(state, name, wantOpen)
	local function check()
		local gui = guiByName(name)
		if gui and gui.Enabled == wantOpen then
			state.Complete()
		elseif not gui and not wantOpen then
			state.Complete()
		end
		return gui
	end
	local gui = check()
	if gui then
		state.Connect(gui:GetPropertyChangedSignal("Enabled"), check)
	else
		state.Connect(playerGui.ChildAdded, function(child)
			if child.Name == name and child:IsA("ScreenGui") then
				state.Connect(child:GetPropertyChangedSignal("Enabled"), check)
				check()
			end
		end)
	end
end

Checks.TreeOpen = function(state)
	watchGui(state, "SkillTree", true)
end

Checks.TreeClosed = function(state)
	watchGui(state, "SkillTree", false)
end

Checks.InventoryOpen = function(state)
	watchGui(state, "Inventory", true)
end

Checks.Dialog = function(state)
	watchGui(state, "QuestDialog", true)
end

-- Gastou um ponto da árvore (os pontos livres diminuíram ou a lista de nós mudou). Sem ponto livre: já passou disso.
Checks.Unlock = function(state)
	local progress = player:WaitForChild("Progress", 10)
	local points = progress and progress:FindFirstChild("StatusPoints")
	if not points or points.Value <= 0 then
		state.Complete()
		return
	end
	local start = points.Value
	state.Connect(points.Changed, function(value)
		if value < start then
			state.Complete()
		end
	end)
	state.Connect(player:GetAttributeChangedSignal("SkillTree"), state.Complete)
end

----------------------------------------------------------------------------------------------------
-- Andamento
----------------------------------------------------------------------------------------------------

local current -- passo em andamento
local running = false
local paused = false
local lastDummyRequest = 0
local skipArmedUntil = 0

local function cleanup(state)
	if not state then return end
	state.Ended = true
	for _, connection in state.Connections do
		connection:Disconnect()
	end
	table.clear(state.Connections)
end

local function setDummy(wanted)
	local exists = findDummy() ~= nil
	if wanted and not exists and os.clock() - lastDummyRequest >= DUMMY_RETRY then
		lastDummyRequest = os.clock()
		Remotes.TutorialAction:FireServer("Dummy", true)
	elseif not wanted and exists then
		Remotes.TutorialAction:FireServer("Dummy", false)
	end
end

local function formatGoal(step, value)
	local unit = step.Unit
	if unit == "s" then
		return string.format("%.1f/%d s", math.min(value, step.Goal), step.Goal)
	elseif unit then
		return `{math.floor(math.min(value, step.Goal))}/{step.Goal}{if unit == "°" then "°" else " " .. unit}`
	end
	return `{math.floor(math.min(value, step.Goal))}/{step.Goal}`
end

local startStep -- (definida abaixo)

local function stop()
	running = false
	cleanup(current)
	current = nil
	screen.Enabled = false
	marker.Enabled = false
	marker.Adornee = nil
	setDummy(false)
end

local function finish(skipped)
	local wasRunning = running
	stop()
	if not wasRunning then return end
	Remotes.TutorialAction:FireServer(if skipped then "Skip" else "Finish")
end

local function completeStep(state)
	if state.Ended or state.Completed then return end
	state.Completed = true
	local step = state.Step
	if step.Goal then
		progressBar.Set(1, if step.Check == "Level" then "Level 2!" else formatGoal(step, step.Goal))
	end
	titleLabel.Text = "✓  " .. step.Title
	titleLabel.TextColor3 = DONE_COLOR
	-- Borda verde (o degradê vermelho do tema sai enquanto isso)
	if panelGradient then
		panelGradient.Enabled = false
	end
	panelStroke.Color = DONE_COLOR
	completeSound:Play()
	task.delay(STEP_PAUSE, function()
		if current ~= state or state.Ended then return end
		if step.Final then
			finish(false)
		elseif state.Index < TutorialData.Count then
			startStep(state.Index + 1)
		else
			finish(false)
		end
	end)
end

function startStep(index)
	cleanup(current)
	index = math.clamp(index, 1, TutorialData.Count)
	local step = TutorialData.Steps[index]
	local state = { Index = index, Step = step, Value = 0, Connections = {} }
	current = state

	Remotes.TutorialAction:FireServer("Step", index)
	setDummy(step.Dummy == true)

	-- Painel
	chapterLabel.Text = `{TutorialData.Chapters[step.Chapter] or ""}  ·  {index}/{TutorialData.Count}`
	titleLabel.Text = step.Title
	titleLabel.TextColor3 = Colors.Text
	panelStroke.Color = Colors.White
	if panelGradient then
		panelGradient.Enabled = true
	end
	bodyLabel.Text = formatText(if touchOnly and step.TouchText then step.TouchText else step.Text)
	buttonRow.Visible = step.Check == nil
	continueButton.Text = step.Button or "CONTINUAR"
	progressBar.Frame.Visible = step.Goal ~= nil
	if step.Goal then
		progressBar.Set(0, formatGoal(step, 0), true)
	end
	UITheme.tween(overallFill, 0.3, { Size = UDim2.fromScale((index - 1) / TutorialData.Count, 1) })
	-- Passo novo: o título pisca na cor de destaque
	titleLabel.TextColor3 = ACCENT
	UITheme.tween(titleLabel, 0.4, { TextColor3 = Colors.Text })

	function state.Set(value)
		if state.Ended or state.Completed or paused then return end
		state.Value = value
		if step.Goal then
			progressBar.Set(math.clamp(value / step.Goal, 0, 1), formatGoal(step, value))
			if value >= step.Goal then
				completeStep(state)
			end
		end
	end
	function state.Add(amount)
		state.Set(state.Value + amount)
	end
	function state.Complete()
		if paused then return end
		completeStep(state)
	end
	function state.Show(ratio, text)
		progressBar.Set(math.clamp(ratio, 0, 1), text)
	end
	function state.Connect(signal, callback)
		local connection = signal:Connect(callback)
		table.insert(state.Connections, connection)
		return connection
	end
	-- Liga no Humanoid atual e no de cada vez que renascer
	function state.ForCharacter(bind)
		local function onCharacter(character)
			local humanoid = character:WaitForChild("Humanoid", 10)
			if humanoid and not state.Ended then
				local connection = bind(humanoid)
				if connection then
					table.insert(state.Connections, connection)
				end
			end
		end
		state.Connect(player.CharacterAdded, onCharacter)
		if player.Character then
			task.spawn(onCharacter, player.Character)
		end
	end

	local check = step.Check and Checks[step.Check]
	if check then
		state.Update = check(state)
	end
end

local function begin()
	if running or player:GetAttribute("TutorialDone") ~= false or menuOpen() then return end
	running = true
	paused = false
	screen.Enabled = true
	local saved = player:GetAttribute("TutorialStep")
	startStep(if type(saved) == "number" then saved else 1)
end

----------------------------------------------------------------------------------------------------
-- Botões e teclas
----------------------------------------------------------------------------------------------------

local function pressContinue()
	if current and not current.Step.Check and not paused then
		completeStep(current)
	end
end
continueButton.MouseButton1Click:Connect(pressContinue)

UserInputService.InputBegan:Connect(function(input, processed)
	if processed or not running or paused then return end
	if input.KeyCode == Enum.KeyCode.Return or input.KeyCode == Enum.KeyCode.KeypadEnter then
		pressContinue()
	end
end)

-- Pular pede confirmação (um segundo clique em até 3 s)
skipButton.MouseButton1Click:Connect(function()
	if not running then return end
	if os.clock() <= skipArmedUntil then
		finish(true)
		return
	end
	skipArmedUntil = os.clock() + 3
	skipButton.Text = `<u><font color="#{KEY_HEX}">Clique de novo para pular</font></u>`
	task.delay(3, function()
		if os.clock() >= skipArmedUntil then
			skipButton.Text = "<u>Pular tutorial</u>"
		end
	end)
end)

----------------------------------------------------------------------------------------------------
-- Quadro a quadro: conferência, destaque, alvo no mapa e lugar do painel
----------------------------------------------------------------------------------------------------

local pulse = 0
local docked = false

local function hidePointers()
	ring.Visible = false
	ringArrow.Visible = false
	edgeArrow.Visible = false
	edgeDistance.Visible = false
	marker.Enabled = false
end

local function updateAnchor(step)
	local anchor = step.Anchor and findAnchor(step.Anchor)
	if not anchor or not isShown(anchor) then
		ring.Visible = false
		ringArrow.Visible = false
		return
	end
	local padding = 6 + math.sin(pulse * 6) * 3
	local position = anchor.AbsolutePosition - screen.AbsolutePosition
	local size = anchor.AbsoluteSize
	ring.Position = UDim2.fromOffset(position.X - padding, position.Y - padding)
	ring.Size = UDim2.fromOffset(size.X + padding * 2, size.Y + padding * 2)
	ringStroke.Transparency = 0.15 + (math.sin(pulse * 6) + 1) * 0.2
	ring.Visible = true
	-- Setinha do lado de dentro da tela: em cima do elemento (apontando para baixo) ou embaixo (para cima)
	local viewport = screen.AbsoluteSize
	local center = position + size / 2
	local bounce = math.sin(pulse * 8) * 5
	if center.Y > viewport.Y * 0.5 then
		ringArrow.Text = "▼"
		ringArrow.Position = UDim2.fromOffset(center.X, position.Y - padding - 22 + bounce)
	else
		ringArrow.Text = "▲"
		ringArrow.Position = UDim2.fromOffset(center.X, position.Y + size.Y + padding + 22 - bounce)
	end
	ringArrow.Visible = true
end

local function updateTarget(step)
	local part, label, height
	if step.Target then
		part, label, height = resolveTarget(step.Target)
	end
	local _, _, root = getCharacter()
	local camera = workspace.CurrentCamera
	if not part or not root or not camera then
		marker.Enabled = false
		edgeArrow.Visible = false
		edgeDistance.Visible = false
		return
	end
	local worldPosition = part.Position + Vector3.new(0, height, 0)
	local distance = (worldPosition - root.Position).Magnitude
	local distanceText = `{math.floor(distance)} m`

	marker.Adornee = part
	marker.StudsOffsetWorldSpace = Vector3.new(0, height, 0)
	markerName.Text = `{label}  ·  {distanceText}`
	markerArrow.Position = UDim2.new(0.5, 0, 0, 20 + math.sin(pulse * 8) * 4)
	marker.Enabled = true

	local point, onScreen = camera:WorldToViewportPoint(worldPosition)
	local viewport = camera.ViewportSize
	local inside = onScreen and point.Z > 0 and point.X > EDGE_MARGIN and point.X < viewport.X - EDGE_MARGIN
		and point.Y > EDGE_MARGIN and point.Y < viewport.Y - EDGE_MARGIN
	if inside then
		edgeArrow.Visible = false
		edgeDistance.Visible = false
		return
	end
	local center = viewport / 2
	local direction = Vector2.new(point.X, point.Y) - center
	if point.Z < 0 then
		direction = -direction
	end
	if direction.Magnitude < 1 then
		direction = Vector2.new(0, 1)
	end
	local half = center - Vector2.new(EDGE_MARGIN, EDGE_MARGIN)
	local fit = math.min(half.X / math.max(math.abs(direction.X), 1e-3), half.Y / math.max(math.abs(direction.Y), 1e-3))
	local spot = center + direction * fit
	edgeArrow.Position = UDim2.fromOffset(spot.X, spot.Y)
	edgeArrow.Rotation = math.deg(math.atan2(direction.Y, direction.X)) + 90
	edgeArrow.Visible = true
	edgeDistance.Position = UDim2.fromOffset(spot.X - direction.Unit.X * 34, spot.Y - direction.Unit.Y * 34)
	edgeDistance.Text = distanceText
	edgeDistance.Visible = true
end

-- Com a árvore ou o inventário abertos (tela cheia, HUD escondida), o painel desce para o pé da tela
local function updateDock()
	local wantDock = guiOpen("SkillTree") or guiOpen("Inventory")
	if wantDock == docked then return end
	docked = wantDock
	panel.AnchorPoint = if docked then Vector2.new(0.5, 1) else Vector2.new(0.5, 0)
	panel.Position = if docked then UDim2.new(0.5, 0, 1, -20) else UDim2.new(0.5, 0, 0, PANEL_TOP)
end

RunService.RenderStepped:Connect(function(dt)
	if not running then return end
	-- Menu principal aberto: tudo pausa e some
	local nowPaused = menuOpen()
	if nowPaused ~= paused then
		paused = nowPaused
		screen.Enabled = not paused
		if paused then
			hidePointers()
		end
	end
	if paused or not current then return end

	pulse += dt
	local step = current.Step
	if current.Update and not current.Completed then
		current.Update(dt)
	end
	if step.Dummy then
		setDummy(true) -- o boneco sumiu (ou não chegou): pede de novo
	end
	updateDock()
	updateAnchor(step)
	updateTarget(step)
end)

----------------------------------------------------------------------------------------------------
-- Início
----------------------------------------------------------------------------------------------------

player:GetAttributeChangedSignal("TutorialDone"):Connect(function()
	if player:GetAttribute("TutorialDone") == true then
		if running then
			stop()
		end
	else
		begin()
	end
end)

-- "Refazer tutorial" (HUD) com o tutorial rodando: o servidor volta o passo para 1
player:GetAttributeChangedSignal("TutorialStep"):Connect(function()
	local step = player:GetAttribute("TutorialStep")
	if running and current and step == 1 and current.Index > 1 then
		startStep(1)
	end
end)

player:GetAttributeChangedSignal("MenuOpen"):Connect(function()
	if not running and not menuOpen() then
		begin()
	end
end)

task.spawn(function()
	if not game:IsLoaded() then
		game.Loaded:Wait()
	end
	-- A tela de carregamento e o menu principal vêm antes (o menu marca MenuOpen enquanto está aberto)
	local deadline = os.clock() + 60
	while playerGui:FindFirstChild("LoadingScreen") and os.clock() < deadline do
		task.wait(0.2)
	end
	deadline = os.clock() + 30
	while player:GetAttribute("TutorialDone") == nil and os.clock() < deadline do
		task.wait(0.2)
	end
	task.wait(0.5)
	-- O menu fecha: TitleScreen.Enabled muda (o atributo MenuOpen some junto)
	local title = guiByName("TitleScreen")
	if title then
		title:GetPropertyChangedSignal("Enabled"):Connect(function()
			if not running and not menuOpen() then
				task.wait(0.6) -- deixa a cortina do menu sair antes
				begin()
			end
		end)
	end
	begin()
end)
