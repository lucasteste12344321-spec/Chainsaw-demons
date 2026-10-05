-- Missões: tracker das missões ativas (direita, no meio da tela) e diálogo dos NPCs de missão.
-- O servidor manda o estado via Remotes.QuestEvent e os diálogos via Remotes.QuestDialog.
-- Se o NPC for de um caminho (Fase 4), o diálogo traz data.PathOffer e mostra um cartão com "VER CAMINHO".
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local CollectionService = game:GetService("CollectionService")

local Remotes = require(ReplicatedStorage:WaitForChild("Remotes"))
local PathData = require(ReplicatedStorage:WaitForChild("PathData"))
local UITheme = require(ReplicatedStorage:WaitForChild("UITheme"))

local Colors = UITheme.Colors
local Fonts = UITheme.Fonts

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- Texto que cresce para baixo conforme o conteúdo
local function autoLabel(props)
	local label = UITheme.label(props)
	label.TextWrapped = true
	label.AutomaticSize = Enum.AutomaticSize.Y
	if not props.Size then
		label.Size = UDim2.new(1, 0, 0, 0)
	end
	return label
end

-- ================= Tracker =================

local trackerGui = UITheme.screen("QuestTracker", 1, playerGui)

local tracker = UITheme.panel({
	AnchorPoint = Vector2.new(1, 0.5),
	Position = UDim2.new(1, -16, 0.45, 0),
	Size = UDim2.fromOffset(280, 0),
	AutomaticSize = Enum.AutomaticSize.Y,
	BackgroundTransparency = 0.2,
	Visible = false,
	Parent = trackerGui,
})
UITheme.padding(tracker, 10, 12, 12, 12)
UITheme.list(tracker, 10)
tracker:SetAttribute("TutorialAnchor", "QuestTracker") -- o tutorial destaca a lista de missões
local trackerScale = UITheme.autoScale(tracker, 1100, 700)
-- No celular a lateral direita é dos botões de ação (HUB_GUI) e o minimapa sobe para o canto de cima: a lista fica em
-- cima, à esquerda do minimapa (mesma escala dos dois: autoScale 1100 x 700; o minimapa tem 190 de diâmetro)
if (UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled)
	or game:GetService("ReplicatedStorage"):GetAttribute("ForceMobileHUD") == true then
	tracker.AnchorPoint = Vector2.new(1, 0)
	local function placeTracker()
		tracker.Position = UDim2.new(1, -(24 + 190 * trackerScale.Scale), 0, 12)
	end
	trackerScale:GetPropertyChangedSignal("Scale"):Connect(placeTracker)
	placeTracker()
end

local header = UITheme.new("Frame", {
	Size = UDim2.new(1, 0, 0, 22),
	BackgroundTransparency = 1,
	LayoutOrder = 0,
	Parent = tracker,
})
UITheme.label({
	Size = UDim2.new(1, -40, 1, 0),
	Font = Fonts.Display,
	TextSize = 17,
	TextColor3 = Colors.Orange,
	Text = "📋 MISSÕES",
	Parent = header,
})
local toggleHint = UITheme.label({
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.fromScale(1, 0),
	Size = UDim2.new(0, 40, 1, 0),
	TextXAlignment = Enum.TextXAlignment.Right,
	Font = Fonts.Title,
	TextSize = 12,
	TextColor3 = Colors.TextDim,
	Parent = header,
})

-- O cabeçalho inteiro é um botão transparente: tocar/clicar recolhe ou expande (no celular não há tecla N)
local headerButton = UITheme.new("TextButton", {
	Size = UDim2.fromScale(1, 1),
	BackgroundTransparency = 1,
	AutoButtonColor = false,
	Text = "",
	ZIndex = 2,
	Parent = header,
})

local collapsed = false
local lastQuests = {}
local lastProgress = {} -- [questId..index] = progresso, para destacar o que acabou de mudar

-- "[N] −" com teclado; só "−" / "+" (maior, para o dedo) em aparelhos sem teclado
local function updateToggleHint(count)
	local keyboard = UserInputService.KeyboardEnabled
	local key = if keyboard then "[N] " else ""
	toggleHint.TextSize = if keyboard then 12 else 18
	toggleHint.Text = if collapsed then `{key}+ ({count})` else `{key}−`
end
updateToggleHint(0)

local function renderTracker(quests)
	lastQuests = quests
	for _, child in tracker:GetChildren() do
		if child:IsA("Frame") and child ~= header then
			child:Destroy()
		end
	end

	tracker.Visible = #quests > 0
	updateToggleHint(#quests)
	if collapsed then return end

	for index, quest in quests do
		local block = UITheme.new("Frame", {
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundTransparency = 1,
			LayoutOrder = index,
			Parent = tracker,
		})
		UITheme.list(block, 3)

		autoLabel({
			Font = Fonts.Title,
			TextSize = 15,
			RichText = true,
			Text = `<font color="#{Colors.Accent:ToHex()}">◆</font> {quest.Name}`,
			LayoutOrder = 0,
			Parent = block,
		})

		for i, objective in quest.Objectives do
			local done = objective.Progress >= objective.Amount
			local key = quest.Id .. "#" .. i
			local changed = lastProgress[key] ~= nil and lastProgress[key] ~= objective.Progress
			lastProgress[key] = objective.Progress

			local text = autoLabel({
				Font = Fonts.Body,
				TextSize = 13,
				TextColor3 = if done then Colors.Green else Colors.TextDim,
				Text = `{if done then "✔" else "•"} {objective.Text}: {objective.Progress}/{objective.Amount}`,
				LayoutOrder = i * 2 - 1,
				Parent = block,
			})
			if changed then
				text.TextColor3 = Colors.Gold
				UITheme.tween(text, 0.8, { TextColor3 = if done then Colors.Green else Colors.TextDim })
			end

			local bar = UITheme.bar({
				Size = UDim2.new(1, 0, 0, 5),
				LayoutOrder = i * 2,
				Parent = block,
			}, if done then { Colors.Green, Colors.Green } else { Colors.Orange, Colors.Accent })
			bar.Set(objective.Progress / math.max(1, objective.Amount), nil, true)
		end
	end
end

local function toggleTracker()
	collapsed = not collapsed
	renderTracker(lastQuests)
end

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed or player:GetAttribute("MenuOpen") then return end
	if input.KeyCode == Enum.KeyCode.N then
		toggleTracker()
	end
end)
headerButton.MouseButton1Click:Connect(toggleTracker)

-- ================= Diálogo de NPC =================

local dialogGui = UITheme.screen("QuestDialog", 6, playerGui)
dialogGui.Enabled = false

local DIALOG_W, DIALOG_H = 480, 460
local dialogHolder = UITheme.new("Frame", {
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromOffset(DIALOG_W, DIALOG_H),
	BackgroundTransparency = 1,
	Parent = dialogGui,
})
UITheme.autoScale(dialogHolder, DIALOG_W + 20, DIALOG_H + 20)

local dialog = UITheme.panel({
	Size = UDim2.fromScale(1, 1),
	Active = true,
	Parent = dialogHolder,
})
local dialogScale = UITheme.new("UIScale", { Parent = dialog })

local npcNameLabel = UITheme.label({
	Position = UDim2.fromOffset(22, 14),
	Size = UDim2.new(1, -90, 0, 30),
	Font = Fonts.Display,
	TextSize = 24,
	TextColor3 = Colors.Orange,
	TextTruncate = Enum.TextTruncate.AtEnd,
	Parent = dialog,
})
UITheme.new("Frame", {
	Position = UDim2.fromOffset(22, 46),
	Size = UDim2.fromOffset(56, 4),
	BackgroundColor3 = Colors.Accent,
	BorderSizePixel = 0,
	Parent = dialog,
})

local closeButton = UITheme.button({
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, -16, 0, 14),
	Size = UDim2.fromOffset(36, 36),
	Text = "×",
	TextSize = 18,
	Parent = dialog,
}, Colors.Accent)

-- Balão de fala
local bubble = UITheme.new("Frame", {
	Position = UDim2.fromOffset(22, 62),
	Size = UDim2.new(1, -44, 0, 0),
	AutomaticSize = Enum.AutomaticSize.Y,
	BackgroundColor3 = Colors.PanelLight,
	BackgroundTransparency = 0.15,
	BorderSizePixel = 0,
	Parent = dialog,
})
UITheme.corner(bubble, UDim.new(0, 10))
UITheme.stroke(bubble, Colors.Stroke, 1, 0.4)
UITheme.padding(bubble, 10, 14)
local greetingLabel = autoLabel({
	Font = Fonts.Body,
	TextSize = 15,
	Parent = bubble,
})

local list = UITheme.new("ScrollingFrame", {
	Position = UDim2.fromOffset(22, 124),
	Size = UDim2.new(1, -44, 1, -124 - 16),
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	ScrollBarThickness = 5,
	ScrollBarImageColor3 = Colors.Accent,
	CanvasSize = UDim2.new(),
	AutomaticCanvasSize = Enum.AutomaticSize.Y,
	Parent = dialog,
})
UITheme.list(list, 10)
UITheme.padding(list, 2, 8, 2, 2)

local GuiService = game:GetService("GuiService")

local function closeDialog()
	dialogGui.Enabled = false
	if GuiService.SelectedObject and GuiService.SelectedObject:IsDescendantOf(dialogGui) then
		GuiService.SelectedObject = nil
	end
end

local function rewardChip(parent, text, color, order)
	local chip = UITheme.new("Frame", {
		Size = UDim2.fromOffset(0, 24),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundColor3 = Colors.Black,
		BackgroundTransparency = 0.4,
		LayoutOrder = order,
		Parent = parent,
	})
	UITheme.corner(chip, UDim.new(0.5, 0))
	UITheme.stroke(chip, color, 1, 0.3)
	UITheme.padding(chip, 0, 10)
	UITheme.label({
		Size = UDim2.fromScale(0, 1),
		AutomaticSize = Enum.AutomaticSize.X,
		Font = Fonts.Title,
		TextSize = 13,
		TextColor3 = color,
		Text = text,
		Parent = chip,
	})
end

local function questCard(quest, order, npcId, canAccept)
	local card = UITheme.new("Frame", {
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = Colors.PanelLight,
		BackgroundTransparency = 0.15,
		BorderSizePixel = 0,
		LayoutOrder = order,
		Parent = list,
	})
	UITheme.corner(card, UDim.new(0, 10))
	UITheme.stroke(card, if canAccept then Colors.Gold else Colors.Stroke, 1.5, if canAccept then 0.3 else 0.5)
	UITheme.padding(card, 12, 14)
	UITheme.list(card, 6)

	autoLabel({
		Font = Fonts.Title,
		TextSize = 18,
		Text = quest.Name,
		LayoutOrder = 1,
		Parent = card,
	})
	autoLabel({
		Font = Fonts.Light,
		TextSize = 14,
		TextColor3 = Colors.TextDim,
		Text = quest.Description,
		LayoutOrder = 2,
		Parent = card,
	})

	for i, objective in quest.Objectives do
		autoLabel({
			Font = Fonts.Body,
			TextSize = 14,
			Text = `• {objective.Text}: {objective.Progress}/{objective.Amount}`,
			LayoutOrder = 2 + i,
			Parent = card,
		})
	end

	local rewards = UITheme.new("Frame", {
		Size = UDim2.new(1, 0, 0, 24),
		BackgroundTransparency = 1,
		LayoutOrder = 50,
		Parent = card,
	})
	UITheme.list(rewards, 6, Enum.FillDirection.Horizontal)
	local r = quest.Rewards or {}
	if r.XP then rewardChip(rewards, `⭐ {r.XP} XP`, Color3.fromRGB(200, 160, 255), 1) end
	if r.Gold then rewardChip(rewards, `💰 {r.Gold}`, Colors.Gold, 2) end
	if r.StatusPoints then rewardChip(rewards, `✚ {r.StatusPoints} ponto(s)`, Colors.Green, 3) end
	if r.DodgeLevel then rewardChip(rewards, `避 Esquiva {r.DodgeLevel}`, Color3.fromRGB(170, 220, 255), 4) end

	-- Recompensa de contrato (Caçador) numa linha própria, porque o nome é comprido
	local contract = type(r.Contract) == "string" and PathData.Contracts[r.Contract]
	if contract then
		local contractRow = UITheme.new("Frame", {
			Size = UDim2.new(1, 0, 0, 24),
			BackgroundTransparency = 1,
			LayoutOrder = 51,
			Parent = card,
		})
		UITheme.list(contractRow, 6, Enum.FillDirection.Horizontal)
		rewardChip(contractRow, `{contract.Icon} Contrato: {contract.DisplayName}`, PathData.Paths.Hunter.Color, 1)
	end

	if canAccept then
		local accept = UITheme.button({
			Size = UDim2.fromOffset(140, 36),
			LayoutOrder = 60,
			Font = Fonts.Display,
			Text = "ACEITAR",
			TextSize = 16,
			Parent = card,
		}, Colors.Green)
		-- Trava local: se o servidor recusar (limite de missões, longe do NPC), o botão volta depois de 2 s.
		-- Se aceitar, o diálogo é refeito e este botão some antes disso.
		local waiting = false
		accept.MouseButton1Click:Connect(function()
			if waiting then return end
			waiting = true
			accept.Text = "..."
			Remotes.QuestAction:FireServer("Accept", quest.Id, npcId)
			task.delay(2, function()
				if accept.Parent then
					waiting = false
					accept.Text = "ACEITAR"
				end
			end)
		end)
	else
		autoLabel({
			Font = Fonts.Title,
			TextSize = 13,
			TextColor3 = Colors.Blue,
			Text = "EM ANDAMENTO",
			LayoutOrder = 60,
			Parent = card,
		})
		-- Missão de treino do Treinador (objetivo Spar/Duel aberto): começa o treino com a cópia dele
		local training
		for _, objective in quest.Objectives do
			if (objective.Type == "Spar" or objective.Type == "Duel") and objective.Progress < objective.Amount then
				training = objective.Type
			end
		end
		if training and quest.Giver == npcId then
			local trainButton = UITheme.button({
				Size = UDim2.fromOffset(160, 36),
				LayoutOrder = 61,
				Font = Fonts.Display,
				Text = if training == "Duel" then "DUELAR" else "TREINAR",
				TextSize = 16,
				Parent = card,
			})
			trainButton.MouseButton1Click:Connect(function()
				Remotes.QuestAction:FireServer("Train", quest.Id, npcId)
				closeDialog()
			end)
		end
	end
end

-- Cartão do caminho deste NPC (data.PathOffer = { Path, Mode, Reason? }, ver docs/fase4-caminhos.md)
local function pathCard(offer, npcId, order)
	local info = type(offer.Path) == "string" and PathData.Paths[offer.Path]
	if not info or offer.Path == "None" then return end
	local color = info.Color

	local card = UITheme.new("Frame", {
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = Colors.PanelLight,
		BackgroundTransparency = 0.15,
		BorderSizePixel = 0,
		LayoutOrder = order,
		Parent = list,
	})
	UITheme.corner(card, UDim.new(0, 10))
	UITheme.stroke(card, color, 2, 0.15)
	UITheme.padding(card, 12, 14)
	UITheme.list(card, 6)

	autoLabel({
		Font = Fonts.Display,
		TextSize = 18,
		TextColor3 = color,
		Text = `{UITheme.PathIcons[offer.Path] or "🧭"} CAMINHO DO {UITheme.upper(info.DisplayName)}`,
		LayoutOrder = 1,
		Parent = card,
	})
	autoLabel({
		Font = Fonts.Light,
		TextSize = 14,
		TextColor3 = Colors.TextDim,
		Text = info.Description,
		LayoutOrder = 2,
		Parent = card,
	})

	local modeText, modeColor
	if offer.Mode == "Choose" then
		modeText, modeColor = "✔ Você já pode escolher este caminho. A escolha é permanente.", Colors.Green
	elseif offer.Mode == "Reset" then
		modeText, modeColor = "★ Você segue este caminho. Aqui também dá para renunciar a ele.", Colors.Gold
	else
		local reason = if type(offer.Reason) == "string" and offer.Reason ~= ""
			then offer.Reason
			else "Você ainda não pode seguir este caminho."
		modeText, modeColor = `🔒 {reason}`, Colors.Accent
	end
	autoLabel({
		Font = Fonts.Title,
		TextSize = 14,
		TextColor3 = modeColor,
		Text = modeText,
		LayoutOrder = 3,
		Parent = card,
	})

	local button = UITheme.button({
		Size = UDim2.fromOffset(170, 36),
		LayoutOrder = 4,
		Font = Fonts.Display,
		Text = "VER CAMINHO",
		TextSize = 16,
		Parent = card,
	}, color)
	button.MouseButton1Click:Connect(function()
		-- O servidor responde com Remotes.PathDialog (tela do PathGUI)
		Remotes.PathAction:FireServer("Open", nil, npcId)
		closeDialog()
	end)
end

-- Cartão da evolução do contrato (Mestre dos Pactos; ContractService.GetOffer): forma atual, próxima forma, o que
-- ela pede (com barras) e o botão de fundir quando a próxima é a V2
local FORM_COLOR = Color3.fromRGB(255, 140, 30)
local function evolutionCard(offer, npcId, order)
	local card = UITheme.new("Frame", {
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = Colors.PanelLight,
		BackgroundTransparency = 0.15,
		BorderSizePixel = 0,
		LayoutOrder = order,
		Parent = list,
	})
	UITheme.corner(card, UDim.new(0, 10))
	UITheme.stroke(card, FORM_COLOR, 2, 0.15)
	UITheme.padding(card, 12, 14)
	UITheme.list(card, 6)

	if offer.Mode == "Locked" then
		autoLabel({ Font = Fonts.Display, TextSize = 18, TextColor3 = FORM_COLOR, Text = "EVOLUÇÃO DO PACTO", LayoutOrder = 1, Parent = card })
		autoLabel({ Font = Fonts.Title, TextSize = 14, TextColor3 = Colors.Accent, Text = `🔒 {offer.Reason or ""}`, LayoutOrder = 2, Parent = card })
		return
	end

	local glyph = offer.Glyph or "🦊"
	autoLabel({
		Font = Fonts.Display,
		TextSize = 18,
		TextColor3 = FORM_COLOR,
		Text = `{glyph} {UITheme.upper(offer.ContractName or "")}: {UITheme.upper(offer.FormName or "")}`,
		LayoutOrder = 1,
		Parent = card,
	})
	if offer.Mode == "Max" then
		autoLabel({ Font = Fonts.Title, TextSize = 14, TextColor3 = Colors.Gold, Text = "★ Seu pacto já está na forma máxima.", LayoutOrder = 2, Parent = card })
		return
	end

	local nextTitle = if offer.FusionName then `PRÓXIMA FORMA: {UITheme.upper(offer.NextName or "")} ({offer.FusionName})` else `PRÓXIMA FORMA: {UITheme.upper(offer.NextName or "")}`
	autoLabel({ Font = Fonts.Title, TextSize = 15, Text = nextTitle, LayoutOrder = 2, Parent = card })
	if offer.Description then
		autoLabel({ Font = Fonts.Light, TextSize = 14, TextColor3 = Colors.TextDim, Text = offer.Description, LayoutOrder = 3, Parent = card })
	end

	-- Requisitos: texto, barra e número
	for index, requirement in offer.Requirements or {} do
		local row = UITheme.new("Frame", {
			Size = UDim2.new(1, 0, 0, 34),
			BackgroundTransparency = 1,
			LayoutOrder = 3 + index,
			Parent = card,
		})
		local color = if requirement.Done then Colors.Green else Colors.Text
		UITheme.label({
			Size = UDim2.new(1, -90, 0, 16),
			Font = Fonts.Title,
			TextSize = 13,
			TextColor3 = color,
			Text = `{if requirement.Done then "✓" else "•"} {requirement.Text}`,
			Parent = row,
		})
		UITheme.label({
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.fromScale(1, 0),
			Size = UDim2.fromOffset(90, 16),
			Font = Fonts.Number,
			TextSize = 13,
			TextColor3 = color,
			TextXAlignment = Enum.TextXAlignment.Right,
			Text = if requirement.Need == 1 then (if requirement.Done then "feita" else "pendente") else `{requirement.Have}/{requirement.Need}`,
			Parent = row,
		})
		local bar = UITheme.bar({
			Position = UDim2.fromOffset(0, 20),
			Size = UDim2.new(1, 0, 0, 8),
			Parent = row,
		}, if requirement.Done then { Colors.Green, Colors.Green } else Colors.XP, 1)
		bar.Label.Visible = false
		bar.Set(math.clamp((requirement.Have or 0) / math.max(1, requirement.Need or 1), 0, 1), nil, true)
	end

	local order2 = 10
	if offer.Mode == "Fuse" then
		local button = UITheme.button({
			Size = UDim2.fromOffset(200, 38),
			LayoutOrder = order2,
			Font = Fonts.Display,
			Text = if offer.Ready then "UNIR ESTILO E CONTRATO" else "AINDA NÃO",
			TextSize = 16,
			AutoButtonColor = false,
			Parent = card,
		}, if offer.Ready then FORM_COLOR else Colors.PanelLight)
		button.MouseButton1Click:Connect(function()
			if not offer.Ready then return end
			Remotes.ContractAction:FireServer("Fuse", npcId)
			closeDialog()
		end)
	else
		autoLabel({
			Font = Fonts.Light,
			TextSize = 13,
			TextColor3 = Colors.TextDim,
			Text = "Essa forma vem da provação final: as missões aparecem aqui quando você estiver pronto.",
			LayoutOrder = order2,
			Parent = card,
		})
	end
end

local dialogNPCId -- NPC do diálogo aberto (para fechar quando o jogador se afasta dele)

local function openDialog(data)
	dialogNPCId = data.NPCId
	for _, child in list:GetChildren() do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end

	npcNameLabel.Text = UITheme.upper(tostring(data.NPCName))
	greetingLabel.Text = `"{data.Greeting}"`

	-- Cartão do caminho primeiro (NPC Veterano / Anciao)
	if type(data.PathOffer) == "table" then
		pathCard(data.PathOffer, data.NPCId, 0)
	end
	-- Evolução do contrato (Mestre dos Pactos)
	if type(data.Evolution) == "table" then
		evolutionCard(data.Evolution, data.NPCId, 0)
	end

	local order = 0
	for _, quest in data.Available or {} do
		order += 1
		questCard(quest, order, data.NPCId, true)
	end
	for _, quest in data.Active or {} do
		order += 1
		questCard(quest, order, data.NPCId, false)
	end

	if not dialogGui.Enabled then
		dialogGui.Enabled = true
		dialogScale.Scale = 0.88
		UITheme.tween(dialogScale, 0.22, { Scale = 1 }, Enum.EasingStyle.Back)
	end
	-- Controle (Xbox): já começa com o primeiro botão do diálogo selecionado (A aperta; B fecha)
	if string.sub(UserInputService:GetLastInputType().Name, 1, 7) == "Gamepad" then
		task.defer(function()
			local first
			for _, item in list:GetDescendants() do
				if item:IsA("GuiButton") and item.Visible then
					first = item
					break
				end
			end
			GuiService.SelectedObject = first or closeButton
		end)
	end
end

-- B do controle fecha o diálogo
UserInputService.InputBegan:Connect(function(input)
	if input.KeyCode == Enum.KeyCode.ButtonB and dialogGui.Enabled then
		closeDialog()
	end
end)

closeButton.MouseButton1Click:Connect(closeDialog)

-- NPC de missão (tag QuestGiver): a parte usada para medir a distância, igual ao servidor
local NPC_RANGE = 20 -- o servidor recusa ações a mais que isso do NPC
local function npcPart(model)
	if model:IsA("BasePart") then return model end
	local root = model:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then return root end
	if model:IsA("Model") and model.PrimaryPart then return model.PrimaryPart end
	return model:FindFirstChildWhichIsA("BasePart", true)
end

local function npcIdOf(model)
	local id = model:GetAttribute("NPCId")
	return if type(id) == "string" and id ~= "" then id else model.Name
end

-- Distância até o NPC mais próximo com esse NPCId, ou nil se ele não existir no cliente (ex.: streaming)
local function distanceToNPC(npcId, position)
	if type(npcId) ~= "string" then return nil end
	local best
	for _, model in CollectionService:GetTagged("QuestGiver") do
		if model:IsDescendantOf(workspace) and npcIdOf(model) == npcId then
			local part = npcPart(model)
			if part then
				local distance = (part.Position - position).Magnitude
				if not best or distance < best then
					best = distance
				end
			end
		end
	end
	return best
end

-- Fecha o diálogo se o jogador se afastar do NPC ou morrer
task.spawn(function()
	local openedAt
	while true do
		task.wait(0.5)
		if dialogGui.Enabled then
			local character = player.Character
			local humanoid = character and character:FindFirstChildOfClass("Humanoid")
			local root = character and character:FindFirstChild("HumanoidRootPart")
			if not root or not humanoid or humanoid.Health <= 0 then
				closeDialog()
			else
				local distance = distanceToNPC(dialogNPCId, root.Position)
				if distance then
					if distance > NPC_RANGE then
						closeDialog()
					end
				else
					-- NPC não carregado no cliente: mede o quanto o jogador andou desde que abriu
					openedAt = openedAt or root.Position
					if (root.Position - openedAt).Magnitude > NPC_RANGE then
						closeDialog()
					end
				end
			end
		else
			openedAt = nil
		end
	end
end)

Remotes.QuestEvent.OnClientEvent:Connect(function(data)
	if type(data) == "table" and data.Action == "State" then
		renderTracker(data.Quests or {})
	end
end)

Remotes.QuestDialog.OnClientEvent:Connect(function(data)
	if type(data) == "table" then
		openDialog(data)
	end
end)

-- Pede o estado atual (as missões podem ter sido dadas antes deste script rodar)
Remotes.QuestEvent:FireServer()
