-- Tela do caminho (Humano comum / Caçador / Infernal), no estilo escuro (vermelho e branco) das outras telas:
--   esquerda: o kanji do caminho num anel, nome, time, descrição e a caixa de baixo (tempo de vida do Caçador, bônus
--     de vida do Infernal ou o level até o 25 do Humano comum)
--   direita: contratos / tipo de Infernal e poderes / caminhos disponíveis, e os passivos, em cartões com kanji
-- Passar o mouse em cima de um cartão mostra os detalhes num balão (UITheme.tooltip).
-- Abre pelo item "Caminho" da árvore de habilidades (SkillTreeMenu), que dispara o BindableEvent StatusMenu.Toggle.
-- (A antiga aba de distribuir pontos saiu: os pontos agora vão na árvore.)
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PathData = require(ReplicatedStorage:WaitForChild("PathData"))
local ContractData = require(ReplicatedStorage:WaitForChild("ContractData"))
local SkillTreeData = require(ReplicatedStorage:WaitForChild("SkillTreeData"))
local UITheme = require(ReplicatedStorage:WaitForChild("UITheme"))

local Colors = UITheme.Colors
local Fonts = UITheme.Fonts

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local level = player:WaitForChild("leaderstats", math.huge):WaitForChild("Level")

local CARD = Color3.fromRGB(20, 20, 24)
local LINE = Color3.fromRGB(56, 56, 62)
local WHITE = Colors.Text
local DIM = Colors.TextDim
local RED = Colors.Accent
local RED_BRIGHT = Colors.Orange
local CREAM = Colors.Gold
local BLACK = Colors.Black
local GREEN = Colors.Green

local PANEL_W, PANEL_H = 780, 480
-- Telas escondidas enquanto este menu está aberto (o minimapa some junto com a HUD)
local HIDE_WHILE_OPEN = { "HUD", "QuestTracker", "BossBar" }
-- Nome dos NPCs que abrem cada caminho (os nomes de verdade ficam no servidor, em QuestData)
local NPC_NAMES = {
	Veterano = "Caçador Veterano",
	Anciao = "Demônio Ancião",
}

local function new(className, props)
	return UITheme.new(className, props)
end

local function round(frame, radius)
	UITheme.corner(frame, radius or UDim.new(0, 8))
	return frame
end

local function text(props)
	props.BackgroundTransparency = 1
	props.TextColor3 = props.TextColor3 or WHITE
	props.Font = props.Font or Fonts.Title
	return new("TextLabel", props)
end

local function hex(color)
	return "#" .. color:ToHex()
end

-- ================= Tela =================

local screen = UITheme.screen("StatusMenu", 5, playerGui)
screen.IgnoreGuiInset = true
screen.Enabled = false
local toggleEvent = new("BindableEvent", { Name = "Toggle", Parent = screen })

-- Fundo escurecido: clicar fora do painel fecha
local dim = new("TextButton", {
	Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = BLACK,
	BackgroundTransparency = 1,
	AutoButtonColor = false,
	Text = "",
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
}))
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
local openScale = new("UIScale", { Parent = panel })

-- Cabeçalho
text({
	Position = UDim2.fromOffset(26, 12),
	Size = UDim2.fromOffset(300, 40),
	TextXAlignment = Enum.TextXAlignment.Left,
	Font = Fonts.Marker,
	TextSize = 32,
	Text = "CAMINHO",
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

-- ================= Esquerda: o caminho =================

local card = round(new("Frame", {
	Position = UDim2.fromOffset(24, 74),
	Size = UDim2.fromOffset(250, 382),
	BackgroundColor3 = BLACK,
	BackgroundTransparency = 0.55,
	Parent = panel,
}))
UITheme.stroke(card, LINE, 1)

local ring = round(new("Frame", {
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 18),
	Size = UDim2.fromOffset(104, 104),
	BackgroundColor3 = CARD,
	Parent = card,
}), UDim.new(0.5, 0))
local ringStroke = UITheme.stroke(ring, RED, 2)
local ringInner = round(new("Frame", {
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.new(1, -12, 1, -12),
	BackgroundTransparency = 1,
	Parent = ring,
}), UDim.new(0.5, 0))
UITheme.stroke(ringInner, LINE, 1)
local pathGlyph = text({
	Size = UDim2.fromScale(1, 1),
	TextXAlignment = Enum.TextXAlignment.Center,
	Font = Fonts.Title,
	TextSize = 50,
	Parent = ring,
})
local pathName = text({
	Position = UDim2.fromOffset(10, 132),
	Size = UDim2.new(1, -20, 0, 32),
	TextXAlignment = Enum.TextXAlignment.Center,
	TextTruncate = Enum.TextTruncate.AtEnd,
	Font = Fonts.Marker,
	TextSize = 26,
	Parent = card,
})
local pathTeam = text({
	Position = UDim2.fromOffset(10, 164),
	Size = UDim2.new(1, -20, 0, 16),
	TextXAlignment = Enum.TextXAlignment.Center,
	RichText = true,
	Font = Fonts.Body,
	TextSize = 13,
	TextColor3 = DIM,
	Parent = card,
})
local pathDescription = text({
	Position = UDim2.fromOffset(16, 188),
	Size = UDim2.new(1, -32, 0, 88),
	TextXAlignment = Enum.TextXAlignment.Center,
	TextYAlignment = Enum.TextYAlignment.Top,
	TextWrapped = true,
	TextScaled = true, -- descrições compridas diminuem para caber
	Font = Fonts.Light,
	TextColor3 = DIM,
	Parent = card,
})
new("UITextSizeConstraint", { MaxTextSize = 13, MinTextSize = 9, Parent = pathDescription })

-- Caixa de baixo: tempo de vida (Caçador), bônus de vida (Infernal) ou level até o 25 (Humano comum)
local box = round(new("Frame", {
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, -14),
	Size = UDim2.new(1, -28, 0, 84),
	BackgroundColor3 = CARD,
	BackgroundTransparency = 0.1,
	Parent = card,
}))
local boxStroke = UITheme.stroke(box, LINE, 1)
local boxTitle = text({
	Position = UDim2.fromOffset(0, 8),
	Size = UDim2.new(1, 0, 0, 16),
	TextXAlignment = Enum.TextXAlignment.Center,
	Font = Fonts.Marker,
	TextSize = 15,
	TextColor3 = DIM,
	Parent = box,
})
local boxValue = text({
	Position = UDim2.fromOffset(0, 26),
	Size = UDim2.new(1, 0, 0, 30),
	TextXAlignment = Enum.TextXAlignment.Center,
	Font = Fonts.Number,
	TextSize = 26,
	TextStrokeTransparency = 0.5,
	Visible = false,
	Parent = box,
})
local boxBar = UITheme.bar({
	Position = UDim2.fromOffset(12, 32),
	Size = UDim2.new(1, -24, 0, 16),
	Parent = box,
}, Colors.Lifespan, 11)
local boxBarGradient = boxBar.Fill:FindFirstChildOfClass("UIGradient")
local boxSub = text({
	Position = UDim2.fromOffset(8, 58),
	Size = UDim2.new(1, -16, 0, 16),
	TextXAlignment = Enum.TextXAlignment.Center,
	TextScaled = true,
	Font = Fonts.Light,
	TextColor3 = DIM,
	Parent = box,
})
new("UITextSizeConstraint", { MaxTextSize = 12, MinTextSize = 8, Parent = boxSub })

-- ================= Direita: contratos, poderes e passivos =================

local list = new("ScrollingFrame", {
	Position = UDim2.fromOffset(294, 74),
	Size = UDim2.fromOffset(PANEL_W - 294 - 22, 382),
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	ScrollBarThickness = 4,
	ScrollBarImageColor3 = RED,
	CanvasSize = UDim2.new(),
	AutomaticCanvasSize = Enum.AutomaticSize.Y,
	Parent = panel,
})
UITheme.list(list, 8)
UITheme.padding(list, 0, 10, 2, 0)

local function sectionTitle(title, order)
	text({
		Size = UDim2.new(1, 0, 0, 22),
		TextXAlignment = Enum.TextXAlignment.Left,
		Font = Fonts.Marker,
		TextSize = 17,
		TextColor3 = RED_BRIGHT,
		Text = title,
		LayoutOrder = order,
		Parent = list,
	})
end

-- Cadeado desenhado com Frames (o emoji sairia amarelo)
local function padlock(parent, size)
	local holder = new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(size, size),
		BackgroundTransparency = 1,
		Parent = parent,
	})
	local clip = new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0),
		Size = UDim2.fromOffset(size * 0.72, size * 0.5),
		BackgroundTransparency = 1,
		ClipsDescendants = true,
		Parent = holder,
	})
	local arc = round(new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 2),
		Size = UDim2.fromOffset(size * 0.46, size * 0.62),
		BackgroundTransparency = 1,
		Parent = clip,
	}), UDim.new(0.5, 0))
	UITheme.stroke(arc, DIM, 2)
	local body = round(new("Frame", {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromScale(0.5, 1),
		Size = UDim2.fromOffset(size * 0.78, size * 0.52),
		BackgroundColor3 = DIM,
		BorderSizePixel = 0,
		Parent = holder,
	}), UDim.new(0, 3))
	round(new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.45),
		Size = UDim2.fromOffset(2, math.max(3, size * 0.22)),
		BackgroundColor3 = BLACK,
		BorderSizePixel = 0,
		Parent = body,
	}), UDim.new(0.5, 0))
	return holder
end

-- Cartão com o kanji à esquerda e os textos à direita. lines = { { Text, Font?, Size?, Color? } }.
-- glyph = nil desenha um cadeado. tip = texto do balão (opcional).
local function infoRow(order, glyph, lines, tip)
	local frame = round(new("Frame", {
		Size = UDim2.new(1, 0, 0, 64),
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = order,
		BackgroundColor3 = BLACK,
		BackgroundTransparency = 0.5,
		Parent = list,
	}))
	local stroke = UITheme.stroke(frame, LINE, 1)
	local iconBox = round(new("Frame", {
		Position = UDim2.fromOffset(10, 10),
		Size = UDim2.fromOffset(44, 44),
		BackgroundColor3 = CARD,
		Parent = frame,
	}))
	UITheme.stroke(iconBox, LINE, 1)
	if glyph then
		text({
			Size = UDim2.fromScale(1, 1),
			TextXAlignment = Enum.TextXAlignment.Center,
			Font = Fonts.Title,
			TextSize = 24,
			Text = glyph,
			Parent = iconBox,
		})
	else
		padlock(iconBox, 20)
	end
	local texts = new("Frame", {
		Position = UDim2.fromOffset(66, 0),
		Size = UDim2.new(1, -76, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		Parent = frame,
	})
	UITheme.padding(texts, 9, 0, 9, 0)
	UITheme.list(texts, 2)
	for index, entry in lines do
		text({
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextWrapped = true,
			RichText = true,
			Font = entry.Font or Fonts.Body,
			TextSize = entry.Size or 12,
			TextColor3 = entry.Color or DIM,
			Text = entry.Text,
			LayoutOrder = index,
			Parent = texts,
		})
	end
	if tip then
		UITheme.tooltip(frame, tip)
		frame.MouseEnter:Connect(function()
			stroke.Color = RED
		end)
		frame.MouseLeave:Connect(function()
			stroke.Color = LINE
		end)
	end
	return frame
end

-- Linhas de um poder: [tecla] nome, números e custo
local function skillLines(skill, slotKey)
	local costText, costColor = UITheme.skillCost(skill)
	return {
		{
			Text = `<font color="{hex(RED_BRIGHT)}">[{PathData.KeyLabel(slotKey)}]</font>  {UITheme.escape(skill.Name)}`,
			Font = Fonts.Title,
			Size = 14,
			Color = WHITE,
		},
		{ Text = UITheme.skillStats(skill) },
		{ Text = `Custo: {costText}`, Font = Fonts.Title, Color = costColor },
	}
end

-- Balão de um poder: nome, tipo (cone, área...), números e custo
local function skillTip(skill, slotKey)
	local costText = UITheme.skillCost(skill)
	local kind = UITheme.SkillKinds[skill.Kind]
	local body = {}
	if kind then
		table.insert(body, `Tipo: {kind}`)
	end
	table.insert(body, UITheme.skillStats(skill))
	table.insert(body, `Custo: {costText}`)
	return UITheme.tipText(`{skill.Name} ({PathData.KeyLabel(slotKey)})`, table.concat(body, "\n"))
end

local function renderPath()
	for _, child in list:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end

	local path, contracts, fiendType, form = PathData.FromPlayer(player)
	local order = 0
	local function nextOrder()
		order += 1
		return order
	end

	if path == "Hunter" then
		-- Um contrato só (desde 2026-10-01), com a forma (ContractData), a maestria dele e os dois poderes
		local contractId = contracts[1]
		local contract = contractId and PathData.Contracts[contractId]
		sectionTitle("CONTRATO", nextOrder())
		if contract then
			local hasForms = ContractData.HasForms(contractId)
			local hpCost = contract.HPCost or 0
			local lines = {
				{ Text = contract.DisplayName, Font = Fonts.Title, Size = 16, Color = WHITE },
			}
			if hasForms then
				local fusion = ContractData.Fusion(contractId, form)
				local formText = `Forma: {ContractData.FormNames[form]} {ContractData.FormGlyphs[form] or ""}`
				if fusion and fusion.DisplayName then
					formText ..= ` · {fusion.DisplayName}`
				end
				table.insert(lines, { Text = formText, Font = Fonts.Title, Color = CREAM })
			end
			table.insert(lines, {
				Text = if hpCost > 0
					then `Sacrifício: −{UITheme.formatPercent(hpCost)} de vida máxima`
					else "Sem sacrifício de vida máxima",
				Font = Fonts.Title,
				Color = if hpCost > 0 then Colors.Health[1] else GREEN,
			})
			local passive = UITheme.passiveText(if hasForms then ContractData.Passive(contractId, form) else contract.Passive)
			if passive then
				table.insert(lines, { Text = `Passivo: {passive}`, Font = Fonts.Title, Color = CREAM })
			end
			infoRow(nextOrder(), UITheme.glyphOf(contract), lines, UITheme.tipText(contract.DisplayName, contract.Description))

			-- Maestria do contrato e o que a próxima forma pede
			if hasForms then
				local folder = player:FindFirstChild("ContractMastery")
				local value = folder and folder:FindFirstChild(contractId)
				local level, into, need = SkillTreeData.MasteryLevel(if value then value.Value else 0)
				local maxed = level >= SkillTreeData.Mastery.MaxLevel
				local masteryLines = {
					{ Text = `Maestria do contrato: {level}/{SkillTreeData.Mastery.MaxLevel}`, Font = Fonts.Title, Size = 16, Color = WHITE },
					{ Text = if maxed then "Maestria máxima." else `{into}/{need} XP para o próximo nível · sobe acertando com os poderes` },
				}
				local nextForm = ContractData.NextForm(form)
				local requires = nextForm and ContractData.Form(contractId, nextForm) and ContractData.Form(contractId, nextForm).Requires
				if requires then
					local parts = {}
					if requires.Mastery then table.insert(parts, `maestria {requires.Mastery} no contrato`) end
					local style = ContractData.Get(contractId).FusionStyle
					if requires.StyleMastery and style then table.insert(parts, `{requires.StyleMastery} nos {style}`) end
					if requires.Quest then table.insert(parts, "a provação final") end
					table.insert(masteryLines, {
						Text = `Próxima forma ({ContractData.FormNames[nextForm]}): {table.concat(parts, ", ")}. Fale com o Mestre dos Pactos.`,
						Font = Fonts.Title,
						Color = CREAM,
					})
				end
				infoRow(nextOrder(), ContractData.FormGlyphs[form] or "壱", masteryLines, UITheme.tipText("Maestria do contrato",
					"Sobe com cada acerto e abate dos poderes do contrato (e, depois da fusão, com os golpes do estilo fundido). "
						.. "É ela que libera as formas do pacto no Mestre dos Pactos."))
			end

			sectionTitle("PODERES", nextOrder())
			for _, slotKey in { "Z", "X" } do
				local skill = PathData.GetSkill(path, contracts, fiendType, slotKey, form)
				if skill then
					infoRow(nextOrder(), UITheme.glyphOf(skill), skillLines(skill, slotKey), skillTip(skill, slotKey))
				end
			end
		end
	elseif path == "Fiend" then
		local fiend = PathData.FiendTypes[fiendType]
		sectionTitle("TIPO DE INFERNAL", nextOrder())
		if fiend then
			infoRow(nextOrder(), UITheme.glyphOf(fiend), {
				{ Text = fiend.DisplayName, Font = Fonts.Title, Size = 16, Color = WHITE },
				{ Text = fiend.Description },
			}, UITheme.tipText(fiend.DisplayName, fiend.Description))
			sectionTitle("PODERES", nextOrder())
			for _, slotKey in { "Z", "X" } do
				local skill = fiend.Skills and fiend.Skills[slotKey]
				if skill then
					infoRow(nextOrder(), UITheme.glyphOf(skill), skillLines(skill, slotKey), skillTip(skill, slotKey))
				end
			end
		else
			infoRow(nextOrder(), "?", {
				{ Text = "Tipo ainda não definido", Font = Fonts.Title, Size = 16, Color = WHITE },
			})
		end
	else
		-- Humano comum: os dois caminhos que abrem no level 25
		sectionTitle(`CAMINHOS NO LEVEL {PathData.MinLevel}`, nextOrder())
		for _, pathId in { "Hunter", "Fiend" } do
			local option = PathData.Paths[pathId]
			local npc = NPC_NAMES[option.NPC] or option.NPC
			infoRow(nextOrder(), UITheme.PathIcons[pathId], {
				{ Text = option.DisplayName, Font = Fonts.Title, Size = 16, Color = WHITE },
				{ Text = option.Description },
				{ Text = `Fale com: {npc}`, Font = Fonts.Title, Color = WHITE },
			}, UITheme.tipText(option.DisplayName, `{option.Description}\n\nFale com: {npc}`))
		end
		infoRow(nextOrder(), "道", {
			{ Text = "Como escolher", Font = Fonts.Title, Size = 16, Color = WHITE },
			{
				Text = `Chegue ao level {PathData.MinLevel}, complete a missão "{PathData.RequiredQuest}" e fale com `
					.. "o NPC do caminho. A escolha é permanente.",
			},
		})
	end

	-- Passivos de quem já tem caminho
	if path ~= "None" then
		sectionTitle("PASSIVOS", nextOrder())
		local multiplier = PathData.HPMultiplier(path, contracts, fiendType)
		local passive = UITheme.passiveText(PathData.Passives(path, contracts, fiendType))
		infoRow(nextOrder(), "体", {
			{
				Text = `Vida máxima: {math.floor(multiplier * 100 + 0.5)}% do normal`,
				Font = Fonts.Title,
				Size = 13,
				Color = if multiplier < 1 then Colors.Health[1] elseif multiplier > 1 then GREEN else WHITE,
			},
			{
				Text = if passive then passive else "Nenhum passivo extra",
				Color = if passive then CREAM else DIM,
			},
			{
				Text = if path == "Fiend"
					then "Infernais não podem fazer contratos. Os poderes custam vida."
					else "Os poderes gastam tempo de vida, que recupera sozinho.",
			},
		}, UITheme.tipText("Passivos", "O que o seu caminho muda no corpo, somando os contratos ou o tipo de Infernal."))
	end
end

local function updateCard()
	local path = PathData.FromPlayer(player)
	local info = PathData.Paths[path]
	local team = PathData.Teams[info.Team]

	pathGlyph.Text = UITheme.PathIcons[path] or info.Glyph or "?"
	ringStroke.Color = if path == "None" then LINE else RED
	pathName.Text = UITheme.upper(info.DisplayName)
	pathTeam.Text = `Time: <font color="{hex(WHITE)}">{if team then team.DisplayName else info.Team}</font>`
	pathDescription.Text = info.Description

	if path == "Hunter" then
		local maxLifespan = player:GetAttribute("MaxLifespan")
		if type(maxLifespan) ~= "number" or maxLifespan <= 0 then
			maxLifespan = PathData.MaxLifespan
		end
		local lifespan = player:GetAttribute("Lifespan")
		if type(lifespan) ~= "number" then
			lifespan = maxLifespan
		end
		boxTitle.Text = "TEMPO DE VIDA"
		boxValue.Visible = false
		boxBar.Frame.Visible = true
		if boxBarGradient then
			boxBarGradient.Color = ColorSequence.new(Colors.Lifespan[1], Colors.Lifespan[2])
		end
		boxBar.Set(lifespan / maxLifespan, `{math.floor(lifespan)} / {math.floor(maxLifespan)}`, true)
		boxSub.Text = `Recupera {math.floor(PathData.LifespanRegen * 60 + 0.5)} por minuto`
		boxStroke.Color = Colors.Lifespan[2]
	elseif path == "Fiend" then
		boxTitle.Text = "CORPO DE DEMÔNIO"
		boxValue.Visible = true
		boxValue.Text = `+{UITheme.formatPercent(PathData.FiendPassive.MaxHPBonus)}`
		boxValue.TextColor3 = GREEN
		boxBar.Frame.Visible = false
		boxSub.Text = "de vida máxima"
		boxStroke.Color = RED
	else
		local minLevel = PathData.MinLevel
		boxTitle.Text = `RUMO AO LEVEL {minLevel}`
		boxValue.Visible = false
		boxBar.Frame.Visible = true
		if boxBarGradient then
			boxBarGradient.Color = ColorSequence.new(Colors.XP[1], Colors.XP[2])
		end
		boxBar.Set(level.Value / minLevel, `Level {math.min(level.Value, minLevel)} / {minLevel}`, true)
		boxSub.Text = if level.Value >= minLevel
			then `Missão: {PathData.RequiredQuest}`
			else "Depois, escolha um caminho"
		boxStroke.Color = LINE
	end
end
UITheme.tooltip(ring, function()
	local info = PathData.Paths[PathData.FromPlayer(player)]
	return UITheme.tipText(info.DisplayName, info.Description)
end)

local function onPathChanged()
	renderPath()
	updateCard()
end
for _, attribute in { "Path", "Contracts", "FiendType", "ContractForm" } do
	player:GetAttributeChangedSignal(attribute):Connect(onPathChanged)
end
for _, attribute in { "Lifespan", "MaxLifespan" } do
	player:GetAttributeChangedSignal(attribute):Connect(function()
		-- O tempo de vida muda o tempo todo: só atualiza com o menu aberto
		if screen.Enabled then
			updateCard()
		end
	end)
end
level.Changed:Connect(function()
	if screen.Enabled then
		updateCard()
	end
end)
onPathChanged()

-- ================= Abrir / fechar =================

local isOpen = false
local hiddenGuis = {}
local blur

local function setOpen(open)
	if open == isOpen then return end
	isOpen = open
	if open then
		renderPath() -- a maestria do contrato muda o tempo todo: monta de novo ao abrir
		updateCard()
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
		openScale.Scale = 0.9
		UITheme.tween(openScale, 0.22, { Scale = 1 }, Enum.EasingStyle.Back)
		UITheme.tween(dim, 0.2, { BackgroundTransparency = 0.45 })
	else
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
		UITheme.tween(dim, 0.15, { BackgroundTransparency = 1 })
		UITheme.tween(openScale, 0.15, { Scale = 0.9 }).Completed:Connect(function()
			if not isOpen then
				screen.Enabled = false
			end
		end)
	end
end

toggleEvent.Event:Connect(function()
	setOpen(not isOpen)
end)
closeButton.MouseButton1Click:Connect(function()
	setOpen(false)
end)
closeButton.MouseEnter:Connect(function()
	closeButton.TextColor3 = RED
end)
closeButton.MouseLeave:Connect(function()
	closeButton.TextColor3 = DIM
end)
dim.MouseButton1Click:Connect(function()
	setOpen(false)
end)

-- A tecla M abre a árvore de habilidades (SkillTreeMenu); este menu abre pelo item "Caminho" de lá
