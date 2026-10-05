-- HUD principal (refeita em 2026-10-05, pedido do usuário: mais moderna e menos poluída). Regras do visual:
--   sem molduras nem degradês pesados, cantos arredondados, fundo escuro translúcido e um destaque vermelho só no que
--   importa agora (estilo na mão, guarda levantada, vida baixa). Fonte Builder Sans nos textos e números.
--   embaixo à esquerda (no celular, em cima à esquerda): level, nome/clã/caminho e gold numa linha; a vida com o número
--     dentro da barra; fôlego, tempo de vida (só Caçador) e XP em linhas finas. Os bônus (árvore + itens) saíram da
--     tela: aparecem no balão do level e no inventário.
--   embaixo no centro, numa linha só: estilos de combate (1 a 5, só as casas com estilo), as habilidades (F guarda,
--     Z/X/C do estilo, Q dash) e os poderes do caminho (V/B). A tecla fica no canto de cada casa.
--   menus em botões redondos pequenos (árvore M, inventário G, pescaria, passes e configurações) numa coluna colada no
--     lado esquerdo do minimapa, fora da linha de combate (em cima do minimapa fica o cartão de navegação dele). A
--     pescaria e os passes não têm mais botão solto na tela.
--   animações de ganho (XP, gold, LEVEL UP) e a borda de sangue com a vida baixa
--   no celular (sem teclado): as habilidades viram botões redondos grandes no canto de baixo à direita, em volta de um
--     botão de ataque (M1), ao lado do pulo do Roblox; a hotbar fica maior e os menus vão para a linha de baixo. Para
--     ver esse layout no Studio, ponha o atributo ForceMobileHUD = true no ReplicatedStorage antes do Play.
-- As telas grandes ficam em SkillTreeMenu (árvore), Inventory (inventário) e StatusMenu (caminho).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")

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
local SLOT_BG = Color3.fromRGB(16, 16, 20)
local SLOT_LINE = Color3.fromRGB(255, 255, 255) -- contorno das casas, quase transparente (LINE_FADE)
local LINE_FADE = 0.86
local TRACK = Color3.fromRGB(8, 8, 10) -- fundo das barras

-- Builder Sans (fonte atual do Roblox) nos textos e números da HUD; os kanji dos ícones continuam na fonte do tema
local FONT_HEAVY = Enum.Font.BuilderSansExtraBold
local FONT_BOLD = Enum.Font.BuilderSansBold
local FONT_MEDIUM = Enum.Font.BuilderSansMedium

local touchOnly = (UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled)
	or ReplicatedStorage:GetAttribute("ForceMobileHUD") == true
local HOTBAR_SLOTS = 5
local HOTBAR_KEYS = { Enum.KeyCode.One, Enum.KeyCode.Two, Enum.KeyCode.Three, Enum.KeyCode.Four, Enum.KeyCode.Five }
-- Ícone de cada estilo de combate na hotbar e das skills dele (kanji brancos, como os nós da árvore)
local STYLE_GLYPHS = { Punhos = "拳", Katana = "刀" }
local SKILL_GLYPHS = { Punhos = { Z = "連", X = "溜" } }

local SLOT_SIZE = 42 -- casas da linha de baixo (estilos, habilidades e poderes)
local SLOT_GAP = 6
local MENU_SIZE = if touchOnly then 38 else 32 -- no celular um pouco maior (dedo)

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
	props.Font = props.Font or FONT_BOLD
	return new("TextLabel", props)
end

-- Contorno fino e discreto das casas (acende em vermelho/branco quando a ação está ativa)
local function softStroke(parent)
	return UITheme.stroke(parent, SLOT_LINE, 1, LINE_FADE)
end

local function setStroke(stroke, color, thickness)
	stroke.Color = color
	stroke.Thickness = thickness or 1
	stroke.Transparency = if color == SLOT_LINE then LINE_FADE else 0
end

-- Letra da tecla no canto de cima, à esquerda, dentro da casa
local function cornerKey(parent, key)
	return text({
		Position = UDim2.fromOffset(5, 3),
		Size = UDim2.fromOffset(16, 12),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		Font = FONT_BOLD,
		TextSize = 11,
		TextColor3 = DIM,
		Text = key,
		ZIndex = 7,
		Parent = parent,
	})
end

-- Barra fina, sem moldura: trilho escuro, preenchimento e um rastro claro que acompanha a perda com atraso.
-- Devolve { Frame, Fill, Ratio, Set(ratio, instant?) }
local function slimBar(props, color, gradient)
	local track = new("Frame", {
		Position = props.Position,
		Size = props.Size,
		BackgroundColor3 = TRACK,
		BackgroundTransparency = 0.35,
		BorderSizePixel = 0,
		ClipsDescendants = true,
		Visible = props.Visible ~= false,
		Parent = props.Parent,
	})
	local radius = UDim.new(0, math.min(4, math.floor(props.Size.Y.Offset / 2)))
	UITheme.corner(track, radius)
	local trail = new("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = WHITE,
		BackgroundTransparency = 0.5,
		BorderSizePixel = 0,
		Parent = track,
	})
	UITheme.corner(trail, radius)
	local fill = new("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = color,
		BorderSizePixel = 0,
		ZIndex = 2,
		Parent = track,
	})
	UITheme.corner(fill, radius)
	if gradient then
		-- Degradê da esquerda (escura) para a direita (clara); o fundo branco deixa as cores como estão
		fill.BackgroundColor3 = WHITE
		new("UIGradient", { Color = ColorSequence.new(gradient[1], gradient[2]), Rotation = 0, Parent = fill })
	end

	local api = { Frame = track, Fill = fill, Ratio = 1 }
	local trailTween
	function api.Set(ratio, instant)
		ratio = math.clamp(ratio, 0, 1)
		if ratio == api.Ratio then return end
		local previous = api.Ratio
		api.Ratio = ratio
		local target = UDim2.fromScale(ratio, 1)
		if trailTween then
			trailTween:Cancel()
			trailTween = nil
		end
		if instant then
			fill.Size = target
			trail.Size = target
			return
		end
		UITheme.tween(fill, 0.15, { Size = target })
		if ratio < previous then
			trailTween = TweenService:Create(trail,
				TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0, false, 0.3), { Size = target })
			trailTween:Play()
		else
			trail.Size = target
		end
	end
	return api
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
	UITheme.stroke(arc, DIM, 2)
	local body = round(new("Frame", {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromScale(0.5, 1),
		Size = UDim2.fromOffset(size * 0.78, size * 0.52),
		BackgroundColor3 = DIM,
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

-- ================= Vida, fôlego, XP e gold =================

local VITALS_WIDTH = 300

local vitals = new("Frame", {
	Name = "Vitals",
	AnchorPoint = if touchOnly then Vector2.new(0, 0) else Vector2.new(0, 1),
	Position = if touchOnly then UDim2.fromOffset(12, 8) else UDim2.new(0, 20, 1, -18),
	Size = UDim2.fromOffset(VITALS_WIDTH, 64),
	BackgroundTransparency = 1,
	Parent = screen,
})
UITheme.autoScale(vitals, 1280, 720)
-- O tutorial (Tutorial.client.luau) acha os elementos que destaca pelo atributo TutorialAnchor
vitals:SetAttribute("TutorialAnchor", "Vitals")

-- Linha de cima: level, nome (clã + caminho) e gold
local topRow = new("Frame", {
	Size = UDim2.new(1, 0, 0, 22),
	BackgroundTransparency = 1,
	Parent = vitals,
})
local levelBadge = round(new("Frame", {
	Size = UDim2.fromOffset(0, 22),
	AutomaticSize = Enum.AutomaticSize.X,
	BackgroundColor3 = RED,
	BorderSizePixel = 0,
	Parent = topRow,
}), UDim.new(0, 6))
UITheme.padding(levelBadge, 0, 7, 0, 7)
local levelBadgeScale = new("UIScale", { Parent = levelBadge })
local levelNumber = text({
	Size = UDim2.fromOffset(0, 22),
	AutomaticSize = Enum.AutomaticSize.X,
	RichText = true,
	Font = FONT_HEAVY,
	TextSize = 14,
	Parent = levelBadge,
})
local nameLabel = text({
	Position = UDim2.fromOffset(44, 0),
	Size = UDim2.new(1, -130, 1, 0),
	TextXAlignment = Enum.TextXAlignment.Left,
	TextTruncate = Enum.TextTruncate.AtEnd,
	RichText = true,
	Font = FONT_BOLD,
	TextSize = 15,
	TextStrokeTransparency = 0.7,
	Parent = topRow,
})
-- O nome começa logo depois do level e vai até o gold (a largura do selo muda com o número)
local GOLD_WIDTH = 86
local function placeName()
	local scale = math.max(0.01, levelBadge.AbsoluteSize.Y / 22)
	local badgeWidth = levelBadge.AbsoluteSize.X / scale
	nameLabel.Position = UDim2.fromOffset(badgeWidth + 8, 0)
	nameLabel.Size = UDim2.new(1, -(badgeWidth + 8 + GOLD_WIDTH + 6), 1, 0)
end
levelBadge:GetPropertyChangedSignal("AbsoluteSize"):Connect(placeName)
-- Gold: moeda creme e o número, à direita
local goldRow = new("Frame", {
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.fromScale(1, 0),
	Size = UDim2.fromOffset(GOLD_WIDTH, 22),
	BackgroundTransparency = 1,
	Parent = topRow,
})
round(new("Frame", {
	AnchorPoint = Vector2.new(1, 0.5),
	Position = UDim2.new(1, 0, 0.5, 0),
	Size = UDim2.fromOffset(9, 9),
	BackgroundColor3 = CREAM,
	Parent = goldRow,
}))
local goldLabel = text({
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, -14, 0, 0),
	Size = UDim2.new(1, -14, 1, 0),
	TextXAlignment = Enum.TextXAlignment.Right,
	Font = FONT_HEAVY,
	TextSize = 14,
	TextColor3 = CREAM,
	TextStrokeTransparency = 0.7,
	Parent = goldRow,
})

-- Vida com o número dentro da barra
local hpBar = slimBar({
	Position = UDim2.fromOffset(0, 28),
	Size = UDim2.new(1, 0, 0, 16),
	Parent = vitals,
}, Colors.Health[1], { Color3.fromRGB(150, 8, 20), Colors.Health[1] })
local hpNumbers = text({
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, -6, 0, 0),
	Size = UDim2.new(1, -12, 1, 0),
	TextXAlignment = Enum.TextXAlignment.Right,
	Font = FONT_HEAVY,
	TextSize = 12,
	TextStrokeTransparency = 0.55,
	ZIndex = 3,
	Parent = hpBar.Frame,
})
local staminaBar = slimBar({
	Position = UDim2.fromOffset(0, 48),
	Size = UDim2.new(1, 0, 0, 4),
	Parent = vitals,
}, WHITE)
-- Tempo de vida: só aparece para Caçadores
local lifespanBar = slimBar({
	Position = UDim2.fromOffset(0, 56),
	Size = UDim2.new(1, 0, 0, 4),
	Visible = false,
	Parent = vitals,
}, Colors.Lifespan[1])
-- XP: a linha mais fina, embaixo de tudo
local xpBar = slimBar({
	Position = UDim2.fromOffset(0, 56),
	Size = UDim2.new(1, 0, 0, 3),
	Parent = vitals,
}, RED_BRIGHT)

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

-- Balão do level: XP e os bônus ativos (antes ficavam em pílulas em cima da vida)
local function levelTip()
	local lines = {}
	if level.Value >= StatConfig.MaxLevel then
		table.insert(lines, "Level máximo.")
	else
		table.insert(lines, `XP: {UITheme.formatNumber(xp.Value)} / {UITheme.formatNumber(xpNeeded.Value)}`)
		table.insert(lines, `Cada level dá {StatConfig.PointsPerLevel} ponto na árvore de habilidades (M).`)
	end
	local effects = currentBonuses()
	local bonusLines = {}
	for _, key in SkillTreeData.EffectOrder do
		local value = effects[key]
		if value ~= nil then
			local info = SkillTreeData.EffectInfo[key] or {}
			table.insert(bonusLines, `{info.Icon or "•"} {SkillTreeData.EffectText(key, value)}`)
		end
	end
	if #bonusLines > 0 then
		table.insert(lines, `\n<font color="#{WHITE:ToHex()}"><b>Bônus ativos</b></font>`)
		table.insert(lines, table.concat(bonusLines, "\n"))
	end
	return UITheme.tipText(`Level {level.Value}`, table.concat(lines, "\n"))
end

UITheme.tooltip(topRow, levelTip)
UITheme.tooltip(xpBar.Frame, levelTip)
UITheme.tooltip(hpBar.Frame, UITheme.tipText("Vida", "A regeneração da árvore e dos itens recupera fora de combate."))
UITheme.tooltip(staminaBar.Frame, UITheme.tipText("Fôlego", "O dash gasta; recupera sozinho."))
UITheme.tooltip(lifespanBar.Frame, function()
	local maxLifespan = player:GetAttribute("MaxLifespan")
	if type(maxLifespan) ~= "number" or maxLifespan <= 0 then
		maxLifespan = PathData.MaxLifespan
	end
	local lifespan = player:GetAttribute("Lifespan")
	if type(lifespan) ~= "number" then
		lifespan = maxLifespan
	end
	return UITheme.tipText(`Tempo de vida {math.floor(lifespan)} / {math.floor(maxLifespan)}`,
		"Os poderes do Caçador gastam tempo de vida. Ele recupera sozinho.")
end)
UITheme.tooltip(goldRow, UITheme.tipText("Gold", "Vem dos inimigos e das missões."))

-- Altura do bloco conforme o tempo de vida (Caçador) aparece ou não
local function layoutVitals(showLifespan)
	lifespanBar.Frame.Visible = showLifespan
	xpBar.Frame.Position = UDim2.fromOffset(0, if showLifespan then 64 else 56)
	vitals.Size = UDim2.fromOffset(VITALS_WIDTH, if showLifespan then 67 else 59)
end
layoutVitals(false)

-- ================= Linha de baixo: estilos, habilidades e poderes =================

local actions = new("Frame", {
	Name = "Actions",
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, -16),
	Size = UDim2.fromOffset(0, SLOT_SIZE),
	AutomaticSize = Enum.AutomaticSize.X,
	BackgroundTransparency = 1,
	Parent = screen,
})
UITheme.list(actions, 12, Enum.FillDirection.Horizontal, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Center)
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

local function row(name, order)
	local frame = new("Frame", {
		Name = name,
		Size = UDim2.fromOffset(0, SLOT_SIZE),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundTransparency = 1,
		LayoutOrder = order,
		Parent = actions,
	})
	UITheme.list(frame, SLOT_GAP, Enum.FillDirection.Horizontal, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Center)
	return frame
end

local function divider(parent, order)
	return new("Frame", {
		Size = UDim2.fromOffset(1, 26),
		LayoutOrder = order,
		BackgroundColor3 = WHITE,
		BackgroundTransparency = 0.82,
		BorderSizePixel = 0,
		Parent = parent,
	})
end

local hotbarRow = row("Hotbar", 1)
hotbarRow:SetAttribute("TutorialAnchor", "Hotbar")
local rowDivider = divider(actions, 2)
local skillsRow = row("Skills", 3)
skillsRow:SetAttribute("TutorialAnchor", "Skills")

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

local powerDivider = divider(skillsRow, 10)
powerDivider.Visible = false

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
		Size = UDim2.fromOffset(SLOT_SIZE, SLOT_SIZE),
		BackgroundTransparency = 1,
		LayoutOrder = order,
		Parent = skillsRow,
	})
	holder:SetAttribute("TutorialAnchor", "Slot_" .. info.Key)
	local button = round(new("TextButton", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1, 1),
		AutoButtonColor = false,
		BackgroundColor3 = SLOT_BG,
		BackgroundTransparency = 0.3,
		ClipsDescendants = true,
		Text = "",
		Parent = holder,
	}), UDim.new(0, 10))
	local stroke = softStroke(button)
	local keyLabel = cornerKey(button, info.Key)

	local icon = text({
		Size = UDim2.fromScale(1, 1),
		TextXAlignment = Enum.TextXAlignment.Center,
		Font = Fonts.Title,
		TextSize = 19,
		Text = info.Glyph,
		ZIndex = 2,
		Parent = button,
	})

	-- Custo do poder (canto de cima, à direita)
	local costLabel
	if info.Power then
		costLabel = text({
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -4, 0, 3),
			Size = UDim2.fromOffset(30, 11),
			TextXAlignment = Enum.TextXAlignment.Right,
			Font = FONT_BOLD,
			TextSize = 10,
			TextStrokeTransparency = 0.6,
			ZIndex = 7,
			Parent = button,
		})
	end

	-- Barra da guarda no slot do block
	local guardFill
	if info.Block then
		local guardTrack = round(new("Frame", {
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -5),
			Size = UDim2.new(1, -14, 0, 3),
			BackgroundColor3 = BLACK,
			BackgroundTransparency = 0.3,
			BorderSizePixel = 0,
			ZIndex = 3,
			Parent = button,
		}))
		guardFill = round(new("Frame", {
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = WHITE,
			BorderSizePixel = 0,
			ZIndex = 4,
			Parent = guardTrack,
		}))
	end

	-- Escurece de cima para baixo enquanto está em recarga
	local cooldown = new("Frame", {
		Size = UDim2.fromScale(1, 0),
		BackgroundColor3 = BLACK,
		BackgroundTransparency = 0.35,
		BorderSizePixel = 0,
		ZIndex = 5,
		Parent = button,
	})
	local cooldownText = text({
		Size = UDim2.fromScale(1, 1),
		TextXAlignment = Enum.TextXAlignment.Center,
		Font = FONT_HEAVY,
		TextSize = 15,
		TextStrokeTransparency = 0.5,
		ZIndex = 6,
		Parent = button,
	})
	-- Cadeado: técnica do estilo ainda não desbloqueada na árvore (atributo Tech_<Técnica>)
	local lock = if info.Skill or info.Power then padlock(button, 16) else nil

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
		BaseTransparency = LINE_FADE,
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
		-- Os poderes ficam com o contorno na cor do caminho (separa do estilo de combate)
		slot.BaseColor = pathColor
		slot.BaseTransparency = 0.45
		slot.Stroke.Color = pathColor
		slot.Stroke.Transparency = 0.45
	end
	powerDivider.Visible = anyShown
end

-- ----- Hotbar: estilos de combate (Tools) nas casas 1 a 5 (só as casas com estilo aparecem) -----
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
	local button = round(new("TextButton", {
		Size = UDim2.fromOffset(SLOT_SIZE, SLOT_SIZE),
		BackgroundColor3 = SLOT_BG,
		BackgroundTransparency = 0.3,
		AutoButtonColor = false,
		LayoutOrder = index,
		Visible = false,
		Text = "",
		Parent = hotbarRow,
	}), UDim.new(0, 10))
	local stroke = softStroke(button)
	local scale = new("UIScale", { Parent = button })
	local glyph = text({
		Size = UDim2.fromScale(1, 1),
		TextXAlignment = Enum.TextXAlignment.Center,
		Font = Fonts.Title,
		TextSize = 20,
		Parent = button,
	})
	cornerKey(button, tostring(index))
	-- Risquinho vermelho embaixo do estilo que está na mão
	local underline = round(new("Frame", {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -4),
		Size = UDim2.fromOffset(16, 3),
		BackgroundColor3 = RED,
		BorderSizePixel = 0,
		Visible = false,
		ZIndex = 3,
		Parent = button,
	}))
	button.MouseButton1Click:Connect(function()
		toggleTool(index)
	end)
	UITheme.tooltip(button, function()
		local name = toolOrder[index]
		local tool = name and currentTools()[name]
		if not tool then
			return UITheme.tipText(`Casa {index}`, "Vazia: os estilos de combate que você ganhar aparecem aqui.")
		end
		local style = CombatStyles.Styles[name]
		return UITheme.tipText(`{if style then style.DisplayName or name else name} ({index})`,
			"Estilo de combate. Aperte o número (ou clique) para equipar ou guardar.")
	end)
	hotbarSlots[index] = { Button = button, Stroke = stroke, Scale = scale, Glyph = glyph, Underline = underline }
end

local attackGlyph -- botão de ataque do celular (mostra o estilo na mão)

local function updateHotbar()
	local tools = currentTools()
	local character = player.Character
	local any = false
	for index, slot in hotbarSlots do
		local name = toolOrder[index]
		local tool = name and tools[name]
		local equipped = tool ~= nil and tool.Parent == character
		slot.Glyph.Text = if tool then (STYLE_GLYPHS[name] or UITheme.upper(string.sub(name, 1, 2))) else ""
		slot.Button.Visible = tool ~= nil
		any = any or tool ~= nil
		setStroke(slot.Stroke, if equipped then RED else SLOT_LINE, if equipped then 1.5 else 1)
		slot.Button.BackgroundTransparency = if equipped then 0.15 else 0.3
		slot.Underline.Visible = equipped
		UITheme.tween(slot.Scale, 0.12, { Scale = if equipped then 1.06 else 1 })
	end
	-- Sem estilo nenhum (logo ao nascer), a linha dos estilos e o separador somem
	hotbarRow.Visible = any
	rowDivider.Visible = any and skillsRow.Visible
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
		BackgroundTransparency = 0.2,
		Text = "",
		Parent = pad,
	}))
	attack:SetAttribute("TutorialAnchor", "AttackButton")
	UITheme.stroke(attack, RED, 2.5)
	local attackScale = new("UIScale", { Parent = attack })
	attackGlyph = text({
		Size = UDim2.fromScale(1, 1),
		TextXAlignment = Enum.TextXAlignment.Center,
		Font = Fonts.Title,
		TextSize = 38,
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

	-- Os slots das habilidades: os mesmos objetos, redondos e maiores, sem a tecla no canto
	for _, slot in slots do
		local offset = MOBILE_LAYOUT[slot.Info.Key]
		if offset then
			local holder = slot.Holder
			holder.Parent = pad
			holder.AnchorPoint = Vector2.new(0.5, 0.5)
			holder.Position = UDim2.fromOffset(offset.X, offset.Y)
			holder.Size = UDim2.fromOffset(MOBILE_SLOT, MOBILE_SLOT)
			slot.KeyLabel.Visible = false
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

-- ================= Menus: árvore (M), inventário (G), pescaria, passes e configurações =================
-- Botões redondos pequenos. No PC ficam numa coluna colada no lado esquerdo do minimapa (fora da linha de combate; em
-- cima do minimapa fica o cartão de navegação dele); no celular, no fim da linha de baixo.

local menuHolder = new("Frame", {
	Name = "Menu",
	AnchorPoint = Vector2.new(1, 1),
	Position = UDim2.new(1, -218, 1, -18),
	Size = if touchOnly then UDim2.fromOffset(0, MENU_SIZE) else UDim2.fromOffset(MENU_SIZE, 0),
	AutomaticSize = if touchOnly then Enum.AutomaticSize.X else Enum.AutomaticSize.Y,
	BackgroundTransparency = 1,
	LayoutOrder = 5,
	Parent = if touchOnly then actions else screen,
})
if touchOnly then
	UITheme.list(menuHolder, 6, Enum.FillDirection.Horizontal, Enum.HorizontalAlignment.Right, Enum.VerticalAlignment.Center)
else
	UITheme.list(menuHolder, 6, Enum.FillDirection.Vertical, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Bottom)
end
if touchOnly then
	divider(actions, 4)
else
	UITheme.autoScale(menuHolder, 1100, 700) -- mesma escala do minimapa
end

local menuKeyLabels = {} -- [botão] = rótulo da tecla (troca para o botão do controle)
local function menuButton(order, key, glyph)
	local button = round(new("TextButton", {
		Size = UDim2.fromOffset(MENU_SIZE, MENU_SIZE),
		BackgroundColor3 = SLOT_BG,
		BackgroundTransparency = 0.3,
		AutoButtonColor = false,
		LayoutOrder = order,
		Font = Fonts.Title,
		TextSize = 15,
		TextColor3 = WHITE,
		Text = glyph,
		Parent = menuHolder,
	}))
	local stroke = softStroke(button)
	if key then
		-- Tecla numa bolinha escura no canto de baixo, à direita
		local keyDot = round(new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(1, -4, 1, -4),
			Size = UDim2.fromOffset(15, 15),
			BackgroundColor3 = BLACK,
			BackgroundTransparency = 0.15,
			BorderSizePixel = 0,
			ZIndex = 4,
			Parent = button,
		}))
		menuKeyLabels[button] = text({
			Size = UDim2.fromScale(1, 1),
			TextXAlignment = Enum.TextXAlignment.Center,
			Font = FONT_BOLD,
			TextSize = 9,
			TextColor3 = DIM,
			Text = key,
			ZIndex = 5,
			Parent = keyDot,
		})
	end
	button.MouseEnter:Connect(function()
		setStroke(stroke, RED)
	end)
	button.MouseLeave:Connect(function()
		setStroke(stroke, SLOT_LINE)
	end)
	return button
end

local treeButton = menuButton(1, "M", "⛓")
local inventoryButton = menuButton(2, "G", "▦")
local fishingButton = menuButton(3, nil, "釣")
local passesButton = menuButton(4, nil, "★")
local settingsButton = menuButton(5, nil, "≡")
passesButton.TextColor3 = CREAM
treeButton:SetAttribute("TutorialAnchor", "TreeButton")
inventoryButton:SetAttribute("TutorialAnchor", "InventoryButton")
settingsButton:SetAttribute("TutorialAnchor", "SettingsButton")
UITheme.tooltip(treeButton, UITheme.tipText("Árvore de habilidades (M)",
	"Gaste os pontos de level em vida, força, guarda... e libere as técnicas dos estilos."))
UITheme.tooltip(inventoryButton, UITheme.tipText("Inventário (G)",
	"Itens dos chefes: vista para ganhar os bônus e mostrar no personagem."))
UITheme.tooltip(fishingButton, UITheme.tipText("Pescaria", "Abre a cesta: peixes, vara, sopas e a venda para o Daichi."))
UITheme.tooltip(passesButton, UITheme.tipText("Passes e VIP", "Benefícios permanentes, giros diários e servidor VIP."))
UITheme.tooltip(settingsButton, UITheme.tipText("Configurações", "Fast Mode, proteção de aliados e corrida automática."))

-- Bolinha com os pontos livres da árvore
local pointsDot = round(new("Frame", {
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.new(1, -3, 0, 3),
	Size = UDim2.fromOffset(16, 16),
	BackgroundColor3 = RED,
	Visible = false,
	ZIndex = 5,
	Parent = treeButton,
}))
local pointsDotText = text({
	Size = UDim2.fromScale(1, 1),
	TextXAlignment = Enum.TextXAlignment.Center,
	Font = FONT_HEAVY,
	TextSize = 10,
	ZIndex = 6,
	Parent = pointsDot,
})

-- PC: a coluna fica colada no lado esquerdo do minimapa, alinhada com o pé dele (as duas telas têm a mesma origem)
if not touchOnly then
	task.spawn(function()
		local map = playerGui:WaitForChild("Minimap", 30)
		local holder = map and map:WaitForChild("Holder", 10)
		if not holder then return end
		local function placeMenu()
			local bottom = holder.AbsolutePosition.Y + holder.AbsoluteSize.Y
			menuHolder.Position = UDim2.fromOffset(holder.AbsolutePosition.X - 10, bottom)
		end
		holder:GetPropertyChangedSignal("AbsolutePosition"):Connect(placeMenu)
		holder:GetPropertyChangedSignal("AbsoluteSize"):Connect(placeMenu)
		placeMenu()
	end)
end

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
-- Cesta de pesca: o servidor responde com o estado "Menu" e o Fishing.client abre o painel
fishingButton.MouseButton1Click:Connect(function()
	if not player:GetAttribute("MenuOpen") then
		Remotes.FishingAction:FireServer("Bag")
	end
end)
-- Loja de passes (GamepassShop.client; o menu principal também abre por lá)
passesButton.MouseButton1Click:Connect(function()
	fireToggle("GamepassShop")
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

-- Abre em cima do grupo dos menus, alinhado à direita dele (posição calculada ao abrir)
local settingsPanel = round(new("Frame", {
	AnchorPoint = Vector2.new(1, 1),
	Size = UDim2.fromOffset(270, 310),
	BackgroundColor3 = Colors.Panel,
	BackgroundTransparency = 0.08,
	BorderSizePixel = 0,
	Visible = false,
	ZIndex = 20,
	Parent = screen,
}), UDim.new(0, 12))
UITheme.stroke(settingsPanel, SLOT_LINE, 1, LINE_FADE)
UITheme.padding(settingsPanel, 14, 16)
local settingsScale = UITheme.autoScale(settingsPanel, 1100, 700)

local function placeSettings()
	local anchor = menuHolder.AbsolutePosition
	local size = menuHolder.AbsoluteSize
	local width = settingsPanel.Size.X.Offset * settingsScale.Scale
	if touchOnly then
		-- Em cima da linha de baixo, alinhado à direita do grupo
		settingsPanel.Position = UDim2.fromOffset(math.max(width + 8, anchor.X + size.X), anchor.Y - 8)
	else
		-- À esquerda da coluna, com o pé alinhado
		settingsPanel.Position = UDim2.fromOffset(math.max(width + 8, anchor.X - 8), anchor.Y + size.Y)
	end
end

text({
	Size = UDim2.new(1, 0, 0, 22),
	TextXAlignment = Enum.TextXAlignment.Left,
	Font = FONT_HEAVY,
	TextSize = 17,
	Text = "Configurações",
	ZIndex = 21,
	Parent = settingsPanel,
})

-- Linha com título, explicação e um interruptor à direita. Devolve o botão e set(ligado)
local function settingRow(y, titleText, hintText)
	text({
		Position = UDim2.fromOffset(0, y),
		Size = UDim2.new(1, -60, 0, 18),
		TextXAlignment = Enum.TextXAlignment.Left,
		Font = FONT_BOLD,
		TextSize = 15,
		Text = titleText,
		ZIndex = 21,
		Parent = settingsPanel,
	})
	text({
		Position = UDim2.fromOffset(0, y + 18),
		Size = UDim2.new(1, -60, 0, 16),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Font = FONT_MEDIUM,
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
	local switchStroke = UITheme.stroke(switch, SLOT_LINE, 1, LINE_FADE)
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
		setStroke(switchStroke, if on then RED_BRIGHT else SLOT_LINE)
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
	Font = FONT_MEDIUM,
	TextSize = 12,
	TextColor3 = DIM,
	Text = `<font color="#{RED_BRIGHT:ToHex()}">Dica:</font> para ainda mais FPS, baixe a Qualidade gráfica em Esc > Configurações.`,
	ZIndex = 21,
	Parent = settingsPanel,
})

-- Volta ao menu principal (MainMenu: personagem, clã, códigos); ele esconde o jogo até apertar JOGAR de novo
local mainMenuButton = UITheme.button({
	Position = UDim2.fromOffset(0, 206),
	Size = UDim2.new(1, 0, 0, 32),
	Font = FONT_HEAVY,
	TextSize = 15,
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
	Position = UDim2.fromOffset(0, 244),
	Size = UDim2.new(1, 0, 0, 32),
	Font = FONT_HEAVY,
	TextSize = 15,
	Text = "REFAZER TUTORIAL",
	ZIndex = 21,
	Parent = settingsPanel,
}, Colors.PanelLight)
tutorialButton.MouseButton1Click:Connect(function()
	settingsPanel.Visible = false
	Remotes.TutorialAction:FireServer("Restart")
end)

settingsButton.MouseButton1Click:Connect(function()
	placeSettings()
	settingsPanel.Visible = not settingsPanel.Visible
end)

-- ================= Level up =================

local levelUpLabel = text({
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.28),
	Size = UDim2.fromOffset(700, 80),
	TextXAlignment = Enum.TextXAlignment.Center,
	Font = Fonts.Marker,
	TextSize = 52,
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
	Font = FONT_BOLD,
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

-- Kanji do clã (na cor da raridade) + nome do jogador + o caminho, menor e apagado
local function updateName()
	local name = UITheme.escape(player.DisplayName)
	local path = PathData.FromPlayer(player)
	local info = PathData.Paths[path]
	local clan = ClanData.Get(player:GetAttribute("Clan"))
	local clanText = if clan then `<font color="#{ClanData.Color(clan.Id):ToHex()}">{clan.Kanji}</font> ` else ""
	nameLabel.Text = `{clanText}{name}  <font size="11" color="#{info.Color:ToHex()}">{UITheme.upper(info.DisplayName)}</font>`
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
	lifespanBar.Set(lifespan / maxLifespan, not wasShown)
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
	local ratio = 1
	if level.Value < StatConfig.MaxLevel then
		ratio = math.clamp(xp.Value / math.max(1, xpNeeded.Value), 0, 1)
	end
	xpBar.Set(ratio)
end

local function updateLevel()
	levelNumber.Text = `<font size="10">LV</font> {level.Value}`
	task.defer(placeName)
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
		UITheme.floatText(goldRow, `+{UITheme.formatNumber(delta)}`, CREAM, UDim2.new(1, -30, 0, 0))
	end
end)

local lastXP = xp.Value
xp.Changed:Connect(function(value)
	local delta = value - lastXP
	lastXP = value
	updateXP()
	if delta > 0 then
		UITheme.floatText(vitals, `+{delta} XP`, RED_BRIGHT, UDim2.fromOffset(70, -2))
	end
end)

local lastLevel = level.Value
level.Changed:Connect(function(value)
	updateLevel()
	if value > lastLevel then
		showLevelUp(value)
		levelBadgeScale.Scale = 1.25
		UITheme.tween(levelBadgeScale, 0.35, { Scale = 1 }, Enum.EasingStyle.Back)
	end
	lastLevel = value
	updateXP()
end)

xpNeeded.Changed:Connect(updateXP)
points.Changed:Connect(updatePoints)

updateLevel()
updateGold()
updateXP()
updatePoints()

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

-- Contorno de volta ao normal da casa (fino e apagado; nos poderes, a cor do caminho)
local function resetStroke(slot)
	slot.Stroke.Color = slot.BaseColor
	slot.Stroke.Thickness = 1
	slot.Stroke.Transparency = slot.BaseTransparency
end

-- Contorno aceso enquanto a ação está ativa (guarda levantada, soco carregando)
local function setActive(slot, active, color)
	if active then
		slot.Stroke.Color = color
		slot.Stroke.Thickness = 1.5
		slot.Stroke.Transparency = 0
		slot.WasActive = true
	elseif slot.WasActive then
		slot.WasActive = false
		resetStroke(slot)
	end
end

-- HUD a até 30 Hz: evita refazer custos, textos e cores a cada frame em monitores de alta frequência.
local hudElapsed = 0
local HUD_INTERVAL = 1 / 30
local LOW_HEALTH_TRACK = Color3.fromRGB(90, 0, 8)
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
	staminaBar.Set(stamina / math.max(1, maxStamina), true)

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

		-- Acende rápido quando a recarga termina
		if slot.WasCooling and remaining == 0 and not slot.WasActive then
			slot.Stroke.Color = WHITE
			slot.Stroke.Thickness = 2
			slot.Stroke.Transparency = 0
			UITheme.tween(slot.Stroke, 0.45, { Thickness = 1, Color = slot.BaseColor, Transparency = slot.BaseTransparency })
		end
		slot.WasCooling = remaining > 0
	end

	-- Vida baixa: o trilho da barra pulsa em vermelho escuro
	if hpBar.Ratio < 0.3 then
		local pulse = (math.sin(os.clock() * 6) + 1) / 2
		hpBar.Frame.BackgroundColor3 = TRACK:Lerp(LOW_HEALTH_TRACK, pulse)
	else
		hpBar.Frame.BackgroundColor3 = TRACK
	end
end)
