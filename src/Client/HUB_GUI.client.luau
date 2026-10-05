-- HUD principal no estilo escuro (vermelho e branco):
--   embaixo à esquerda (no celular, em cima à esquerda): anel de level com o XP, nome e caminho, vida (números em
--     cima da barra), stamina, tempo de vida (só Caçador) e gold; em cima disso, os bônus em pílulas (árvore + itens)
--   embaixo no centro: habilidades com a tecla em cima (F guarda, Z/X/C do estilo, Q dash, V/B poderes do caminho),
--     a hotbar redonda 1 a 5 (estilos de combate; a mochila padrão do Roblox sai) e os botões da árvore (M), do
--     inventário (G) e das configurações
--   animações de ganho (XP, gold, LEVEL UP) e a borda de sangue com a vida baixa
--   no celular (sem teclado): as habilidades viram botões redondos grandes no canto de baixo à direita, em volta de um
--     botão de ataque (M1), ao lado do pulo do Roblox; a hotbar fica maior e sem as casas vazias. Para ver esse layout
--     no Studio, ponha o atributo ForceMobileHUD = true no ReplicatedStorage antes do Play.
-- As telas grandes ficam em SkillTreeMenu (árvore), Inventory (inventário) e StatusMenu (caminho).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")
local UserInputService = game:GetService("UserInputService")

local Remotes = require(ReplicatedStorage:WaitForChild("Remotes"))
local StatConfig = require(ReplicatedStorage:WaitForChild("StatConfig"))
local PathData = require(ReplicatedStorage:WaitForChild("PathData"))
local CombatStyles = require(ReplicatedStorage:WaitForChild("CombatStyles"))
local SkillTreeData = require(ReplicatedStorage:WaitForChild("SkillTreeData"))
local ClanData = require(ReplicatedStorage:WaitForChild("ClanData"))
local UITheme = require(ReplicatedStorage:WaitForChild("UITheme"))
local FastMode = require(script.Parent:WaitForChild("FastMode"))

local Colors = UITheme.Colors
local Fonts = UITheme.Fonts

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- A vida e a mochila padrão do Roblox somem: a HUD mostra as nossas
pcall(function()
	StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Health, false)
	StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
end)

local leaderstats = player:WaitForChild("leaderstats")
local progress = player:WaitForChild("Progress")
local statsFolder = player:WaitForChild("Stats")
local level = leaderstats:WaitForChild("Level")
local gold = leaderstats:WaitForChild("Gold")
local xp = progress:WaitForChild("XP")
local xpNeeded = progress:WaitForChild("XPNeeded")
local points = progress:WaitForChild("StatusPoints")

local WHITE = Colors.Text
local DIM = Colors.TextDim
local RED = Colors.Accent
local RED_BRIGHT = Colors.Orange
local CREAM = Colors.Gold
local BLACK = Colors.Black
local SLOT_BG = Color3.fromRGB(12, 12, 14)
local SLOT_LINE = Color3.fromRGB(70, 70, 78)

local touchOnly = (UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled)
	or ReplicatedStorage:GetAttribute("ForceMobileHUD") == true
local RING_SEGMENTS = 40
local HOTBAR_SLOTS = 5
local HOTBAR_KEYS = { Enum.KeyCode.One, Enum.KeyCode.Two, Enum.KeyCode.Three, Enum.KeyCode.Four, Enum.KeyCode.Five }
-- Ícone de cada estilo de combate na hotbar e das skills dele (kanji brancos, como os nós da árvore)
local STYLE_GLYPHS = { Punhos = "拳", Katana = "刀" }
local SKILL_GLYPHS = { Punhos = { Z = "連", X = "溜" } }

local screen = UITheme.screen("HUD", 1, playerGui)

local function new(className, props)
	return UITheme.new(className, props)
end

local function round(frame, radius)
	UITheme.corner(frame, radius or UDim.new(0.5, 0))
	return frame
end

local function text(props)
	props.BackgroundTransparency = 1
	props.TextColor3 = props.TextColor3 or WHITE
	props.Font = props.Font or Fonts.Title
	return new("TextLabel", props)
end

-- Cadeado desenhado com Frames (o emoji sairia amarelo)
local function padlock(parent, size)
	local holder = new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(size, size),
		BackgroundTransparency = 1,
		Visible = false,
		ZIndex = 8,
		Parent = parent,
	})
	local clip = new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0),
		Size = UDim2.fromOffset(size * 0.72, size * 0.5),
		BackgroundTransparency = 1,
		ClipsDescendants = true,
		ZIndex = 8,
		Parent = holder,
	})
	local arc = round(new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 2),
		Size = UDim2.fromOffset(size * 0.46, size * 0.62),
		BackgroundTransparency = 1,
		ZIndex = 8,
		Parent = clip,
	}))
	UITheme.stroke(arc, WHITE, 2)
	local body = round(new("Frame", {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromScale(0.5, 1),
		Size = UDim2.fromOffset(size * 0.78, size * 0.52),
		BackgroundColor3 = WHITE,
		BorderSizePixel = 0,
		ZIndex = 9,
		Parent = holder,
	}), UDim.new(0, 3))
	round(new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.45),
		Size = UDim2.fromOffset(2, math.max(3, size * 0.22)),
		BackgroundColor3 = BLACK,
		BorderSizePixel = 0,
		ZIndex = 10,
		Parent = body,
	}))
	return holder
end

-- ================= Vida, stamina, XP e gold =================

local vitals = new("Frame", {
	Name = "Vitals",
	AnchorPoint = if touchOnly then Vector2.new(0, 0) else Vector2.new(0, 1),
	Position = if touchOnly then UDim2.fromOffset(12, 8) else UDim2.new(0, 22, 1, -16),
	Size = UDim2.fromOffset(372, 112),
	BackgroundTransparency = 1,
	Parent = screen,
})
UITheme.autoScale(vitals, 1280, 720)
-- O tutorial (Tutorial.client.luau) acha os elementos que destaca pelo atributo TutorialAnchor
vitals:SetAttribute("TutorialAnchor", "Vitals")

-- Anel de level: segmentos que acendem com o XP
local ring = new("Frame", {
	Position = UDim2.fromOffset(0, 30),
	Size = UDim2.fromOffset(76, 76),
	BackgroundTransparency = 1,
	Parent = vitals,
})
local ringScale = new("UIScale", { Parent = ring })
local ringSegments = {}
for i = 1, RING_SEGMENTS do
	local angle = (i - 0.5) / RING_SEGMENTS * math.pi * 2 -- começa em cima, sentido horário
	local segment = new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, math.sin(angle) * 34, 0.5, -math.cos(angle) * 34),
		Size = UDim2.fromOffset(3, 8),
		Rotation = math.deg(angle),
		BackgroundColor3 = WHITE,
		BackgroundTransparency = 0.8,
		BorderSizePixel = 0,
		Parent = ring,
	})
	ringSegments[i] = segment
end
local ringCore = round(new("Frame", {
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromOffset(56, 56),
	BackgroundColor3 = BLACK,
	BackgroundTransparency = 0.35,
	Parent = ring,
}))
text({
	Position = UDim2.fromOffset(0, 9),
	Size = UDim2.new(1, 0, 0, 12),
	TextXAlignment = Enum.TextXAlignment.Center,
	Font = Fonts.Title,
	TextSize = 11,
	TextColor3 = DIM,
	Text = "Lv",
	Parent = ringCore,
})
local levelNumber = text({
	Position = UDim2.fromOffset(0, 19),
	Size = UDim2.new(1, 0, 0, 26),
	TextXAlignment = Enum.TextXAlignment.Center,
	Font = Fonts.Number,
	TextSize = 22,
	TextStrokeTransparency = 0.5,
	Parent = ringCore,
})
local xpLabel = text({
	Position = UDim2.fromOffset(0, 12),
	Size = UDim2.fromOffset(160, 14),
	TextXAlignment = Enum.TextXAlignment.Left,
	Font = Fonts.Title,
	TextSize = 11,
	TextColor3 = RED_BRIGHT,
	TextStrokeTransparency = 0.5,
	Parent = vitals,
})

-- Barras à direita do anel
local bars = new("Frame", {
	Position = UDim2.fromOffset(88, 0),
	Size = UDim2.new(1, -88, 1, 0),
	BackgroundTransparency = 1,
	Parent = vitals,
})
local nameLabel = text({
	Position = UDim2.fromOffset(0, 26),
	Size = UDim2.new(0.62, 0, 0, 18),
	TextXAlignment = Enum.TextXAlignment.Left,
	TextTruncate = Enum.TextTruncate.AtEnd,
	RichText = true,
	Font = Fonts.Title,
	TextSize = 13,
	TextStrokeTransparency = 0.5,
	Parent = bars,
})
local hpNumbers = text({
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, 0, 0, 22),
	Size = UDim2.new(0.5, 0, 0, 22),
	TextXAlignment = Enum.TextXAlignment.Right,
	Font = Fonts.Number,
	TextSize = 19,
	TextStrokeTransparency = 0.3,
	Parent = bars,
})
local hpBar = UITheme.bar({
	Position = UDim2.fromOffset(0, 46),
	Size = UDim2.new(1, 0, 0, 14),
	Parent = bars,
}, Colors.Health, 1)
hpBar.Label.Visible = false
local hpStroke = hpBar.Frame:FindFirstChildOfClass("UIStroke")
local staminaBar = UITheme.bar({
	Position = UDim2.fromOffset(0, 64),
	Size = UDim2.new(1, 0, 0, 6),
	Parent = bars,
}, Colors.Stamina, 1)
staminaBar.Label.Visible = false
-- Tempo de vida: só aparece para Caçadores
local lifespanBar = UITheme.bar({
	Position = UDim2.fromOffset(0, 74),
	Size = UDim2.new(1, 0, 0, 6),
	Visible = false,
	Parent = bars,
}, Colors.Lifespan, 1)
lifespanBar.Label.Visible = false
local lifespanLabel = text({
	Position = UDim2.fromOffset(0, 82),
	Size = UDim2.fromOffset(150, 14),
	TextXAlignment = Enum.TextXAlignment.Left,
	Font = Fonts.Title,
	TextSize = 11,
	TextColor3 = Colors.Lifespan[1],
	TextStrokeTransparency = 0.5,
	Visible = false,
	Parent = bars,
})
-- Gold: moeda creme e o número
local goldRow = new("Frame", {
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, 0, 0, 74),
	Size = UDim2.fromOffset(140, 18),
	BackgroundTransparency = 1,
	Parent = bars,
})
round(new("Frame", {
	AnchorPoint = Vector2.new(1, 0.5),
	Position = UDim2.new(1, 0, 0.5, 0),
	Size = UDim2.fromOffset(11, 11),
	BackgroundColor3 = CREAM,
	Parent = goldRow,
}))
local goldLabel = text({
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, -16, 0, 0),
	Size = UDim2.fromOffset(120, 18),
	TextXAlignment = Enum.TextXAlignment.Right,
	Font = Fonts.Number,
	TextSize = 14,
	TextColor3 = CREAM,
	TextStrokeTransparency = 0.5,
	Parent = goldRow,
})

-- Balões das barras e do anel
UITheme.tooltip(ring, function()
	if level.Value >= StatConfig.MaxLevel then
		return UITheme.tipText(`Level {level.Value}`, "Level máximo.")
	end
	return UITheme.tipText(`Level {level.Value}`, `XP: {UITheme.formatNumber(xp.Value)} / {UITheme.formatNumber(xpNeeded.Value)}\n`
		.. `Cada level dá {StatConfig.PointsPerLevel} ponto na árvore de habilidades (M).`)
end)
UITheme.tooltip(hpBar.Frame, UITheme.tipText("Vida", "A regeneração da árvore e dos itens recupera fora de combate."))
UITheme.tooltip(staminaBar.Frame, UITheme.tipText("Fôlego", "O dash gasta; recupera sozinho."))
UITheme.tooltip(lifespanLabel, UITheme.tipText("Tempo de vida", "Os poderes do Caçador gastam tempo de vida. Ele recupera sozinho."))
UITheme.tooltip(goldRow, UITheme.tipText("Gold", "Vem dos inimigos e das missões."))

local function layoutVitals(showLifespan)
	lifespanBar.Frame.Visible = showLifespan
	lifespanLabel.Visible = showLifespan
	goldRow.Position = UDim2.new(1, 0, 0, if showLifespan then 84 else 74)
end

-- ================= Bônus (pílulas) =================

local bonuses = new("Frame", {
	Name = "Bonuses",
	AnchorPoint = if touchOnly then Vector2.new(0, 0) else Vector2.new(0, 1),
	Position = if touchOnly then UDim2.fromOffset(12, 124) else UDim2.new(0, 22, 1, -132),
	Size = UDim2.fromOffset(372, 84),
	BackgroundTransparency = 1,
	Parent = screen,
})
UITheme.autoScale(bonuses, 1280, 720)
new("UIListLayout", {
	FillDirection = Enum.FillDirection.Horizontal,
	Wraps = true,
	Padding = UDim.new(0, 5),
	HorizontalAlignment = Enum.HorizontalAlignment.Left,
	VerticalAlignment = if touchOnly then Enum.VerticalAlignment.Top else Enum.VerticalAlignment.Bottom,
	SortOrder = Enum.SortOrder.LayoutOrder,
	Parent = bonuses,
})

-- Bônus atuais: stats acima da base e os efeitos da árvore/itens (atributos Tree<Efeito>)
local function currentBonuses()
	local effects = {}
	for name, base in StatConfig.BaseStats do
		local stat = statsFolder:FindFirstChild(name)
		if stat and stat.Value ~= base then
			effects[name] = stat.Value - base
		end
	end
	for key in SkillTreeData.EffectInfo do
		if StatConfig.BaseStats[key] == nil then
			local value = player:GetAttribute("Tree" .. key)
			if value ~= nil and value ~= 0 and value ~= false then
				effects[key] = value
			end
		end
	end
	return effects
end

local bonusPills = {} -- [efeito] = { Frame, Value }
local function updateBonuses()
	local effects = currentBonuses()
	for index, key in SkillTreeData.EffectOrder do
		local value = effects[key]
		local pill = bonusPills[key]
		if value == nil then
			if pill then
				pill.Frame.Visible = false
			end
		else
			if not pill then
				local info = SkillTreeData.EffectInfo[key] or {}
				local frame, _, valueLabel = UITheme.pill({ LayoutOrder = index, Parent = bonuses }, info.Icon or "•", "")
				pill = { Frame = frame, Value = valueLabel }
				bonusPills[key] = pill
				-- Balão: o nome do bônus e o que ele faz (árvore + itens vestidos)
				UITheme.tooltip(frame, function()
					local current = currentBonuses()[key]
					return UITheme.tipText(info.Name or key, if current ~= nil then SkillTreeData.EffectText(key, current) else "")
				end)
			end
			pill.Frame.Visible = true
			pill.Value.Text = SkillTreeData.ShortValue(key, value)
		end
	end
end

-- ================= Habilidades, hotbar e botões (embaixo no centro) =================

local actions = new("Frame", {
	Name = "Actions",
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, -12),
	Size = UDim2.fromOffset(560, 146),
	BackgroundTransparency = 1,
	Parent = screen,
})
local actionsScale = UITheme.autoScale(actions, 1280, 720)
if touchOnly then
	-- No celular a hotbar não fica menor que 80% (o dedo precisa acertar as casas)
	local function keepTouchSize()
		if actionsScale.Scale < 0.8 then
			actionsScale.Scale = 0.8
		end
	end
	actionsScale:GetPropertyChangedSignal("Scale"):Connect(keepTouchSize)
	keepTouchSize()
end

local skillsRow = new("Frame", {
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.fromScale(0.5, 0),
	Size = UDim2.fromOffset(560, 66),
	BackgroundTransparency = 1,
	Parent = actions,
})
UITheme.list(skillsRow, 8, Enum.FillDirection.Horizontal, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Bottom)
skillsRow:SetAttribute("TutorialAnchor", "Skills")

local hotbarRow = new("Frame", {
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.fromScale(0.5, 1),
	Size = UDim2.fromOffset(560, 74),
	BackgroundTransparency = 1,
	Parent = actions,
})
UITheme.list(hotbarRow, 10, Enum.FillDirection.Horizontal, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Top)
hotbarRow:SetAttribute("TutorialAnchor", "Hotbar")

-- F e Z/X/C vêm do estilo equipado (CombatStyles; slot sem skill no estilo some); o teclado é do CombatInput
local SKILLS = {
	{ Key = "F", Name = "Defesa", Glyph = "守", Block = true },
	{ Key = "Z", Name = "Skill", Glyph = "連", Attribute = "CombatZReadyAt", Skill = "Z" },
	{ Key = "X", Name = "Skill", Glyph = "溜", Attribute = "CombatXReadyAt", Skill = "X" },
	{ Key = "C", Name = "Skill", Glyph = "斬", Attribute = "CombatCReadyAt", Skill = "C" },
	{ Key = "Q", Name = "Dash", Glyph = "駆", StaminaCost = 20, Attribute = "DashReadyAt" },
}
-- Poderes do caminho (PathData.GetSkill) nas teclas V e B; por dentro os slots continuam "Z" e "X". O teclado é
-- tratado pelo PowerInput.client.luau.
local POWERS = {
	{ Key = "V", Name = "Poder", Glyph = "?", Attribute = "PowerZReadyAt", Power = "Z" },
	{ Key = "B", Name = "Poder", Glyph = "?", Attribute = "PowerXReadyAt", Power = "X" },
	-- Modo híbrido de admin (/hibrido): os poderes do Infernal em H e J (só aparecem nele)
	{ Key = "H", Name = "Poder", Glyph = "?", Attribute = "PowerHZReadyAt", Power = "HZ" },
	{ Key = "J", Name = "Poder", Glyph = "?", Attribute = "PowerHXReadyAt", Power = "HX" },
}
local SLOT_SIZE = 44

-- Toques nos slots: os scripts donos das ações escutam BindableEvents ao lado dos LocalScripts.
-- "MovementAction" (StaminaDashRunscript): ("Dash") e ("AutoRun", ligado).
-- "CombatAction" (CombatInput): ("Block", segurando) ou ("Skill", slot, segurando).
local function fireBindable(name, ...)
	local event = script.Parent:FindFirstChild(name)
	if event and event:IsA("BindableEvent") then
		event:Fire(...)
	end
end

-- Slots de segurar (block, soco carregado): funcionam enquanto o dedo/botão estiver pressionado
local heldSlots = {} -- [botão] = { Input, Release }
local function releaseHeldSlots()
	local released = table.clone(heldSlots)
	table.clear(heldSlots)
	for _, held in released do
		held.Release()
	end
end
-- InputEnded pode não chegar se a janela perder o foco ou o personagem for removido.
player.CharacterRemoving:Connect(releaseHeldSlots)
UserInputService.WindowFocusReleased:Connect(releaseHeldSlots)
player:GetAttributeChangedSignal("MenuOpen"):Connect(function()
	if player:GetAttribute("MenuOpen") then releaseHeldSlots() end
end)
local function isPress(input)
	return input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1
end
local function bindHold(button, onPress, onRelease)
	button.InputBegan:Connect(function(input)
		if heldSlots[button] or not isPress(input) then return end
		heldSlots[button] = { Input = input, Release = onRelease }
		onPress()
	end)
end
UserInputService.InputEnded:Connect(function(input)
	for button, held in heldSlots do
		-- O toque é o mesmo InputObject do começo ao fim; o mouse é comparado pelo tipo
		local same = input == held.Input
			or (input.UserInputType == Enum.UserInputType.MouseButton1 and held.Input.UserInputType == Enum.UserInputType.MouseButton1)
		if same then
			heldSlots[button] = nil
			held.Release()
		end
	end
end)

local slots = {}
local powerSlots = {}

local powerDivider = new("Frame", {
	Size = UDim2.fromOffset(2, 30),
	LayoutOrder = 10,
	BackgroundColor3 = WHITE,
	BackgroundTransparency = 0.8,
	BorderSizePixel = 0,
	Visible = false,
	Parent = skillsRow,
})

-- Balão de cada slot: o que a tecla faz agora (nome, recarga, se está travada)
local function slotTip(slot)
	local info = slot.Info
	if info.Block then
		return UITheme.tipText("Defesa (F)", "Segure para levantar a guarda. Logo no começo dela, o golpe inimigo vira "
			.. "parry. A barrinha embaixo é a guarda: se esvaziar, ela quebra e você fica atordoado.")
	elseif info.StaminaCost then
		return UITheme.tipText("Dash (Q)", "Avança para onde você está andando. Recarga de 1 s e gasta fôlego (a barra branca).")
	elseif info.Skill then
		local _, style = CombatStyles.FromCharacter(player.Character)
		style = style or CombatStyles.Styles.Punhos
		local skill = style and style.Skills[info.Skill]
		if not skill then
			return UITheme.tipText(`Skill ({info.Key})`, "O estilo equipado não tem skill nessa tecla.")
		end
		local lines = { skill.Description or "" }
		if skill.Cooldown then
			table.insert(lines, `Recarga: {UITheme.formatSeconds(skill.Cooldown)}`)
		end
		if skill.Technique and player:GetAttribute("Tech_" .. skill.Technique) ~= true then
			table.insert(lines, `<font color="#{RED_BRIGHT:ToHex()}">Travada: desbloqueie na árvore de habilidades (M).</font>`)
		end
		return UITheme.tipText(`{skill.Name} ({info.Key})`, table.concat(lines, "\n"))
	elseif info.Power then
		local skill = slot.Skill
		if not skill then
			return UITheme.tipText(`Contrato vazio ({info.Key})`, "O 2º contrato vem de missões de Caçador.")
		end
		local costText = UITheme.skillCost(skill)
		return UITheme.tipText(`{skill.Name} ({info.Key})`, `{UITheme.skillStats(skill)}\nCusto: {costText}`)
	end
	return nil
end

local function createSlot(info, order)
	local holder = new("Frame", {
		Size = UDim2.fromOffset(SLOT_SIZE, SLOT_SIZE + 20),
		BackgroundTransparency = 1,
		LayoutOrder = order,
		Parent = skillsRow,
	})
	holder:SetAttribute("TutorialAnchor", "Slot_" .. info.Key)
	local keyLabel = UITheme.keyLabel({
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0),
		Text = info.Key,
		Parent = holder,
	})
	local button = round(new("TextButton", {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromScale(0.5, 1),
		Size = UDim2.fromOffset(SLOT_SIZE, SLOT_SIZE),
		AutoButtonColor = false,
		BackgroundColor3 = SLOT_BG,
		BackgroundTransparency = 0.25,
		ClipsDescendants = true,
		Text = "",
		Parent = holder,
	}), UDim.new(0, 8))
	local stroke = UITheme.stroke(button, SLOT_LINE, 1.5)

	local icon = text({
		Size = UDim2.fromScale(1, 1),
		TextXAlignment = Enum.TextXAlignment.Center,
		Font = Fonts.Title,
		TextSize = 22,
		Text = info.Glyph,
		ZIndex = 2,
		Parent = button,
	})

	-- Custo do poder (canto de cima, à direita)
	local costLabel
	if info.Power then
		costLabel = text({
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -3, 0, 2),
			Size = UDim2.fromOffset(34, 12),
			TextXAlignment = Enum.TextXAlignment.Right,
			Font = Fonts.Title,
			TextSize = 9,
			TextStrokeTransparency = 0.4,
			ZIndex = 4,
			Parent = button,
		})
	end

	-- Barra da guarda no slot do block
	local guardFill
	if info.Block then
		local guardTrack = new("Frame", {
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -4),
			Size = UDim2.new(1, -10, 0, 3),
			BackgroundColor3 = BLACK,
			BackgroundTransparency = 0.3,
			BorderSizePixel = 0,
			ZIndex = 3,
			Parent = button,
		})
		guardFill = new("Frame", {
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = WHITE,
			BorderSizePixel = 0,
			ZIndex = 4,
			Parent = guardTrack,
		})
	end

	-- Escurece de cima para baixo enquanto está em recarga
	local cooldown = new("Frame", {
		Size = UDim2.fromScale(1, 0),
		BackgroundColor3 = BLACK,
		BackgroundTransparency = 0.3,
		BorderSizePixel = 0,
		ZIndex = 5,
		Parent = button,
	})
	local cooldownText = text({
		Size = UDim2.fromScale(1, 1),
		TextXAlignment = Enum.TextXAlignment.Center,
		Font = Fonts.Number,
		TextSize = 15,
		TextStrokeTransparency = 0.3,
		ZIndex = 6,
		Parent = button,
	})
	-- Cadeado: técnica do estilo ainda não desbloqueada na árvore (atributo Tech_<Técnica>)
	local lock = if info.Skill or info.Power then padlock(button, 18) else nil

	local slot = {
		Info = info,
		Holder = holder,
		KeyLabel = keyLabel,
		Button = button,
		Stroke = stroke,
		Lock = lock,
		Icon = icon,
		CostLabel = costLabel,
		GuardFill = guardFill,
		Cooldown = cooldown,
		CooldownText = cooldownText,
		Total = 1,
		WasCooling = false,
		BaseColor = SLOT_LINE,
		Skill = nil, -- habilidade do caminho (só nos slots V/B)
		CostColor = WHITE, -- cor do custo quando dá para pagar (só nos slots V/B)
	}
	table.insert(slots, slot)
	UITheme.tooltip(button, function()
		return slotTip(slot)
	end)

	if info.Attribute then
		-- A duração total vem do próprio atributo (quem escreve define quando a habilidade fica pronta)
		player:GetAttributeChangedSignal(info.Attribute):Connect(function()
			local readyAt = player:GetAttribute(info.Attribute) or 0
			slot.Total = math.max(0.1, readyAt - workspace:GetServerTimeNow())
		end)
	end

	-- Toque/clique usa a habilidade (útil no celular)
	if info.Block then
		bindHold(button, function()
			fireBindable("CombatAction", "Block", true)
		end, function()
			fireBindable("CombatAction", "Block", false)
		end)
	elseif info.Skill then
		-- Skill de segurar (Soco carregado) carrega enquanto o slot estiver pressionado; as outras saem no toque
		bindHold(button, function()
			fireBindable("CombatAction", "Skill", info.Skill, true)
		end, function()
			fireBindable("CombatAction", "Skill", info.Skill, false)
		end)
	elseif info.Power then
		button.MouseButton1Click:Connect(function()
			local readyAt = player:GetAttribute(info.Attribute) or 0
			local character = player.Character
			-- Guarda levantada ou carregando o R: o servidor recusaria
			local inStance = character ~= nil
				and (character:GetAttribute("Blocking") == true or character:GetAttribute("Charging") == true)
			if slot.Skill and not inStance and workspace:GetServerTimeNow() >= readyAt then
				-- Bote da Raposa: vira para onde a câmera olha e faz o gesto (FoxAim); o resto vai direto
				local foxAim = script.Parent:FindFirstChild("FoxAim")
				if slot.Skill.Kind == "FoxLunge" and foxAim then
					require(foxAim).Cast(info.Power)
				else
					Remotes.UsePower:FireServer(info.Power)
				end
			end
		end)
	elseif info.StaminaCost then
		button.MouseButton1Click:Connect(function()
			fireBindable("MovementAction", "Dash")
		end)
	end

	return slot
end

for index, info in SKILLS do
	createSlot(info, index)
end
for index, info in POWERS do
	local slot = createSlot(info, 10 + index)
	slot.Holder.Visible = false
	table.insert(powerSlots, slot)
end

-- Largura da linha conforme os slots visíveis
local function resizeSkillsRow()
	local width, count = 0, 0
	for _, child in skillsRow:GetChildren() do
		if child:IsA("GuiObject") and child.Visible then
			width += child.Size.X.Offset
			count += 1
		end
	end
	skillsRow.Size = UDim2.fromOffset(math.max(560, width + math.max(0, count - 1) * 8), 66)
end

-- Vida atual (para saber se dá para pagar o custo dos poderes de Infernal)
local currentHumanoid

local function canPay(skill)
	if skill.LifespanCost then
		return (player:GetAttribute("Lifespan") or 0) >= skill.LifespanCost
	elseif skill.HealthCost then
		local humanoid = currentHumanoid
		if not humanoid or humanoid.Health <= 0 then return false end
		-- O servidor não deixa o poder matar: exige vida maior que o custo
		return humanoid.Health > skill.HealthCost * humanoid.MaxHealth
	end
	return true
end

-- Slots V/B conforme o caminho, o contrato (e a forma dele) e o tipo de Infernal
local function updatePowers()
	local path = PathData.FromPlayer(player)
	local pathColor = PathData.Paths[path].Color
	local anyShown = false
	local hybrid = player:GetAttribute("Hybrid") == true
	for _, slot in powerSlots do
		local skill = PathData.PlayerSkill(player, slot.Info.Power)
		slot.Skill = skill
		-- Caçador: os dois slots são do contrato (um slot vazio aparece trancado); H/J só com o poder (modo híbrido)
		local extra = slot.Info.Power == "HZ" or slot.Info.Power == "HX"
		local show = skill ~= nil or (path == "Hunter" and not extra) or (hybrid and not extra)
		slot.Holder.Visible = show
		anyShown = anyShown or show
		if skill then
			slot.Icon.Text = UITheme.glyphOf(skill)
			slot.Icon.TextSize = 22
			local costText, costColor = UITheme.skillCostShort(skill)
			slot.CostLabel.Text = costText
			slot.CostLabel.TextColor3 = costColor
			slot.CostColor = costColor
			slot.Lock.Visible = false
			local readyAt = player:GetAttribute(slot.Info.Attribute) or 0
			if readyAt <= workspace:GetServerTimeNow() then
				slot.Total = math.max(0.1, skill.Cooldown or 1)
			end
		else
			slot.Icon.Text = ""
			slot.CostLabel.Text = ""
			slot.Lock.Visible = true
		end
		slot.BaseColor = pathColor
		slot.Stroke.Color = pathColor
	end
	powerDivider.Visible = anyShown
	resizeSkillsRow()
end

-- ----- Hotbar: estilos de combate (Tools) nas casas 1 a 5 -----
local hotbarSlots = {}
local toolOrder = {} -- nomes na ordem em que chegaram (a casa de cada estilo não muda)

local function currentTools()
	local found = {}
	-- Mochila atual: o Roblox cria outra a cada vez que o jogador renasce
	for _, container in { player.Character, player:FindFirstChildOfClass("Backpack") } do
		if container then
			for _, child in container:GetChildren() do
				if child:IsA("Tool") then
					found[child.Name] = child
				end
			end
		end
	end
	for name in found do
		if not table.find(toolOrder, name) then
			table.insert(toolOrder, name)
		end
	end
	return found
end

local function toggleTool(index)
	local name = toolOrder[index]
	local tool = name and currentTools()[name]
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not tool or not humanoid or humanoid.Health <= 0 then return end
	if tool.Parent == character then
		humanoid:UnequipTools()
	else
		humanoid:EquipTool(tool)
	end
end

for index = 1, HOTBAR_SLOTS do
	local holder = new("Frame", {
		Size = UDim2.fromOffset(54, 74),
		BackgroundTransparency = 1,
		LayoutOrder = index,
		Parent = hotbarRow,
	})
	local circle = round(new("TextButton", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0),
		Size = UDim2.fromOffset(52, 52),
		BackgroundColor3 = SLOT_BG,
		BackgroundTransparency = 0.3,
		AutoButtonColor = false,
		Text = "",
		Parent = holder,
	}))
	local circleStroke = UITheme.stroke(circle, SLOT_LINE, 1.5)
	local circleScale = new("UIScale", { Parent = circle })
	local glyph = text({
		Size = UDim2.fromScale(1, 1),
		TextXAlignment = Enum.TextXAlignment.Center,
		Font = Fonts.Title,
		TextSize = 24,
		Parent = circle,
	})
	UITheme.keyLabel({
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromScale(0.5, 1),
		Text = tostring(index),
		Parent = holder,
	})
	circle.MouseButton1Click:Connect(function()
		toggleTool(index)
	end)
	UITheme.tooltip(circle, function()
		local name = toolOrder[index]
		local tool = name and currentTools()[name]
		if not tool then
			return UITheme.tipText(`Casa {index}`, "Vazia: os estilos de combate que você ganhar aparecem aqui.")
		end
		local style = CombatStyles.Styles[name]
		return UITheme.tipText(`{if style then style.DisplayName or name else name} ({index})`,
			"Estilo de combate. Aperte o número (ou clique) para equipar ou guardar.")
	end)
	hotbarSlots[index] = { Holder = holder, Circle = circle, Stroke = circleStroke, Scale = circleScale, Glyph = glyph }
end

local attackGlyph -- botão de ataque do celular (mostra o estilo na mão)

local function updateHotbar()
	local tools = currentTools()
	local character = player.Character
	for index, slot in hotbarSlots do
		local name = toolOrder[index]
		local tool = name and tools[name]
		local equipped = tool ~= nil and tool.Parent == character
		slot.Glyph.Text = if tool then (STYLE_GLYPHS[name] or UITheme.upper(string.sub(name, 1, 2))) else ""
		slot.Circle.BackgroundTransparency = if tool then 0.2 else 0.55
		-- No celular as casas vazias somem (sobra espaço para o dedo)
		slot.Holder.Visible = tool ~= nil or not touchOnly
		slot.Stroke.Color = if equipped then RED else SLOT_LINE
		slot.Stroke.Thickness = if equipped then 2.5 else 1.5
		UITheme.tween(slot.Scale, 0.12, { Scale = if equipped then 1.08 else 1 })
	end
	if attackGlyph then
		local styleName = CombatStyles.FromCharacter(character)
		attackGlyph.Text = if styleName then (STYLE_GLYPHS[styleName] or UITheme.upper(string.sub(styleName, 1, 2))) else "拳"
		attackGlyph.TextTransparency = if styleName then 0 else 0.45
	end
end

-- ================= Celular: botões de ação no canto de baixo à direita =================
-- Sem teclado as habilidades saem da linha do centro (pequena demais para o dedo) e viram botões redondos em volta de um
-- botão grande de ataque (M1; segurando repete o combo), ao lado do botão de pulo do Roblox. São os mesmos slots
-- (recarga, cadeado, guarda, custo dos poderes), só maiores e em outro lugar. Posições em relação ao centro do botão de
-- pulo, no tamanho do celular (o pulo do Roblox tem 70 px no celular e 120 no tablet: tudo cresce junto).
local MOBILE_SLOT = 54
local MOBILE_ATTACK = Vector2.new(-95, -40)
local MOBILE_ATTACK_SIZE = 92
local MOBILE_LAYOUT = {
	-- Anel de dentro (84 do centro do ataque): guarda à esquerda, Z/X/C por cima e o dash embaixo à esquerda
	F = Vector2.new(-179, -40),
	Z = Vector2.new(-154, -99),
	X = Vector2.new(-95, -124),
	C = Vector2.new(-36, -99),
	Q = Vector2.new(-154, 19),
	-- Anel de fora: poderes do caminho (V/B) e, no modo híbrido de admin, H/J
	V = Vector2.new(-45, -177),
	B = Vector2.new(17, -134),
	H = Vector2.new(-120, -184),
	J = Vector2.new(-185, -155),
}

if touchOnly then
	skillsRow.Visible = false
	local pad = new("Frame", {
		Name = "MobilePad",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromOffset(0, 0),
		BackgroundTransparency = 1,
		Parent = screen,
	})
	local padScale = new("UIScale", { Parent = pad })
	-- Mesma conta do botão de pulo do Roblox (TouchJump): centro e tamanho conforme o lado menor da tela
	local function placePad()
		local size = screen.AbsoluteSize
		if size.X <= 0 then return end
		local small = math.min(size.X, size.Y) <= 500
		pad.Position = if small then UDim2.new(1, -60, 1, -55) else UDim2.new(1, -110, 1, -150)
		padScale.Scale = if small then 1 else 120 / 70
	end
	placePad()
	screen:GetPropertyChangedSignal("AbsoluteSize"):Connect(placePad)

	local attack = round(new("TextButton", {
		Name = "Attack",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(MOBILE_ATTACK.X, MOBILE_ATTACK.Y),
		Size = UDim2.fromOffset(MOBILE_ATTACK_SIZE, MOBILE_ATTACK_SIZE),
		AutoButtonColor = false,
		BackgroundColor3 = SLOT_BG,
		BackgroundTransparency = 0.15,
		Text = "",
		Parent = pad,
	}))
	attack:SetAttribute("TutorialAnchor", "AttackButton")
	UITheme.stroke(attack, RED, 3)
	local attackScale = new("UIScale", { Parent = attack })
	round(new("Frame", { -- anel de dentro
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(1, -16, 1, -16),
		BackgroundTransparency = 1,
		Parent = attack,
	}))
	UITheme.stroke(attack:FindFirstChildOfClass("Frame"), WHITE, 1, 0.75)
	attackGlyph = text({
		Size = UDim2.fromScale(1, 1),
		TextXAlignment = Enum.TextXAlignment.Center,
		Font = Fonts.Title,
		TextSize = 40,
		Text = "拳",
		Parent = attack,
	})
	bindHold(attack, function()
		-- Sem estilo na mão: equipa o primeiro da hotbar (o próximo toque já bate)
		if not CombatStyles.FromCharacter(player.Character) then
			toggleTool(1)
			return
		end
		attackScale.Scale = 0.9
		fireBindable("CombatAction", "Attack", true)
	end, function()
		UITheme.tween(attackScale, 0.12, { Scale = 1 })
		fireBindable("CombatAction", "Attack", false)
	end)

	-- Os slots das habilidades: os mesmos objetos, redondos e maiores, sem a tecla em cima
	for _, slot in slots do
		local offset = MOBILE_LAYOUT[slot.Info.Key]
		if offset then
			local holder = slot.Holder
			holder.Parent = pad
			holder.AnchorPoint = Vector2.new(0.5, 0.5)
			holder.Position = UDim2.fromOffset(offset.X, offset.Y)
			holder.Size = UDim2.fromOffset(MOBILE_SLOT, MOBILE_SLOT)
			slot.KeyLabel.Visible = false
			slot.Button.AnchorPoint = Vector2.new(0.5, 0.5)
			slot.Button.Position = UDim2.fromScale(0.5, 0.5)
			slot.Button.Size = UDim2.fromScale(1, 1)
			local corner = slot.Button:FindFirstChildOfClass("UICorner")
			if corner then
				corner.CornerRadius = UDim.new(0.5, 0)
			end
			UITheme.corner(slot.Cooldown, UDim.new(0.5, 0))
			slot.Icon.TextSize = 26
		end
	end
	updateHotbar()
end

-- ----- Botões: árvore (M), inventário (G) e configurações -----
new("Frame", {
	Name = "MenuDivider",
	Size = UDim2.fromOffset(2, 40),
	LayoutOrder = 20,
	BackgroundColor3 = WHITE,
	BackgroundTransparency = 0.8,
	BorderSizePixel = 0,
	Parent = hotbarRow,
})

local menuKeyLabels = {} -- [botão] = rótulo da tecla (troca para o botão do controle)
local function menuButton(order, key, glyph)
	local holder = new("Frame", {
		Size = UDim2.fromOffset(44, 74),
		BackgroundTransparency = 1,
		LayoutOrder = order,
		Parent = hotbarRow,
	})
	local button = round(new("TextButton", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 6),
		Size = UDim2.fromOffset(40, 40),
		BackgroundColor3 = SLOT_BG,
		BackgroundTransparency = 0.3,
		AutoButtonColor = false,
		Font = Fonts.Title,
		TextSize = 18,
		TextColor3 = WHITE,
		Text = glyph,
		Parent = holder,
	}))
	local stroke = UITheme.stroke(button, SLOT_LINE, 1.5)
	if key then
		menuKeyLabels[button] = UITheme.keyLabel({
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.fromScale(0.5, 1),
			Text = key,
			Parent = holder,
		})
	end
	button.MouseEnter:Connect(function()
		stroke.Color = RED
	end)
	button.MouseLeave:Connect(function()
		stroke.Color = SLOT_LINE
	end)
	return button
end

local treeButton = menuButton(21, "M", "⛓")
local inventoryButton = menuButton(22, "G", "▦")
local settingsButton = menuButton(23, nil, "≡")
treeButton:SetAttribute("TutorialAnchor", "TreeButton")
inventoryButton:SetAttribute("TutorialAnchor", "InventoryButton")
settingsButton:SetAttribute("TutorialAnchor", "SettingsButton")
UITheme.tooltip(treeButton, UITheme.tipText("Árvore de habilidades (M)",
	"Gaste os pontos de level em vida, força, guarda... e libere as técnicas dos estilos."))
UITheme.tooltip(inventoryButton, UITheme.tipText("Inventário (G)",
	"Itens dos chefes: vista para ganhar os bônus e mostrar no personagem."))
UITheme.tooltip(settingsButton, UITheme.tipText("Configurações", "Fast Mode, proteção de aliados e corrida automática."))

-- Bolinha com os pontos livres da árvore
local pointsDot = round(new("Frame", {
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.new(1, -3, 0, 3),
	Size = UDim2.fromOffset(18, 18),
	BackgroundColor3 = RED,
	Visible = false,
	ZIndex = 5,
	Parent = treeButton,
}))
UITheme.stroke(pointsDot, BLACK, 1.5)
local pointsDotText = text({
	Size = UDim2.fromScale(1, 1),
	TextXAlignment = Enum.TextXAlignment.Center,
	Font = Fonts.Number,
	TextSize = 10,
	ZIndex = 6,
	Parent = pointsDot,
})

local function fireToggle(guiName)
	local gui = playerGui:FindFirstChild(guiName)
	local toggle = gui and gui:FindFirstChild("Toggle")
	if toggle then
		toggle:Fire()
	end
end
treeButton.MouseButton1Click:Connect(function()
	fireToggle("SkillTree")
end)
inventoryButton.MouseButton1Click:Connect(function()
	fireToggle("Inventory")
end)

-- ================= Controle (Xbox) =================
-- Os botões de combate, poderes e movimento ficam nos scripts donos de cada ação (CombatInput, PowerInput,
-- StaminaDashRunscript). Aqui: direcional para a esquerda troca o estilo da hotbar, para baixo abre a árvore, e os
-- rótulos das teclas viram os botões do controle quando ele é o último a ser usado. Menus abertos pelo controle já
-- começam com um botão selecionado (navegação do Roblox: analógico/direcional e A; B sai da seleção).
local GuiService = game:GetService("GuiService")
local GAMEPAD_LABELS = {
	F = "LT", Z = "B", X = "Y", C = "RB", Q = "LB", V = "↑", B = "→",
}
local MENU_GAMEPAD_LABELS = { [treeButton] = "↓" }

local function usingGamepad()
	return string.sub(UserInputService:GetLastInputType().Name, 1, 7) == "Gamepad"
end

local function refreshKeyLabels()
	local gamepad = usingGamepad()
	for _, slot in slots do
		if slot.KeyLabel then
			slot.KeyLabel.Text = if gamepad then (GAMEPAD_LABELS[slot.Info.Key] or "") else slot.Info.Key
		end
	end
	for button, label in menuKeyLabels do
		label.Text = if gamepad then (MENU_GAMEPAD_LABELS[button] or "") else (if button == treeButton then "M" else "G")
	end
end
UserInputService.LastInputTypeChanged:Connect(refreshKeyLabels)

-- Primeiro botão visível de uma tela (o "×" de fechar, se tiver), para começar a navegação do controle
local function firstButton(gui)
	local first
	for _, item in gui:GetDescendants() do
		if item:IsA("GuiButton") and item.Visible and item.Selectable then
			if item:IsA("TextButton") and item.Text == "×" then
				return item
			end
			first = first or item
		end
	end
	return first
end

-- Estilo seguinte da hotbar (sem nenhum na mão: o primeiro)
local function cycleStyle()
	local tools = currentTools()
	local character = player.Character
	local current
	for index, name in toolOrder do
		local tool = tools[name]
		if tool and tool.Parent == character then
			current = index
		end
	end
	for step = 1, #toolOrder do
		local index = ((current or 0) + step - 1) % #toolOrder + 1
		if tools[toolOrder[index]] and index ~= current then
			toggleTool(index)
			return
		end
	end
end

UserInputService.InputBegan:Connect(function(input, processed)
	if processed or player:GetAttribute("MenuOpen") then return end
	if input.KeyCode == Enum.KeyCode.DPadLeft then
		cycleStyle()
	elseif input.KeyCode == Enum.KeyCode.DPadDown then
		fireToggle("SkillTree")
		task.defer(function()
			local gui = playerGui:FindFirstChild("SkillTree")
			if gui and gui:IsA("ScreenGui") and gui.Enabled then
				GuiService.SelectedObject = firstButton(gui)
			end
		end)
	end
end)

-- ================= Configurações =================

local settingsPanel = UITheme.panel({
	AnchorPoint = Vector2.new(1, 1),
	Position = UDim2.new(1, 0, 0, -8),
	Size = UDim2.fromOffset(270, 322),
	Visible = false,
	ZIndex = 20,
	Parent = actions,
})
UITheme.padding(settingsPanel, 12, 14)

text({
	Size = UDim2.new(1, 0, 0, 22),
	TextXAlignment = Enum.TextXAlignment.Left,
	Font = Fonts.Marker,
	TextSize = 18,
	Text = "CONFIGURAÇÕES",
	ZIndex = 21,
	Parent = settingsPanel,
})

-- Linha com título, explicação e um interruptor à direita. Devolve o botão e set(ligado)
local function settingRow(y, titleText, hintText)
	text({
		Position = UDim2.fromOffset(0, y),
		Size = UDim2.new(1, -60, 0, 18),
		TextXAlignment = Enum.TextXAlignment.Left,
		Font = Fonts.Title,
		TextSize = 14,
		Text = titleText,
		ZIndex = 21,
		Parent = settingsPanel,
	})
	text({
		Position = UDim2.fromOffset(0, y + 18),
		Size = UDim2.new(1, -60, 0, 16),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Font = Fonts.Light,
		TextSize = 12,
		TextColor3 = DIM,
		Text = hintText,
		ZIndex = 21,
		Parent = settingsPanel,
	})
	local switch = round(new("TextButton", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, y + 4),
		Size = UDim2.fromOffset(46, 22),
		AutoButtonColor = false,
		BackgroundColor3 = Colors.PanelLight,
		Text = "",
		ZIndex = 21,
		Parent = settingsPanel,
	}))
	local switchStroke = UITheme.stroke(switch, SLOT_LINE, 1.5)
	local knob = round(new("Frame", {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 3, 0.5, 0),
		Size = UDim2.fromOffset(16, 16),
		BackgroundColor3 = WHITE,
		ZIndex = 22,
		Parent = switch,
	}))
	local function set(on)
		UITheme.tween(knob, 0.15, { Position = if on then UDim2.new(1, -19, 0.5, 0) else UDim2.new(0, 3, 0.5, 0) })
		UITheme.tween(switch, 0.15, { BackgroundColor3 = if on then RED else Colors.PanelLight })
		switchStroke.Color = if on then RED_BRIGHT else SLOT_LINE
	end
	return switch, set
end

-- Fast Mode (só neste cliente)
local fastSwitch, setFastSwitch = settingRow(32, "Fast Mode", "Mais FPS · fica salvo")
fastSwitch.MouseButton1Click:Connect(function()
	FastMode.Toggle()
end)
FastMode.Changed:Connect(function()
	setFastSwitch(FastMode.IsEnabled())
end)
setFastSwitch(FastMode.IsEnabled())

-- Proteção de aliados (atributo AllyProtection, escrito pelo servidor; padrão ligado)
local allySwitch, setAllySwitch = settingRow(78, "Proteção de aliados", "Sem dano no mesmo time")
local function allyProtectionOn()
	return player:GetAttribute("AllyProtection") ~= false
end
local allyShown = allyProtectionOn() -- o que o interruptor mostra agora
local function showAlly(on)
	allyShown = on
	setAllySwitch(on)
end
local allyToken = 0
allySwitch.MouseButton1Click:Connect(function()
	allyToken += 1
	local token = allyToken
	local wanted = not allyShown
	showAlly(wanted) -- mostra na hora; o servidor confirma pelo atributo
	Remotes.SetAllyProtection:FireServer(wanted)
	-- Sem confirmação do servidor: volta a mostrar o valor real
	task.delay(2, function()
		if token == allyToken then
			showAlly(allyProtectionOn())
		end
	end)
end)
player:GetAttributeChangedSignal("AllyProtection"):Connect(function()
	allyToken += 1
	showAlly(allyProtectionOn())
end)
showAlly(allyShown)

-- Corrida automática: quem aplica e salva é o StaminaDashRunscript (MovementAction); o estado vem do atributo AutoRun
local autoRunSwitch, setAutoRunSwitch = settingRow(124, "Corrida automática", "Corre ao andar · Ctrl anda")
local function autoRunOn()
	return player:GetAttribute("AutoRun") ~= false
end
autoRunSwitch.MouseButton1Click:Connect(function()
	fireBindable("MovementAction", "AutoRun", not autoRunOn())
end)
player:GetAttributeChangedSignal("AutoRun"):Connect(function()
	setAutoRunSwitch(autoRunOn())
end)
setAutoRunSwitch(autoRunOn())

-- A qualidade gráfica do Roblox pesa mais que tudo e só o jogador muda (scripts não podem)
text({
	Position = UDim2.fromOffset(0, 170),
	Size = UDim2.new(1, 0, 0, 30),
	TextXAlignment = Enum.TextXAlignment.Left,
	TextYAlignment = Enum.TextYAlignment.Top,
	TextWrapped = true,
	RichText = true,
	Font = Fonts.Light,
	TextSize = 12,
	TextColor3 = DIM,
	Text = `<font color="#{RED_BRIGHT:ToHex()}">Dica:</font> para ainda mais FPS, baixe a Qualidade gráfica em Esc > Configurações.`,
	ZIndex = 21,
	Parent = settingsPanel,
})

-- Volta ao menu principal (MainMenu: personagem, clã, códigos); ele esconde o jogo até apertar JOGAR de novo
local mainMenuButton = UITheme.button({
	Position = UDim2.fromOffset(0, 210),
	Size = UDim2.new(1, 0, 0, 34),
	Font = Fonts.Marker,
	TextSize = 17,
	Text = "MENU PRINCIPAL",
	ZIndex = 21,
	Parent = settingsPanel,
}, RED)
mainMenuButton.MouseButton1Click:Connect(function()
	settingsPanel.Visible = false
	local menu = playerGui:FindFirstChild("TitleScreen")
	local open = menu and menu:FindFirstChild("Open")
	if open and open:IsA("BindableEvent") then
		open:Fire()
	end
end)

-- Refazer o tutorial (TutorialService; a recompensa não se repete)
local tutorialButton = UITheme.button({
	Position = UDim2.fromOffset(0, 252),
	Size = UDim2.new(1, 0, 0, 34),
	Font = Fonts.Marker,
	TextSize = 17,
	Text = "REFAZER TUTORIAL",
	ZIndex = 21,
	Parent = settingsPanel,
}, Colors.PanelLight)
tutorialButton.MouseButton1Click:Connect(function()
	settingsPanel.Visible = false
	Remotes.TutorialAction:FireServer("Restart")
end)

settingsButton.MouseButton1Click:Connect(function()
	settingsPanel.Visible = not settingsPanel.Visible
end)

-- ================= Level up =================

local levelUpLabel = text({
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.28),
	Size = UDim2.fromOffset(700, 80),
	TextXAlignment = Enum.TextXAlignment.Center,
	Font = Fonts.Marker,
	TextSize = 64,
	Text = "LEVEL UP!",
	TextTransparency = 1,
	Parent = screen,
})
local levelUpStroke = new("UIStroke", {
	Color = RED,
	Thickness = 3,
	Transparency = 1,
	Parent = levelUpLabel,
})
local levelUpScale = new("UIScale", { Parent = levelUpLabel })
local levelUpSub = text({
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 1, 2),
	Size = UDim2.fromOffset(700, 24),
	TextXAlignment = Enum.TextXAlignment.Center,
	Font = Fonts.Title,
	TextSize = 18,
	TextTransparency = 1,
	TextStrokeTransparency = 1,
	Parent = levelUpLabel,
})

local levelUpToken = 0
local function showLevelUp(newLevel)
	levelUpToken += 1
	local token = levelUpToken
	levelUpSub.Text = `Level {newLevel}  ·  +{StatConfig.PointsPerLevel} ponto de habilidade (M)`
	levelUpScale.Scale = 0.5
	levelUpLabel.TextTransparency = 0
	levelUpStroke.Transparency = 0
	levelUpSub.TextTransparency = 0
	levelUpSub.TextStrokeTransparency = 0.3
	UITheme.tween(levelUpScale, 0.4, { Scale = 1 }, Enum.EasingStyle.Back)
	task.delay(2, function()
		if token ~= levelUpToken then return end
		UITheme.tween(levelUpLabel, 0.5, { TextTransparency = 1 })
		UITheme.tween(levelUpStroke, 0.5, { Transparency = 1 })
		UITheme.tween(levelUpSub, 0.5, { TextTransparency = 1, TextStrokeTransparency = 1 })
	end)
end

-- ================= Atualizações =================

-- Kanji do clã (na cor da raridade) + nome do jogador + tag do caminho
local function updateName()
	local name = UITheme.escape(player.DisplayName)
	local path = PathData.FromPlayer(player)
	local info = PathData.Paths[path]
	local clan = ClanData.Get(player:GetAttribute("Clan"))
	local clanText = if clan then `<font color="#{ClanData.Color(clan.Id):ToHex()}">{clan.Kanji}</font> ` else ""
	nameLabel.Text = `{clanText}{name}  <font color="#{info.Color:ToHex()}">{UITheme.upper(info.DisplayName)}</font>`
end
player:GetAttributeChangedSignal("Clan"):Connect(updateName)

local function updateLifespan()
	local isHunter = PathData.FromPlayer(player) == "Hunter"
	local wasShown = lifespanBar.Frame.Visible
	if isHunter ~= wasShown then
		layoutVitals(isHunter)
	end
	if not isHunter then return end
	local maxLifespan = player:GetAttribute("MaxLifespan")
	if type(maxLifespan) ~= "number" or maxLifespan <= 0 then
		maxLifespan = PathData.MaxLifespan
	end
	local lifespan = player:GetAttribute("Lifespan")
	if type(lifespan) ~= "number" then
		lifespan = maxLifespan
	end
	-- Quando a barra acabou de aparecer, pula direto para o valor (sem animar desde o cheio)
	lifespanBar.Set(lifespan / maxLifespan, nil, not wasShown)
	lifespanLabel.Text = `⏳ tempo de vida {math.floor(lifespan)} / {math.floor(maxLifespan)}`
end

local function onPathChanged()
	updateName()
	updatePowers()
	updateLifespan()
end
for _, attribute in { "Path", "Contracts", "FiendType", "ContractForm", "Hybrid", "HybridContract", "HybridForm", "HybridFiend" } do
	player:GetAttributeChangedSignal(attribute):Connect(onPathChanged)
end
player:GetAttributeChangedSignal("Lifespan"):Connect(updateLifespan)
player:GetAttributeChangedSignal("MaxLifespan"):Connect(updateLifespan)
onPathChanged()

local function updateGold()
	goldLabel.Text = UITheme.formatNumber(gold.Value)
end

local function updateXP()
	local ratio
	if level.Value >= StatConfig.MaxLevel then
		ratio = 1
		xpLabel.Text = "LEVEL MÁXIMO"
	else
		local needed = math.max(1, xpNeeded.Value)
		ratio = math.clamp(xp.Value / needed, 0, 1)
		xpLabel.Text = `{UITheme.formatNumber(xp.Value)} / {UITheme.formatNumber(needed)}`
	end
	local lit = math.floor(ratio * RING_SEGMENTS + 0.5)
	for i, segment in ringSegments do
		local on = i <= lit
		segment.BackgroundColor3 = if on then RED_BRIGHT else WHITE
		segment.BackgroundTransparency = if on then 0 else 0.8
	end
end

local function updatePoints()
	pointsDot.Visible = points.Value > 0
	pointsDotText.Text = if points.Value > 99 then "99+" else tostring(points.Value)
end

local lastGold = gold.Value
gold.Changed:Connect(function(value)
	local delta = value - lastGold
	lastGold = value
	updateGold()
	if delta > 0 then
		UITheme.floatText(goldRow, `+{UITheme.formatNumber(delta)}`, CREAM, UDim2.new(1, -40, 0, 0))
	end
end)

local lastXP = xp.Value
xp.Changed:Connect(function(value)
	local delta = value - lastXP
	lastXP = value
	updateXP()
	if delta > 0 then
		UITheme.floatText(ring, `+{delta} XP`, RED_BRIGHT, UDim2.new(0.5, 0, 0, -4))
	end
end)

local lastLevel = level.Value
level.Changed:Connect(function(value)
	levelNumber.Text = tostring(value)
	if value > lastLevel then
		showLevelUp(value)
		ringScale.Scale = 1.18
		UITheme.tween(ringScale, 0.35, { Scale = 1 }, Enum.EasingStyle.Back)
	end
	lastLevel = value
	updateXP()
end)

xpNeeded.Changed:Connect(updateXP)
points.Changed:Connect(updatePoints)

levelNumber.Text = tostring(level.Value)
updateGold()
updateXP()
updatePoints()

-- Bônus: mudam com os Stats e os atributos Tree<Efeito> (árvore e itens)
local function watchStat(value)
	if value:IsA("IntValue") then
		value.Changed:Connect(updateBonuses)
	end
	updateBonuses()
end
statsFolder.ChildAdded:Connect(watchStat)
for _, value in statsFolder:GetChildren() do
	watchStat(value)
end
player.AttributeChanged:Connect(function(name)
	if string.sub(name, 1, 4) == "Tree" then
		updateBonuses()
	end
end)
updateBonuses()

-- Hotbar: muda quando um estilo entra/sai da mochila ou do personagem. Cada vez que o jogador renasce o Roblox troca
-- a mochila por uma nova: as conexões passam para ela (presa na antiga, a hotbar perdia o estilo guardado depois de
-- morrer, e ele parecia sumir do inventário)
local backpackConnections = {}
local function watchBackpack(backpack)
	for _, connection in backpackConnections do
		connection:Disconnect()
	end
	backpackConnections = {
		backpack.ChildAdded:Connect(updateHotbar),
		backpack.ChildRemoved:Connect(updateHotbar),
	}
	updateHotbar()
end
player.ChildAdded:Connect(function(child)
	if child:IsA("Backpack") then
		watchBackpack(child)
	end
end)
watchBackpack(player:WaitForChild("Backpack"))

-- Teclas 1 a 5 da hotbar (não com o menu principal aberto)
UserInputService.InputBegan:Connect(function(input, processed)
	if processed or player:GetAttribute("MenuOpen") then return end
	local index = table.find(HOTBAR_KEYS, input.KeyCode)
	if index then
		toggleTool(index)
	end
end)

-- ================= Sangue na borda da tela =================
-- Pulsa com a vida baixa e pisca quando leva dano. Fica embaixo da HUD (DisplayOrder 0) e cobre a barra do topo.

local vignetteGui = UITheme.screen("BloodVignette", 0, playerGui)
vignetteGui.IgnoreGuiInset = true
local vignetteEdges = {}
for _, edge in {
	{ Size = UDim2.fromScale(0.2, 1), Position = UDim2.fromScale(0, 0), Rotation = 0 },
	{ Size = UDim2.fromScale(0.2, 1), Position = UDim2.fromScale(0.8, 0), Rotation = 180 },
	{ Size = UDim2.fromScale(1, 0.22), Position = UDim2.fromScale(0, 0), Rotation = 90 },
	{ Size = UDim2.fromScale(1, 0.22), Position = UDim2.fromScale(0, 0.78), Rotation = -90 },
} do
	local frame = new("Frame", {
		Size = edge.Size,
		Position = edge.Position,
		BackgroundColor3 = Color3.fromRGB(120, 0, 8),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Parent = vignetteGui,
	})
	new("UIGradient", {
		Rotation = edge.Rotation,
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0),
			NumberSequenceKeypoint.new(0.6, 0.75),
			NumberSequenceKeypoint.new(1, 1),
		}),
		Parent = frame,
	})
	table.insert(vignetteEdges, frame)
end

local healthRatio = 1
local hurtFlash = 0
local lastHealth
RunService.RenderStepped:Connect(function(dt)
	hurtFlash = math.max(0, hurtFlash - dt * 2.5)
	local low = if healthRatio < 0.35 and healthRatio > 0 then (0.35 - healthRatio) / 0.35 else 0
	local pulse = low * (0.65 + 0.35 * math.sin(os.clock() * 5))
	local alpha = math.max(pulse * 0.6, hurtFlash * 0.5)
	for _, frame in vignetteEdges do
		frame.BackgroundTransparency = 1 - alpha
	end
end)

-- Vida e o personagem (a hotbar olha o que ele segura)
local characterConnections = {}
local function bindCharacter(character)
	releaseHeldSlots()
	for _, connection in characterConnections do
		connection:Disconnect()
	end
	table.clear(characterConnections)
	currentHumanoid = nil
	table.insert(characterConnections, character.ChildAdded:Connect(updateHotbar))
	table.insert(characterConnections, character.ChildRemoved:Connect(updateHotbar))
	updateHotbar()

	local humanoid = character:WaitForChild("Humanoid", 10)
	if not humanoid or character ~= player.Character then return end
	currentHumanoid = humanoid
	table.insert(characterConnections, humanoid.Died:Connect(releaseHeldSlots))

	local function update()
		local maxHealth = math.max(1, humanoid.MaxHealth)
		local health = math.max(0, humanoid.Health)
		hpBar.Set(health / maxHealth)
		hpNumbers.Text = `{math.ceil(health)} / {math.floor(maxHealth)}`
		healthRatio = health / maxHealth
		-- Perdeu pelo menos 2% da vida de uma vez: a borda pisca em vermelho
		if lastHealth and lastHealth - health >= maxHealth * 0.02 then
			hurtFlash = math.clamp((lastHealth - health) / maxHealth * 4, 0.45, 1)
		end
		lastHealth = health
	end
	lastHealth = nil
	table.insert(characterConnections, humanoid.HealthChanged:Connect(update))
	table.insert(characterConnections, humanoid:GetPropertyChangedSignal("MaxHealth"):Connect(update))
	update()
end
player.CharacterAdded:Connect(bindCharacter)
if player.Character then
	task.spawn(bindCharacter, player.Character)
end

-- Ícones de Z/X/C conforme o estilo equipado (desequipado, mostra o último estilo). Glyph da skill no CombatStyles.
-- (os dados também contam: com a fusão do contrato o estilo tem o mesmo nome, mas outras skills)
local shownStyle, shownData
local function updateCombatSlots(styleName, style)
	if not styleName or (styleName == shownStyle and style == shownData) then return end
	shownStyle, shownData = styleName, style
	local glyphs = SKILL_GLYPHS[styleName] or {}
	for _, slot in slots do
		local info = slot.Info
		if info.Skill then
			local skill = style.Skills[info.Skill]
			slot.Holder.Visible = skill ~= nil -- o estilo não usa essa tecla
			slot.Icon.Text = glyphs[info.Skill] or (skill and (skill.Glyph or skill.Icon)) or info.Glyph
			if skill and (player:GetAttribute(info.Attribute) or 0) <= workspace:GetServerTimeNow() then
				slot.Total = math.max(0.1, skill.Cooldown or 1)
			end
		end
	end
end
updateCombatSlots("Punhos", CombatStyles.Styles.Punhos)
refreshKeyLabels()

-- Contorno aceso enquanto a ação está ativa (guarda levantada, soco carregando)
local function setActive(slot, active, color)
	if active then
		slot.Stroke.Color = color
		slot.WasActive = true
	elseif slot.WasActive then
		slot.WasActive = false
		slot.Stroke.Color = slot.BaseColor
	end
end

-- HUD a até 30 Hz: evita refazer custos, textos e cores a cada frame em monitores de alta frequência.
local hudElapsed = 0
local HUD_INTERVAL = 1 / 30
RunService.RenderStepped:Connect(function(dt)
	hudElapsed += dt
	if hudElapsed < HUD_INTERVAL then return end
	hudElapsed %= HUD_INTERVAL
	local now = workspace:GetServerTimeNow()
	local character = player.Character
	local stunned = character ~= nil and character:GetAttribute("Stunned") == true
	local styleName, style = CombatStyles.FromCharacter(character)
	updateCombatSlots(styleName, style)
	local blocking = character ~= nil and character:GetAttribute("Blocking") == true
	local charging = character ~= nil and character:GetAttribute("Charging") == true

	local maxStamina = player:GetAttribute("MaxStamina") or 100
	local stamina = player:GetAttribute("PredictedStamina") or player:GetAttribute("Stamina") or maxStamina
	staminaBar.Set(stamina / math.max(1, maxStamina), nil, true)

	for _, slot in slots do
		local info = slot.Info
		local usable = not stunned
		local remaining = 0

		if info.Power then
			local skill = slot.Skill
			if skill then
				remaining = math.max(0, (player:GetAttribute(info.Attribute) or 0) - now)
				local paid = canPay(skill)
				usable = usable and paid
				slot.CostLabel.TextColor3 = if paid then slot.CostColor else RED_BRIGHT
			else
				usable = false
			end
		elseif info.Block then
			local maxGuard = player:GetAttribute("MaxGuard") or 100
			local guard = player:GetAttribute("Guard") or maxGuard
			local minGuard = if style then style.Block.MinGuard else 0
			slot.GuardFill.Size = UDim2.fromScale(math.clamp(guard / math.max(1, maxGuard), 0, 1), 1)
			slot.GuardFill.BackgroundColor3 = if guard < minGuard then RED_BRIGHT else WHITE
			usable = usable and style ~= nil and guard >= minGuard
			setActive(slot, blocking, WHITE)
		elseif info.StaminaCost then
			-- Dash: recarga curta (DashReadyAt, do script de movimento) e stamina (mais barato com "Dash econômico")
			remaining = math.max(0, math.max(player:GetAttribute(info.Attribute) or 0,
				player:GetAttribute("PredictedDashReadyAt") or 0) - now)
			local cost = info.StaminaCost * math.max(0, 1 - (player:GetAttribute("TreeDashCost") or 0))
			usable = usable and stamina >= cost
		elseif info.Attribute then
			remaining = math.max(0, (player:GetAttribute(info.Attribute) or 0) - now)
			local skill = style and style.Skills[info.Skill]
			local locked = skill ~= nil and skill.Technique ~= nil and player:GetAttribute("Tech_" .. skill.Technique) ~= true
			usable = usable and style ~= nil and not locked
			if slot.Lock then
				slot.Lock.Visible = locked
				slot.Icon.Visible = not locked
			end
			setActive(slot, charging and skill ~= nil and skill.Hold == true, RED_BRIGHT)
		end

		local ratio = if remaining > 0 then math.clamp(remaining / slot.Total, 0, 1) else 0
		slot.Cooldown.Size = UDim2.fromScale(1, ratio)
		slot.CooldownText.Text = if remaining > 0 then string.format("%.1f", remaining) else ""
		slot.Icon.TextTransparency = if usable and remaining == 0 then 0 else 0.6

		-- Pisca quando a recarga termina
		if slot.WasCooling and remaining == 0 then
			slot.Stroke.Color = WHITE
			slot.Stroke.Thickness = 2.5
			UITheme.tween(slot.Stroke, 0.45, { Thickness = 1.5, Color = slot.BaseColor })
		end
		slot.WasCooling = remaining > 0
	end

	-- Vida baixa: a borda da barra pulsa em vermelho
	if hpStroke then
		if hpBar.Ratio < 0.3 then
			local pulse = (math.sin(os.clock() * 6) + 1) / 2
			hpStroke.Color = BLACK:Lerp(RED_BRIGHT, pulse)
		else
			hpStroke.Color = BLACK
		end
	end
end)
