-- Tela de escolha do save (pedido do usuário, 2026-10-05: "CHOOSE A SAVE" antes do menu). O servidor (PlayerData) só
-- carrega o perfil depois da escolha: Remotes.SaveSlots traz os saves da conta e Remotes.SaveSlotAction escolhe
-- ("Select"), apaga ("Delete") ou pede a lista ("List"). O 1º save é grátis; o 2º e o 3º pedem o passe ExtraSlots.
-- Com o save carregado (atributo SaveSlot no player), a tela some e o menu principal (MainMenu) aparece por baixo.
-- Textos em inglês (o jogo passou a ter o inglês como língua de origem; o Roblox traduz para os outros idiomas).
local GuiService = game:GetService("GuiService")
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPlayer = game:GetService("StarterPlayer")
local UserInputService = game:GetService("UserInputService")

local Remotes = require(ReplicatedStorage:WaitForChild("Remotes"))
local UITheme = require(ReplicatedStorage:WaitForChild("UITheme"))
local AppearanceData = require(ReplicatedStorage:WaitForChild("AppearanceData"))
local ClanData = require(ReplicatedStorage:WaitForChild("ClanData"))
local PathData = require(ReplicatedStorage:WaitForChild("PathData"))
local CombatStyles = require(ReplicatedStorage:WaitForChild("CombatStyles"))
local GamepassConfig = require(ReplicatedStorage:WaitForChild("GamepassConfig"))

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- Já escolheu (o script reiniciou): nada a fazer
if player:GetAttribute("SaveSlot") ~= nil then return end

local Colors = UITheme.Colors
local ACCENT = Color3.fromRGB(255, 122, 26) -- o laranja do menu principal
local CARD = Color3.fromRGB(16, 16, 20)
local LINE = Color3.fromRGB(70, 70, 78)
local FONT = { Heavy = Enum.Font.BuilderSansExtraBold, Bold = Enum.Font.BuilderSansBold, Medium = Enum.Font.BuilderSansMedium }
local CARD_W, CARD_H, GAP = 300, 470, 30
local CAMERA = CFrame.lookAt(Vector3.new(0, 0.4, 12), Vector3.new(0, -0.2, 0))
local PATH_NAMES = { None = "Human", Hunter = "Hunter", Fiend = "Fiend" }

local new = UITheme.new

local screen = UITheme.screen("SaveSelect", 40, playerGui)
screen.IgnoreGuiInset = true

local backdrop = new("Frame", {
	Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = Color3.fromRGB(10, 10, 12),
	Parent = screen,
})
UITheme.gradient(backdrop, { Color3.fromRGB(26, 24, 28), Color3.fromRGB(6, 6, 8) }, 90)
-- Brilho laranja quase transparente atrás dos cartões (o mesmo clima do menu)
local glow = new("Frame", {
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.55),
	Size = UDim2.fromOffset(900, 900),
	BackgroundColor3 = ACCENT,
	BackgroundTransparency = 0.93,
	Parent = backdrop,
})
UITheme.corner(glow, UDim.new(0.5, 0))

local content = new("Frame", {
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromOffset(1060, 680),
	BackgroundTransparency = 1,
	Parent = backdrop,
})
UITheme.autoScale(content, 1060, 680)

new("TextLabel", {
	Position = UDim2.fromOffset(0, 10),
	Size = UDim2.new(1, 0, 0, 60),
	BackgroundTransparency = 1,
	Font = FONT.Heavy,
	TextSize = 52,
	TextColor3 = Colors.Text,
	Text = "CHOOSE A SAVE",
	Parent = content,
})
local subtitle = new("TextLabel", {
	Position = UDim2.fromOffset(0, 72),
	Size = UDim2.new(1, 0, 0, 26),
	BackgroundTransparency = 1,
	Font = FONT.Medium,
	TextSize = 19,
	TextColor3 = Colors.TextDim,
	Text = "Choose a save to play on. Each save is a separate character with its own progress.",
	Parent = content,
})
local titleLine = new("Frame", {
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 108),
	Size = UDim2.new(0.8, 0, 0, 2),
	BackgroundColor3 = Colors.White,
	BorderSizePixel = 0,
	Parent = content,
})
new("UIGradient", {
	Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.5, 0.1),
		NumberSequenceKeypoint.new(1, 1),
	}),
	Parent = titleLine,
})

local status = new("TextLabel", {
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.55),
	Size = UDim2.fromOffset(600, 30),
	BackgroundTransparency = 1,
	Font = FONT.Bold,
	TextSize = 20,
	TextColor3 = Colors.TextDim,
	Text = "Loading your saves...",
	Parent = content,
})
local warning = new("TextLabel", {
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, -6),
	Size = UDim2.new(1, 0, 0, 22),
	BackgroundTransparency = 1,
	Font = FONT.Medium,
	TextSize = 15,
	TextColor3 = Colors.Orange,
	Text = "",
	Parent = content,
})

local row = new("Frame", {
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 150),
	Size = UDim2.fromOffset(3 * CARD_W + 2 * GAP, CARD_H + 20),
	BackgroundTransparency = 1,
	Visible = false,
	Parent = content,
})
UITheme.list(row, GAP, Enum.FillDirection.Horizontal, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Center)

-- ================= Prévia do personagem =================

-- Modelo base: o StarterCharacter (R6 liso do jogo) ou uma cópia do personagem atual
local function baseModel()
	local template = StarterPlayer:FindFirstChild("StarterCharacter")
	local source = template or player.Character
	if not source then return nil end
	local wasArchivable = source.Archivable
	source.Archivable = true
	local ok, clone = pcall(function()
		return source:Clone()
	end)
	source.Archivable = wasArchivable
	if not ok or not clone then return nil end
	for _, descendant in clone:GetDescendants() do
		if descendant:IsA("LuaSourceContainer") or descendant:IsA("Tool") or descendant:IsA("ForceField")
			or descendant:IsA("Sound") or descendant:IsA("BillboardGui") or descendant:IsA("ParticleEmitter")
			or (descendant:IsA("Accessory") and descendant:GetAttribute("EquippedItem") ~= nil) then
			descendant:Destroy()
		end
	end
	return clone
end

local idleId = CombatStyles.Animation(CombatStyles.Styles.Punhos, "Idle")

local function buildPreview(parent, appearance)
	local view = new("ViewportFrame", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 56),
		Size = UDim2.fromOffset(CARD_W - 40, 250),
		BackgroundTransparency = 1,
		Ambient = Color3.fromRGB(150, 150, 160),
		LightColor = Color3.fromRGB(255, 240, 225),
		LightDirection = Vector3.new(-0.4, -1, -0.6),
		Parent = parent,
	})
	local world = new("WorldModel", { Parent = view })
	local camera = Instance.new("Camera")
	camera.FieldOfView = 28
	camera.CFrame = CAMERA
	camera.Parent = view
	view.CurrentCamera = camera

	local model = baseModel()
	if not model or not model:FindFirstChild("HumanoidRootPart") then return end
	pcall(AppearanceData.Apply, model, appearance)
	local root = model.HumanoidRootPart
	root.Anchored = true
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	end
	model:PivotTo(CFrame.Angles(0, math.pi * 0.92, 0))
	model.Parent = world
	if humanoid and idleId then
		local animator = humanoid:FindFirstChildOfClass("Animator") or new("Animator", { Parent = humanoid })
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
end

-- ================= Cartões =================

local cards = {}
local state = nil
local busy = false
local chosen = false
local confirmLayer -- (criado mais abaixo)

local function decorate(card)
	UITheme.corner(card, UDim.new(0, 8))
	local outer = UITheme.stroke(card, LINE, 2, 0)
	-- Moldura de dentro (o "enfeite" duplo do cartão)
	local inner = new("Frame", {
		Position = UDim2.fromOffset(7, 7),
		Size = UDim2.new(1, -14, 1, -14),
		BackgroundTransparency = 1,
		Parent = card,
	})
	UITheme.corner(inner, UDim.new(0, 5))
	UITheme.stroke(inner, Colors.White, 1, 0.75)
	return outer
end

local function divider(parent, y)
	local line = new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, y),
		Size = UDim2.new(1, -40, 0, 2),
		BackgroundColor3 = ACCENT,
		BorderSizePixel = 0,
		Parent = parent,
	})
	new("UIGradient", {
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.5, 0),
			NumberSequenceKeypoint.new(1, 1),
		}),
		Parent = line,
	})
end

local function text(parent, props)
	local base = {
		BackgroundTransparency = 1,
		Font = FONT.Bold,
		TextSize = 16,
		TextColor3 = Colors.Text,
		Parent = parent,
	}
	for key, value in props do
		base[key] = value
	end
	return new("TextLabel", base)
end

local function infoLines(summary)
	local lines = {}
	local clan = summary.Clan and ClanData.Get(summary.Clan)
	table.insert(lines, `Clan : <b>{if clan then clan.Name else "None"}</b>`)
	if summary.Path == "Hunter" then
		local contract = summary.Contract and PathData.Contracts[summary.Contract]
		table.insert(lines, `Contract : <b>{if contract then contract.DisplayName else "None"}</b>`)
	elseif summary.Path == "Fiend" then
		local fiend = summary.FiendType and PathData.FiendTypes[summary.FiendType]
		table.insert(lines, `Fiend : <b>{if fiend then fiend.DisplayName else "?"}</b>`)
	else
		table.insert(lines, "Path : <b>Not chosen</b>")
	end
	table.insert(lines, `Gold : <b>{UITheme.formatNumber(summary.Gold)}</b>`)
	return table.concat(lines, "\n")
end

local function selectSlot(slot)
	if busy or chosen or not state then return end
	busy = true
	status.Text = "Loading save " .. slot .. "..."
	status.Visible = true
	row.Visible = false
	Remotes.SaveSlotAction:FireServer("Select", slot)
	-- Sem resposta (passe ainda não confirmado, por exemplo): volta para a lista
	task.delay(10, function()
		if not chosen and player:GetAttribute("SaveSlot") == nil then
			busy = false
			status.Visible = false
			row.Visible = true
		end
	end)
end

local function askDelete(slot, summary)
	confirmLayer.Show(slot, summary)
end

local function buildCard(slot, summary, unlocked)
	local card = new("TextButton", {
		Name = "Slot" .. slot,
		Size = UDim2.fromOffset(CARD_W, CARD_H),
		BackgroundColor3 = CARD,
		BackgroundTransparency = 0.08,
		AutoButtonColor = false,
		Selectable = true,
		LayoutOrder = slot,
		Parent = row,
	})
	local stroke = decorate(card)
	local scale = new("UIScale", { Parent = card })
	text(card, {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -16, 0, 14),
		Size = UDim2.fromOffset(80, 16),
		Font = FONT.Medium,
		TextSize = 12,
		TextColor3 = Colors.TextDim,
		TextXAlignment = Enum.TextXAlignment.Right,
		Text = "SLOT " .. slot,
	})

	if not unlocked then
		card.BackgroundTransparency = 0.3
		text(card, {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, 0, 0.36, 0),
			Size = UDim2.fromOffset(120, 110),
			Font = UITheme.Fonts.Display,
			TextSize = 84,
			TextColor3 = Colors.TextDim,
			Text = "鍵",
		})
		text(card, {
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0.55, 0),
			Size = UDim2.new(1, -40, 0, 24),
			TextSize = 20,
			Text = "LOCKED",
		})
		local pass = GamepassConfig.Passes.ExtraSlots
		text(card, {
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0.55, 30),
			Size = UDim2.new(1, -50, 0, 40),
			Font = FONT.Medium,
			TextSize = 14,
			TextWrapped = true,
			TextColor3 = Colors.TextDim,
			Text = `Get the "{pass.Name}" pass to unlock slots 2 and 3.`,
		})
		local buy = UITheme.button({
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -34),
			Size = UDim2.fromOffset(190, 44),
			Font = FONT.Heavy,
			TextSize = 16,
			Text = if pass.Id > 0 then "UNLOCK" else "COMING SOON",
			Parent = card,
		}, if pass.Id > 0 then ACCENT else Colors.PanelLight)
		buy.MouseButton1Click:Connect(function()
			if pass.Id > 0 then
				pcall(MarketplaceService.PromptGamePassPurchase, MarketplaceService, player, pass.Id)
			end
		end)
		card.MouseButton1Click:Connect(function()
			if pass.Id > 0 then
				pcall(MarketplaceService.PromptGamePassPurchase, MarketplaceService, player, pass.Id)
			end
		end)
	elseif summary then
		local pathName = PATH_NAMES[summary.Path] or "Human"
		text(card, {
			Position = UDim2.fromOffset(0, 18),
			Size = UDim2.new(1, 0, 0, 30),
			Font = FONT.Heavy,
			TextSize = 24,
			RichText = true,
			Text = `Level {summary.Level}  <font color="#7a7a82">|</font>  {pathName}`,
		})
		buildPreview(card, summary.Appearance)
		divider(card, 318)
		text(card, {
			Position = UDim2.fromOffset(28, 332),
			Size = UDim2.new(1, -56, 0, 72),
			Font = FONT.Medium,
			TextSize = 15,
			RichText = true,
			LineHeight = 1.15,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextYAlignment = Enum.TextYAlignment.Top,
			Text = infoLines(summary),
		})
		if not summary.Created then
			text(card, {
				Position = UDim2.fromOffset(28, 404),
				Size = UDim2.new(1, -56, 0, 18),
				Font = FONT.Medium,
				TextSize = 13,
				TextColor3 = ACCENT,
				TextXAlignment = Enum.TextXAlignment.Left,
				Text = "Character not created yet",
			})
		end
		if not state.Offline then
			local delete = new("TextButton", {
				AnchorPoint = Vector2.new(1, 1),
				Position = UDim2.new(1, -20, 1, -18),
				Size = UDim2.fromOffset(86, 28),
				BackgroundColor3 = Colors.PanelLight,
				AutoButtonColor = true,
				Font = FONT.Bold,
				TextSize = 13,
				TextColor3 = Colors.TextDim,
				Text = "DELETE",
				Parent = card,
			})
			UITheme.corner(delete, UDim.new(0, 5))
			delete.MouseButton1Click:Connect(function()
				askDelete(slot, summary)
			end)
		end
		card.MouseButton1Click:Connect(function()
			selectSlot(slot)
		end)
	else
		text(card, {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, 0, 0.42, 0),
			Size = UDim2.fromOffset(160, 160),
			Font = FONT.Heavy,
			TextSize = 150,
			Text = "+",
		})
		text(card, {
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0.6, 0),
			Size = UDim2.new(1, -40, 0, 22),
			TextSize = 17,
			Text = "NEW SLOT",
		})
		divider(card, CARD_H - 70)
		card.MouseButton1Click:Connect(function()
			selectSlot(slot)
		end)
	end

	-- Destaque ao passar o mouse / selecionar no controle
	local function highlight(on)
		UITheme.tween(stroke, 0.15, { Color = if on then ACCENT else LINE })
		UITheme.tween(scale, 0.15, { Scale = if on then 1.03 else 1 })
	end
	card.MouseEnter:Connect(function() highlight(true) end)
	card.MouseLeave:Connect(function() highlight(false) end)
	card.SelectionGained:Connect(function() highlight(true) end)
	card.SelectionLost:Connect(function() highlight(false) end)
	return card
end

local function render()
	for _, card in cards do
		card:Destroy()
	end
	table.clear(cards)
	if not state then return end
	for slot = 1, state.Count do
		cards[slot] = buildCard(slot, state.Slots[slot], state.Unlocked[slot])
	end
	status.Visible = false
	row.Visible = true
	warning.Text = if state.Offline
		then "Saves are offline (Studio without API access or Roblox is down): progress in this session will not be saved."
		else ""
	if UserInputService.GamepadEnabled and cards[1] then
		GuiService.SelectedObject = cards[1]
	end
end

-- ================= Confirmação de apagar =================

do
	local layer = new("TextButton", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Colors.Black,
		BackgroundTransparency = 0.35,
		AutoButtonColor = false,
		Visible = false,
		ZIndex = 10,
		Parent = screen,
	})
	local panel = new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(440, 220),
		BackgroundColor3 = CARD,
		ZIndex = 11,
		Parent = layer,
	})
	UITheme.corner(panel, UDim.new(0, 8))
	UITheme.stroke(panel, ACCENT, 2, 0)
	local title = text(panel, {
		Position = UDim2.fromOffset(0, 22),
		Size = UDim2.new(1, 0, 0, 30),
		Font = FONT.Heavy,
		TextSize = 24,
		ZIndex = 12,
	})
	local body = text(panel, {
		Position = UDim2.fromOffset(30, 60),
		Size = UDim2.new(1, -60, 0, 64),
		Font = FONT.Medium,
		TextSize = 15,
		TextWrapped = true,
		TextColor3 = Colors.TextDim,
		ZIndex = 12,
	})
	local yes = UITheme.button({
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -24, 1, -22),
		Size = UDim2.fromOffset(180, 46),
		Font = FONT.Heavy,
		TextSize = 16,
		Text = "DELETE",
		ZIndex = 12,
		Parent = panel,
	}, Colors.Accent)
	local no = UITheme.button({
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 24, 1, -22),
		Size = UDim2.fromOffset(180, 46),
		Font = FONT.Heavy,
		TextSize = 16,
		Text = "CANCEL",
		ZIndex = 12,
		Parent = panel,
	}, Colors.PanelLight)
	local target = nil
	local armedAt = 0
	confirmLayer = {
		Show = function(slot, summary)
			target = slot
			armedAt = os.clock()
			title.Text = `Delete save {slot}?`
			body.Text = `Level {summary.Level} {PATH_NAMES[summary.Path] or "Human"} will be erased forever: level, Gold, clan, items and everything else in this save. This cannot be undone.`
			layer.Visible = true
			if UserInputService.GamepadEnabled then
				GuiService.SelectedObject = no
			end
		end,
	}
	local function hide()
		layer.Visible = false
		target = nil
	end
	no.MouseButton1Click:Connect(hide)
	layer.MouseButton1Click:Connect(hide)
	yes.MouseButton1Click:Connect(function()
		-- Meio segundo de trava: um clique duplo no DELETE do cartão não apaga sem querer
		if not target or os.clock() - armedAt < 0.5 then return end
		Remotes.SaveSlotAction:FireServer("Delete", target)
		hide()
		status.Text = "Deleting..."
		status.Visible = true
		row.Visible = false
	end)
end

-- ================= Servidor =================

Remotes.SaveSlots.OnClientEvent:Connect(function(data)
	if chosen or type(data) ~= "table" or type(data.Slots) ~= "table" or type(data.Unlocked) ~= "table" then return end
	data.Count = if type(data.Count) == "number" then math.clamp(data.Count, 1, 6) else 3
	state = data
	busy = false
	render()
end)

local function finish()
	if chosen then return end
	chosen = true
	status.Text = "Loading your character..."
	status.Visible = true
	row.Visible = false
	warning.Text = ""
	subtitle.Visible = true
	-- Espera os dados chegarem (o menu principal mostra os botões com eles) e sai devagar
	local deadline = os.clock() + 15
	while not player:FindFirstChild("leaderstats") and os.clock() < deadline do
		task.wait(0.1)
	end
	if GuiService.SelectedObject and GuiService.SelectedObject:IsDescendantOf(screen) then
		GuiService.SelectedObject = nil
	end
	for _, object in screen:GetDescendants() do
		if object:IsA("TextLabel") or object:IsA("TextButton") then
			UITheme.tween(object, 0.35, { TextTransparency = 1, BackgroundTransparency = 1 })
		elseif object:IsA("Frame") or object:IsA("ViewportFrame") then
			UITheme.tween(object, 0.4, { BackgroundTransparency = 1 })
		elseif object:IsA("UIStroke") then
			UITheme.tween(object, 0.35, { Transparency = 1 })
		end
	end
	task.wait(0.45)
	screen:Destroy()
end

player:GetAttributeChangedSignal("SaveSlot"):Connect(function()
	if player:GetAttribute("SaveSlot") ~= nil then
		task.spawn(finish)
	end
end)

-- Pede a lista até ela chegar (o servidor pode ainda estar lendo os saves)
task.spawn(function()
	while not state and not chosen and screen.Parent do
		Remotes.SaveSlotAction:FireServer("List")
		task.wait(3)
	end
end)
