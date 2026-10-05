-- Tela do caminho (Fase 4): escolher Caçador ou Infernal, renunciar ao caminho ou ver por que ainda não pode.
-- O servidor abre com Remotes.PathDialog e recebe a decisão por Remotes.PathAction (ver docs/fase4-caminhos.md).
-- Nomes, descrições, custos e habilidades vêm do PathData.
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage:WaitForChild("Remotes"))
local PathData = require(ReplicatedStorage:WaitForChild("PathData"))
local ContractData = require(ReplicatedStorage:WaitForChild("ContractData"))
local UITheme = require(ReplicatedStorage:WaitForChild("UITheme"))

local Colors = UITheme.Colors
local Fonts = UITheme.Fonts

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local NPC_TAG = "QuestGiver"
local NPC_RANGE = 20 -- distância máxima até o NPC (a mesma que o servidor exige no PathModule)
local CLOSE_DISTANCE = 20 -- studs andados até fechar sozinho, só quando o NPC não é encontrado no cliente
local CONFIRM_DELAY = 2 -- segundos até o botão de confirmar liberar (dá tempo de ler o aviso)

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

local function hex(color)
	return "#" .. color:ToHex()
end

local function teamName(path)
	local info = PathData.Paths[path]
	local team = info and PathData.Teams[info.Team]
	return if team then team.DisplayName elseif info then info.Team else "?"
end

local function goldValue()
	local leaderstats = player:FindFirstChild("leaderstats")
	local gold = leaderstats and leaderstats:FindFirstChild("Gold")
	return if gold then gold.Value else 0
end

local function resetCostOf(data)
	return if type(data.ResetCost) == "number" then data.ResetCost else PathData.ResetCost
end

-- Parte do NPC usada para medir a distância (mesma regra do PathModule no servidor)
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
	for _, model in CollectionService:GetTagged(NPC_TAG) do
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

-- ================= Janela =================

local gui = UITheme.screen("PathDialog", 7, playerGui)
gui.Enabled = false

local PANEL_W, PANEL_H = 720, 540
local CONTENT_W = PANEL_W - 44 - 14 -- largura útil dentro da área com rolagem

local holder = UITheme.new("Frame", {
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromOffset(PANEL_W, PANEL_H),
	BackgroundTransparency = 1,
	Parent = gui,
})
UITheme.autoScale(holder, PANEL_W + 20, PANEL_H + 20)

local panel = UITheme.panel({
	Size = UDim2.fromScale(1, 1),
	Active = true,
	Parent = holder,
})
local panelScale = UITheme.new("UIScale", { Parent = panel })

-- Cabeçalho: ícone do caminho, título e nome do NPC
local iconCircle = UITheme.new("Frame", {
	Position = UDim2.fromOffset(22, 16),
	Size = UDim2.fromOffset(52, 52),
	BackgroundColor3 = Colors.Accent,
	Parent = panel,
})
UITheme.corner(iconCircle, UDim.new(0.5, 0))
UITheme.stroke(iconCircle, Colors.Black, 2, 0.3)
UITheme.gradient(iconCircle, { Color3.fromRGB(255, 255, 255), Color3.fromRGB(110, 110, 110) })
local iconLabel = UITheme.label({
	Size = UDim2.fromScale(1, 1),
	TextXAlignment = Enum.TextXAlignment.Center,
	TextSize = 28,
	Parent = iconCircle,
})

local titleLabel = UITheme.label({
	Position = UDim2.fromOffset(86, 14),
	Size = UDim2.new(1, -150, 0, 32),
	Font = Fonts.Display,
	TextSize = 26,
	TextTruncate = Enum.TextTruncate.AtEnd,
	Parent = panel,
})
local subtitleLabel = UITheme.label({
	Position = UDim2.fromOffset(86, 46),
	Size = UDim2.new(1, -150, 0, 18),
	Font = Fonts.Body,
	TextSize = 14,
	TextColor3 = Colors.TextDim,
	TextTruncate = Enum.TextTruncate.AtEnd,
	Parent = panel,
})
local accentBar = UITheme.new("Frame", {
	Position = UDim2.fromOffset(22, 78),
	Size = UDim2.fromOffset(64, 4),
	BackgroundColor3 = Colors.Accent,
	BorderSizePixel = 0,
	Parent = panel,
})

local closeButton = UITheme.button({
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, -16, 0, 16),
	Size = UDim2.fromOffset(36, 36),
	Text = "×",
	TextSize = 18,
	Parent = panel,
}, Colors.Accent)

-- Conteúdo com rolagem
local content = UITheme.new("ScrollingFrame", {
	Position = UDim2.fromOffset(22, 94),
	Size = UDim2.new(1, -44, 1, -94 - 84),
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	ScrollBarThickness = 5,
	ScrollBarImageColor3 = Colors.Accent,
	CanvasSize = UDim2.new(),
	AutomaticCanvasSize = Enum.AutomaticSize.Y,
	Parent = panel,
})
UITheme.list(content, 12)
UITheme.padding(content, 2, 12, 4, 2)

-- Rodapé: aviso e botão principal
local footer = UITheme.new("Frame", {
	AnchorPoint = Vector2.new(0, 1),
	Position = UDim2.new(0, 22, 1, -16),
	Size = UDim2.new(1, -44, 0, 52),
	BackgroundTransparency = 1,
	Parent = panel,
})
UITheme.new("Frame", {
	Position = UDim2.fromOffset(0, -9),
	Size = UDim2.new(1, 0, 0, 1),
	BackgroundColor3 = Colors.Stroke,
	BackgroundTransparency = 0.5,
	BorderSizePixel = 0,
	Parent = footer,
})
local warningLabel = UITheme.label({
	Size = UDim2.new(1, -250, 1, 0),
	TextWrapped = true,
	RichText = true,
	Font = Fonts.Title,
	TextSize = 13,
	TextColor3 = Colors.Gold,
	Text = "",
	Parent = footer,
})
local actionButton = UITheme.button({
	AnchorPoint = Vector2.new(1, 0.5),
	Position = UDim2.fromScale(1, 0.5),
	Size = UDim2.fromOffset(234, 48),
	Font = Fonts.Display,
	TextSize = 15,
	Parent = footer,
}, Colors.Accent)

-- ================= Confirmação =================

-- Cobre o painel inteiro (é um botão para bloquear cliques nos cartões por trás)
local confirmOverlay = UITheme.new("TextButton", {
	Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = Colors.Black,
	BackgroundTransparency = 0.3,
	AutoButtonColor = false,
	Text = "",
	Visible = false,
	ZIndex = 20,
	Parent = panel,
})
UITheme.corner(confirmOverlay, UDim.new(0, 12))

local confirmBox = UITheme.panel({
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromOffset(470, 260),
	Active = true,
	Parent = confirmOverlay,
})
local confirmScale = UITheme.new("UIScale", { Parent = confirmBox })

local confirmTitle = UITheme.label({
	Position = UDim2.fromOffset(20, 16),
	Size = UDim2.new(1, -40, 0, 28),
	Font = Fonts.Display,
	TextSize = 22,
	TextColor3 = Colors.Accent,
	Parent = confirmBox,
})
UITheme.new("Frame", {
	Position = UDim2.fromOffset(20, 48),
	Size = UDim2.fromOffset(56, 4),
	BackgroundColor3 = Colors.Accent,
	BorderSizePixel = 0,
	Parent = confirmBox,
})
local confirmMessage = UITheme.label({
	Position = UDim2.fromOffset(20, 62),
	Size = UDim2.new(1, -40, 1, -62 - 70),
	TextWrapped = true,
	RichText = true,
	TextYAlignment = Enum.TextYAlignment.Top,
	Font = Fonts.Body,
	TextSize = 15,
	Parent = confirmBox,
})
local cancelButton = UITheme.button({
	AnchorPoint = Vector2.new(0, 1),
	Position = UDim2.new(0, 20, 1, -16),
	Size = UDim2.fromOffset(150, 44),
	Font = Fonts.Display,
	TextSize = 16,
	Text = "VOLTAR",
	Parent = confirmBox,
}, Colors.PanelLight)
local confirmButton = UITheme.button({
	AnchorPoint = Vector2.new(1, 1),
	Position = UDim2.new(1, -20, 1, -16),
	Size = UDim2.fromOffset(220, 44),
	Font = Fonts.Display,
	TextSize = 16,
	Parent = confirmBox,
}, Colors.Accent)

local confirmToken = 0
local confirmReady = false
local confirmCallback

local function hideConfirm()
	confirmToken += 1
	confirmCallback = nil
	confirmReady = false
	confirmOverlay.Visible = false
end

local function askConfirm(titleText, message, confirmText, color, callback)
	confirmToken += 1
	local token = confirmToken
	confirmCallback = callback
	confirmReady = false
	confirmTitle.Text = titleText
	confirmMessage.Text = message
	confirmButton.BackgroundColor3 = Colors.PanelLight
	confirmButton.TextTransparency = 0.4
	confirmOverlay.Visible = true
	confirmScale.Scale = 0.85
	UITheme.tween(confirmScale, 0.2, { Scale = 1 }, Enum.EasingStyle.Back)

	-- Contagem antes de liberar: evita confirmar sem ler
	task.spawn(function()
		for remaining = CONFIRM_DELAY, 1, -1 do
			if token ~= confirmToken then return end
			confirmButton.Text = `{confirmText} ({remaining})`
			task.wait(1)
		end
		if token ~= confirmToken then return end
		confirmReady = true
		confirmButton.Text = confirmText
		confirmButton.BackgroundColor3 = color
		confirmButton.TextTransparency = 0
	end)
end

confirmButton.MouseButton1Click:Connect(function()
	if not confirmReady or not confirmCallback then return end
	local callback = confirmCallback
	hideConfirm()
	callback()
end)
cancelButton.MouseButton1Click:Connect(function()
	hideConfirm()
end)

-- ================= Estado =================

local current -- dados do diálogo aberto (Remotes.PathDialog)
local selectedId -- contrato ou tipo de Infernal escolhido no modo Choose
local cards = {} -- [id] = { Card, Stroke, Scale, Badge }
local goldLine -- linha "Seu Gold" do modo Reset
local actionEnabled = false
local openedAt -- posição do jogador quando abriu (fecha se andar demais)

local function clearContent()
	for _, child in content:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	table.clear(cards)
	goldLine = nil
end

local function closeDialog()
	hideConfirm()
	gui.Enabled = false
	current = nil
	selectedId = nil
end
closeButton.MouseButton1Click:Connect(closeDialog)

-- ================= Blocos de conteúdo =================

local function sectionTitle(text, order)
	return UITheme.label({
		Size = UDim2.new(1, 0, 0, 20),
		Font = Fonts.Display,
		TextSize = 15,
		TextColor3 = Colors.Orange,
		Text = text,
		LayoutOrder = order,
		Parent = content,
	})
end

-- Caixa com borda e uma lista de linhas
local function box(order, strokeColor)
	local frame = UITheme.new("Frame", {
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = Colors.PanelLight,
		BackgroundTransparency = 0.2,
		BorderSizePixel = 0,
		LayoutOrder = order,
		Parent = content,
	})
	UITheme.corner(frame, UDim.new(0, 10))
	UITheme.stroke(frame, strokeColor or Colors.Stroke, 1.5, 0.3)
	UITheme.padding(frame, 10, 14)
	UITheme.list(frame, 6)
	return frame
end

local function line(parent, text, order, color, font, size)
	return autoLabel({
		Font = font or Fonts.Body,
		TextSize = size or 14,
		TextColor3 = color or Colors.Text,
		RichText = true,
		Text = text,
		LayoutOrder = order,
		Parent = parent,
	})
end

-- Os sacrifícios de cada caminho (o que o jogador paga)
local function sacrificeLines(path)
	if path == "Hunter" then
		local regenPerMinute = math.floor(PathData.LifespanRegen * 60 + 0.5)
		return {
			"❤ Cada contrato tira uma parte da sua <b>vida máxima</b> enquanto existir.",
			`⏳ Usar um poder gasta <b>Tempo de Vida</b> (máximo {PathData.MaxLifespan}, recupera {regenPerMinute} por minuto).`,
			`📜 Você começa com 1 contrato. Os outros vêm de missões (até {PathData.MaxContracts}).`,
			`🤝 Você continua no time <b>{teamName("Hunter")}</b>.`,
		}
	elseif path == "Fiend" then
		return {
			`💪 Corpo de demônio: <b>+{UITheme.formatPercent(PathData.FiendPassive.MaxHPBonus)}</b> de vida máxima.`,
			"🩸 Os poderes custam o seu próprio <b>sangue</b>: gastam vida e não funcionam com a vida baixa.",
			"🚫 Infernais <b>não podem</b> fazer contratos com demônios.",
			`🔥 Você sai do time {teamName("None")} e entra no time <b>{teamName("Fiend")}</b>.`,
		}
	end
	return {}
end

local function sacrificeBox(path, order)
	local frame = box(order, Colors.AccentDark)
	line(frame, "O PREÇO DESTE CAMINHO", 0, Colors.Accent, Fonts.Display, 14)
	for index, text in sacrificeLines(path) do
		line(frame, text, index, Colors.Text, Fonts.Body, 14)
	end
	return frame
end

-- Habilidade com tecla, tipo, dano, recarga e custo
local function skillBlock(parent, skill, slotKey, order, color)
	local frame = UITheme.new("Frame", {
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = Colors.Black,
		BackgroundTransparency = 0.5,
		BorderSizePixel = 0,
		LayoutOrder = order,
		Parent = parent,
	})
	UITheme.corner(frame, UDim.new(0, 8))
	UITheme.padding(frame, 8, 10)
	UITheme.list(frame, 3)

	local kind = UITheme.SkillKinds[skill.Kind]
	local kindText = if kind then `  <font color="{hex(Colors.TextDim)}" size="12">({kind})</font>` else ""
	line(frame, `<font color="{hex(color)}">[{PathData.KeyLabel(slotKey)}]</font> {skill.Icon} {skill.Name}{kindText}`, 1, Colors.Text, Fonts.Title, 14)
	line(frame, UITheme.skillStats(skill), 2, Colors.TextDim, Fonts.Body, 12)
	local costText, costColor = UITheme.skillCost(skill)
	line(frame, `Custo: {costText}`, 3, costColor, Fonts.Title, 12)
	return frame
end

-- Cartão base (contrato ou tipo de Infernal). Selecionável só no modo Choose.
local function optionCard(parent, icon, name, order, width, color, selectable)
	local props = {
		Size = UDim2.fromOffset(width, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = Colors.PanelLight,
		BackgroundTransparency = 0.15,
		BorderSizePixel = 0,
		LayoutOrder = order,
		Parent = parent,
	}
	if selectable then
		props.AutoButtonColor = false
		props.Text = ""
	end
	local card = UITheme.new(if selectable then "TextButton" else "Frame", props)
	UITheme.corner(card, UDim.new(0, 12))
	local stroke = UITheme.stroke(card, Colors.Stroke, 1.5, 0.35)
	UITheme.padding(card, 12, 14)
	UITheme.list(card, 8)
	local scale = UITheme.new("UIScale", { Parent = card })

	local header = UITheme.new("Frame", {
		Size = UDim2.new(1, 0, 0, 46),
		BackgroundTransparency = 1,
		LayoutOrder = 1,
		Parent = card,
	})
	local circle = UITheme.new("Frame", {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.fromScale(0, 0.5),
		Size = UDim2.fromOffset(44, 44),
		BackgroundColor3 = color,
		Parent = header,
	})
	UITheme.corner(circle, UDim.new(0.5, 0))
	UITheme.gradient(circle, { Color3.fromRGB(255, 255, 255), Color3.fromRGB(110, 110, 110) })
	UITheme.label({
		Size = UDim2.fromScale(1, 1),
		TextXAlignment = Enum.TextXAlignment.Center,
		TextSize = 24,
		Text = icon,
		Parent = circle,
	})
	UITheme.label({
		Position = UDim2.fromOffset(54, 0),
		Size = UDim2.new(1, -54 - 32, 1, 0),
		TextWrapped = true,
		Font = Fonts.Title,
		TextSize = 18,
		Text = name,
		Parent = header,
	})

	-- Marca de selecionado (canto de cima)
	local badge = UITheme.new("Frame", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		Size = UDim2.fromOffset(26, 26),
		BackgroundColor3 = color,
		Visible = false,
		Parent = header,
	})
	UITheme.corner(badge, UDim.new(0.5, 0))
	UITheme.stroke(badge, Colors.White, 1.5, 0.2)
	UITheme.label({
		Size = UDim2.fromScale(1, 1),
		TextXAlignment = Enum.TextXAlignment.Center,
		Font = Fonts.Title,
		TextSize = 15,
		Text = "✓",
		Parent = badge,
	})

	return { Card = card, Stroke = stroke, Scale = scale, Badge = badge }
end

local function contractCard(parent, contractId, order, width, color, selectable)
	local contract = PathData.Contracts[contractId]
	local entry = optionCard(parent, contract.Icon, contract.DisplayName, order, width, color, selectable)
	local card = entry.Card

	line(card, contract.Description, 2, Colors.TextDim, Fonts.Light, 13)

	local hpCost = contract.HPCost or 0
	if hpCost > 0 then
		UITheme.chip(card, `❤ −{UITheme.formatPercent(hpCost)} de vida máxima`, Colors.Health[1], 3, 12)
	else
		UITheme.chip(card, "❤ Sem perda de vida máxima", Colors.Green, 3, 12)
	end

	-- Contrato com formas (ContractData): passivo e os dois poderes da forma V1 (teclas V e B)
	local hasForms = ContractData.HasForms(contractId)
	local passive = UITheme.passiveText(if hasForms then ContractData.Passive(contractId, "V1") else contract.Passive)
	if passive then
		line(card, `✨ Passivo: {passive}`, 4, Colors.Gold, Fonts.Title, 13)
	end

	if hasForms then
		for index, slot in { "Z", "X" } do
			local skill = ContractData.GetSkill(contractId, "V1", slot)
			if skill then
				skillBlock(card, skill, slot, 4 + index, color)
			end
		end
		local fusionStyle = ContractData.Get(contractId).FusionStyle
		if fusionStyle then
			line(card, `🔥 Com maestria, funde com o estilo {fusionStyle} (Mestre dos Pactos).`, 8, color, Fonts.Title, 12)
		end
	elseif contract.Skill then
		skillBlock(card, contract.Skill, "Z", 5, color)
	end
	return entry
end

local function fiendCard(parent, fiendId, order, width, color, selectable)
	local fiendType = PathData.FiendTypes[fiendId]
	local entry = optionCard(parent, fiendType.Icon, fiendType.DisplayName, order, width, color, selectable)
	local card = entry.Card

	line(card, fiendType.Description, 2, Colors.TextDim, Fonts.Light, 13)
	UITheme.chip(card, `❤ +{UITheme.formatPercent(PathData.FiendPassive.MaxHPBonus)} de vida máxima`, Colors.Green, 3, 12)

	local passive = UITheme.passiveText(fiendType.Passive)
	if passive then
		line(card, `✨ Passivo: {passive}`, 4, Colors.Gold, Fonts.Title, 13)
	end

	for index, slotKey in { "Z", "X" } do
		local skill = fiendType.Skills and fiendType.Skills[slotKey]
		if skill then
			skillBlock(card, skill, slotKey, 4 + index, color)
		end
	end
	return entry
end

-- Opções do diálogo: as que o servidor mandou (validadas pelo PathData) ou, sem lista, as do PathData
local function optionIds(data)
	local source = if data.Path == "Hunter" then PathData.Contracts else PathData.FiendTypes
	local ids = {}
	if type(data.Options) == "table" then
		for _, id in data.Options do
			if type(id) == "string" and source[id] and not table.find(ids, id) then
				table.insert(ids, id)
			end
		end
	end
	if #ids == 0 then
		for id, info in source do
			if data.Path ~= "Hunter" or info.Unlock == "Path" then
				table.insert(ids, id)
			end
		end
		table.sort(ids)
	end
	return ids
end

-- ================= Rodapé =================

local function setAction(text, color, enabled)
	actionEnabled = enabled
	actionButton.Text = text
	actionButton.BackgroundColor3 = color
	actionButton.TextTransparency = if enabled then 0 else 0.4
end

local function updateGoldLine()
	if not goldLine or not current then return end
	local gold = goldValue()
	local enough = gold >= resetCostOf(current)
	goldLine.TextColor3 = if enough then Colors.Green else Colors.Accent
	goldLine.Text = `Seu Gold: 💰 {UITheme.formatNumber(gold)}` .. (if enough then "" else "  (não é suficiente)")
end

local function updateFooter()
	if not current then return end
	local info = PathData.Paths[current.Path]
	local cost = resetCostOf(current)

	if current.Mode == "Choose" then
		warningLabel.TextColor3 = Colors.Gold
		warningLabel.Text = `⚠ A escolha é <b>PERMANENTE</b>. Para desistir depois, só pagando `
			.. `{UITheme.formatNumber(cost)} de Gold no NPC do caminho.`
		if selectedId then
			setAction("ESCOLHER ▶", info.Color, true)
		else
			setAction(if current.Path == "Hunter" then "ESCOLHA UM CONTRATO" else "ESCOLHA UM TIPO", Colors.PanelLight, false)
		end
	elseif current.Mode == "Reset" then
		warningLabel.TextColor3 = Colors.Accent
		warningLabel.Text = "⚠ O Gold gasto não volta e você perde os poderes do caminho."
		if goldValue() >= cost then
			setAction("RENUNCIAR", Colors.AccentDark, true)
		else
			setAction("GOLD INSUFICIENTE", Colors.PanelLight, false)
		end
	else
		warningLabel.TextColor3 = Colors.TextDim
		warningLabel.Text = "Volte aqui quando cumprir os requisitos."
		setAction("FECHAR", Colors.PanelLight, true)
	end
end

local function selectOption(id)
	local selected = cards[id]
	if not current or not selected then return end
	selectedId = id
	local color = PathData.Paths[current.Path].Color
	for cardId, entry in cards do
		local on = cardId == id
		entry.Stroke.Color = if on then color else Colors.Stroke
		entry.Stroke.Thickness = if on then 3 else 1.5
		entry.Stroke.Transparency = if on then 0 else 0.35
		entry.Badge.Visible = on
	end
	selected.Scale.Scale = 0.95
	UITheme.tween(selected.Scale, 0.25, { Scale = 1 }, Enum.EasingStyle.Back)
	updateFooter()
end

-- Linha de cartões das opções
local function optionsRow(data, order, selectable)
	local ids = optionIds(data)
	local color = PathData.Paths[data.Path].Color
	local row = UITheme.new("Frame", {
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		LayoutOrder = order,
		Parent = content,
	})
	UITheme.list(row, 14, Enum.FillDirection.Horizontal, Enum.HorizontalAlignment.Center)

	local count = math.max(1, #ids)
	local width = math.min(330, math.floor((CONTENT_W - 14 * (count - 1)) / count))
	for index, id in ids do
		local entry = if data.Path == "Hunter"
			then contractCard(row, id, index, width, color, selectable)
			else fiendCard(row, id, index, width, color, selectable)
		cards[id] = entry

		if selectable then
			local card = entry.Card
			card.MouseButton1Click:Connect(function()
				selectOption(id)
			end)
			card.MouseEnter:Connect(function()
				if selectedId ~= id then
					entry.Stroke.Color = Colors.TextDim
					entry.Stroke.Transparency = 0
				end
			end)
			card.MouseLeave:Connect(function()
				if selectedId ~= id then
					entry.Stroke.Color = Colors.Stroke
					entry.Stroke.Transparency = 0.35
				end
			end)
		end
	end
	return row
end

-- ================= Modos =================

local function renderChoose(data, info)
	line(content, info.Description, 1, Colors.Text, Fonts.Light, 15)
	sacrificeBox(data.Path, 2)
	sectionTitle(if data.Path == "Hunter" then "ESCOLHA SEU CONTRATO" else "ESCOLHA SEU TIPO DE INFERNAL", 3)
	optionsRow(data, 4, true)
end

local function renderReset(data, info)
	local color = info.Color
	local path, contracts, fiendType = PathData.FromPlayer(player)

	-- O que o jogador tem hoje
	local mine = box(1, color)
	line(mine, `Você segue o caminho do <b><font color="{hex(color)}">{info.DisplayName}</font></b>.`, 0, Colors.Text, Fonts.Title, 15)
	if path == "Hunter" then
		for index, contractId in contracts do
			local contract = PathData.Contracts[contractId]
			if contract then
				line(mine, `{contract.Icon} {contract.DisplayName}`, index, Colors.TextDim, Fonts.Body, 14)
			end
		end
	elseif path == "Fiend" then
		local fiend = PathData.FiendTypes[fiendType]
		if fiend then
			line(mine, `{fiend.Icon} {fiend.DisplayName}`, 1, Colors.TextDim, Fonts.Body, 14)
		end
	end

	-- O que acontece ao renunciar
	local lose = box(2, Colors.AccentDark)
	line(lose, "SE VOCÊ RENUNCIAR", 0, Colors.Accent, Fonts.Display, 14)
	line(lose, `↩ Você volta a ser <b>Humano comum</b>, no time <b>{teamName("None")}</b>.`, 1)
	if data.Path == "Hunter" then
		line(lose, "📜 Perde todos os contratos e os poderes V/B.", 2)
		line(lose, "❤ A vida máxima volta ao normal.", 3)
	else
		line(lose, "🩸 Perde o tipo de Infernal, os passivos e os poderes V/B.", 2)
		line(lose, "❤ Perde o bônus de vida máxima do corpo de demônio.", 3)
	end
	line(lose, "🔄 Depois você pode escolher um caminho outra vez.", 4)

	-- Custo
	local costBox = box(3, Colors.Gold)
	line(costBox, `Custo para renunciar: <b>💰 {UITheme.formatNumber(resetCostOf(data))}</b> de Gold`, 1, Colors.Gold, Fonts.Title, 16)
	goldLine = line(costBox, "", 2, Colors.Text, Fonts.Title, 14)
	updateGoldLine()
end

local function renderLocked(data, info)
	local lock = box(1, Colors.Accent)
	line(lock, "🔒 AINDA NÃO", 0, Colors.Accent, Fonts.Display, 16)
	local reason = if type(data.Reason) == "string" and data.Reason ~= ""
		then data.Reason
		else "Você ainda não pode seguir este caminho."
	line(lock, UITheme.escape(reason), 1, Colors.Text, Fonts.Title, 15)
	if PathData.FromPlayer(player) == "None" then
		line(
			lock,
			`Requisitos: level {PathData.MinLevel} e a missão "{PathData.RequiredQuest}" completa.`,
			2,
			Colors.TextDim,
			Fonts.Light,
			13
		)
	end

	line(content, info.Description, 2, Colors.Text, Fonts.Light, 15)
	sacrificeBox(data.Path, 3)
	sectionTitle("O QUE TE ESPERA", 4)
	optionsRow(data, 5, false)
end

-- ================= Abrir / fechar =================

local function openDialog(data)
	local info = PathData.Paths[data.Path]
	if not info or data.Path == "None" then return end
	if data.Mode ~= "Choose" and data.Mode ~= "Reset" and data.Mode ~= "Locked" then return end

	hideConfirm()
	clearContent()
	current = data
	selectedId = nil

	local color = info.Color
	iconCircle.BackgroundColor3 = color
	iconLabel.Text = UITheme.PathIcons[data.Path] or "❔"
	titleLabel.TextColor3 = color
	titleLabel.Text = if data.Mode == "Reset"
		then "RENUNCIAR AO CAMINHO"
		else `CAMINHO DO {UITheme.upper(info.DisplayName)}`
	subtitleLabel.Text = if type(data.NPCName) == "string" then data.NPCName else ""
	accentBar.BackgroundColor3 = color
	content.ScrollBarImageColor3 = color
	content.CanvasPosition = Vector2.zero

	if data.Mode == "Choose" then
		renderChoose(data, info)
	elseif data.Mode == "Reset" then
		renderReset(data, info)
	else
		renderLocked(data, info)
	end
	updateFooter()

	-- O diálogo de missão do mesmo NPC fica por baixo: fecha
	local questDialog = playerGui:FindFirstChild("QuestDialog")
	if questDialog and questDialog:IsA("ScreenGui") then
		questDialog.Enabled = false
	end

	if not gui.Enabled then
		openedAt = nil
		gui.Enabled = true
		panelScale.Scale = 0.88
		UITheme.tween(panelScale, 0.22, { Scale = 1 }, Enum.EasingStyle.Back)
	end
end

actionButton.MouseButton1Click:Connect(function()
	if not current or not actionEnabled then return end
	local data = current
	local info = PathData.Paths[data.Path]
	local cost = UITheme.formatNumber(resetCostOf(data))

	if data.Mode == "Choose" then
		local id = selectedId
		if not id then return end
		local message
		if data.Path == "Hunter" then
			local contract = PathData.Contracts[id]
			message = `Você vai se tornar <b>{info.DisplayName}</b> com o contrato <b>{contract.DisplayName}</b>.`
		else
			local fiendType = PathData.FiendTypes[id]
			message = `Você vai se tornar <b>{fiendType.DisplayName}</b> e entrar no time <b>{teamName("Fiend")}</b>.`
		end
		message ..= `\n\nEsta escolha é <b>permanente</b>. Para desistir, só pagando {cost} de Gold e perdendo tudo o que o caminho deu.`

		askConfirm("ESCOLHA PERMANENTE", message, "CONFIRMAR", info.Color, function()
			local action = if data.Path == "Hunter" then "ChooseHunter" else "ChooseFiend"
			Remotes.PathAction:FireServer(action, id, data.NPCId)
			closeDialog()
		end)
	elseif data.Mode == "Reset" then
		local message = `Você vai pagar <b>{cost} de Gold</b> e voltar a ser <b>Humano comum</b>.`
			.. `\n\nOs poderes e passivos do caminho do {info.DisplayName} serão perdidos. O Gold não volta.`
		askConfirm("RENUNCIAR AO CAMINHO?", message, "RENUNCIAR", Colors.Accent, function()
			Remotes.PathAction:FireServer("Reset", nil, data.NPCId)
			closeDialog()
		end)
	else
		closeDialog()
	end
end)

-- Fecha se o jogador morrer ou sair do alcance do NPC. A distância é medida até o próprio NPC, igual ao
-- servidor (PathModule.isNearNPC), para a tela não ficar aberta com uma escolha que o servidor vai recusar.
task.spawn(function()
	while true do
		task.wait(0.5)
		if gui.Enabled then
			local character = player.Character
			local humanoid = character and character:FindFirstChildOfClass("Humanoid")
			local root = character and character:FindFirstChild("HumanoidRootPart")
			if not humanoid or humanoid.Health <= 0 or not root then
				closeDialog()
			else
				openedAt = openedAt or root.Position
				local npcDistance = distanceToNPC(current and current.NPCId, root.Position)
				if npcDistance then
					if npcDistance > NPC_RANGE then
						closeDialog()
					end
				elseif (root.Position - openedAt).Magnitude > CLOSE_DISTANCE then
					-- NPC não encontrado no cliente: usa a distância andada desde que a tela abriu
					closeDialog()
				end
			end
		else
			openedAt = nil
		end
	end
end)

-- Gold muda enquanto o modo Reset está aberto: atualiza o custo e o botão
task.spawn(function()
	local leaderstats = player:WaitForChild("leaderstats", math.huge)
	local gold = leaderstats:WaitForChild("Gold")
	gold.Changed:Connect(function()
		if current and current.Mode == "Reset" then
			updateGoldLine()
			updateFooter()
		end
	end)
end)

Remotes.PathDialog.OnClientEvent:Connect(function(data)
	if type(data) == "table" and type(data.Path) == "string" then
		openDialog(data)
	end
end)
