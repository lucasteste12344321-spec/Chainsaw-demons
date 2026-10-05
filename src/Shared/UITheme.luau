-- Visual compartilhado das interfaces: cores, fontes e construtores (painel, botão, barra, texto flutuante).
-- Estilo Chainsaw Man: tinta preta de mangá, vermelho sangue, laranja do Pochita e o amarelo do logo, cantos
-- duros, dentes de motosserra e sangue escorrendo (sawEdge, drips, sawBlade). Só é usado pelo cliente.
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

local UITheme = {}

UITheme.Colors = {
	-- Estilo escuro: tinta quase preta, vermelho sangue e branco (o laranja e o amarelo viraram vermelho e creme)
	Background = Color3.fromRGB(8, 8, 10), -- tinta
	Panel = Color3.fromRGB(14, 14, 17),
	PanelLight = Color3.fromRGB(32, 32, 38),
	Stroke = Color3.fromRGB(84, 18, 24), -- borda vermelho-escura
	Black = Color3.fromRGB(0, 0, 0),
	White = Color3.fromRGB(255, 255, 255),
	Text = Color3.fromRGB(242, 242, 245),
	TextDim = Color3.fromRGB(158, 158, 166),
	Accent = Color3.fromRGB(214, 22, 32), -- vermelho sangue
	AccentDark = Color3.fromRGB(96, 6, 10),
	Orange = Color3.fromRGB(255, 62, 70), -- destaque (era o laranja do Pochita)
	Gold = Color3.fromRGB(255, 226, 168), -- creme (gold, level, "!")
	Green = Color3.fromRGB(70, 210, 110),
	Blue = Color3.fromRGB(70, 150, 255),
	Demons = Color3.fromRGB(214, 22, 32),
	Humans = Color3.fromRGB(60, 130, 240),
	-- Degradês das barras (topo, base)
	Health = { Color3.fromRGB(240, 48, 56), Color3.fromRGB(120, 0, 10) },
	Stamina = { Color3.fromRGB(255, 255, 255), Color3.fromRGB(190, 190, 198) },
	XP = { Color3.fromRGB(255, 96, 104), Color3.fromRGB(140, 16, 24) },
	Lifespan = { Color3.fromRGB(160, 225, 220), Color3.fromRGB(40, 115, 125) }, -- tempo de vida (Caçador)
}

UITheme.Fonts = {
	Display = Enum.Font.PermanentMarker, -- títulos e letras de tecla: pincel atômico
	Marker = Enum.Font.PermanentMarker,
	Horror = Enum.Font.Creepster, -- só no nome do jogo
	Number = Enum.Font.GothamBlack, -- números da HUD (vida, bônus)
	Title = Enum.Font.GothamBold,
	Body = Enum.Font.GothamMedium,
	Light = Enum.Font.Gotham,
}

local Colors = UITheme.Colors
local Fonts = UITheme.Fonts

-- Cria uma instância com propriedades; Parent é aplicado por último.
-- Texto (TextLabel/TextButton/TextBox) sem Text começa vazio, e não com o "Label"/"Button" padrão do Roblox
-- (as barras finas de missão e de status não têm texto).
function UITheme.new(className, props)
	local instance = Instance.new(className)
	if instance:IsA("TextLabel") or instance:IsA("TextButton") or instance:IsA("TextBox") then
		instance.Text = ""
	end
	local parent
	for key, value in props or {} do
		if key == "Parent" then
			parent = value
		else
			instance[key] = value
		end
	end
	if parent then
		instance.Parent = parent
	end
	return instance
end

local function merge(defaults, props)
	local result = table.clone(defaults)
	for key, value in props or {} do
		result[key] = value
	end
	return result
end

function UITheme.tween(instance, time, goals, style, direction)
	local tween = TweenService:Create(
		instance,
		TweenInfo.new(time, style or Enum.EasingStyle.Quad, direction or Enum.EasingDirection.Out),
		goals
	)
	tween:Play()
	return tween
end

function UITheme.corner(parent, radius)
	return UITheme.new("UICorner", { CornerRadius = radius or UDim.new(0, 8), Parent = parent })
end

function UITheme.stroke(parent, color, thickness, transparency)
	return UITheme.new("UIStroke", {
		Color = color or Colors.Stroke,
		Thickness = thickness or 1.5,
		Transparency = transparency or 0,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Parent = parent,
	})
end

-- Degradê vertical (rotation 90 = cor 1 em cima). As cores multiplicam a cor de fundo.
function UITheme.gradient(parent, colors, rotation)
	return UITheme.new("UIGradient", {
		Color = ColorSequence.new(colors[1], colors[2]),
		Rotation = rotation or 90,
		Parent = parent,
	})
end

function UITheme.padding(parent, top, right, bottom, left)
	right = right or top
	bottom = bottom or top
	left = left or right
	return UITheme.new("UIPadding", {
		PaddingTop = UDim.new(0, top),
		PaddingRight = UDim.new(0, right),
		PaddingBottom = UDim.new(0, bottom),
		PaddingLeft = UDim.new(0, left),
		Parent = parent,
	})
end

function UITheme.list(parent, padding, direction, horizontal, vertical)
	return UITheme.new("UIListLayout", {
		Padding = UDim.new(0, padding or 0),
		FillDirection = direction or Enum.FillDirection.Vertical,
		HorizontalAlignment = horizontal or Enum.HorizontalAlignment.Left,
		VerticalAlignment = vertical or Enum.VerticalAlignment.Top,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = parent,
	})
end

function UITheme.screen(name, displayOrder, parent)
	return UITheme.new("ScreenGui", {
		Name = name,
		ResetOnSpawn = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder = displayOrder or 0,
		Parent = parent,
	})
end

function UITheme.label(props)
	return UITheme.new("TextLabel", merge({
		BackgroundTransparency = 1,
		Font = Fonts.Body,
		TextColor3 = Colors.Text,
		TextSize = 16,
		TextXAlignment = Enum.TextXAlignment.Left,
	}, props))
end

-- Painel escuro: quase preto e um pouco transparente, cantos quase retos e borda fina vermelha (escuro -> sangue ->
-- escuro). Sem filhos de enfeite (painéis costumam ter UIListLayout/UIPadding); os enfeites ficam em sawEdge/drips.
-- accent / accentDark (opcionais): cores da borda em degradê (padrão: o vermelho do tema)
function UITheme.panel(props, accent, accentDark)
	local frame = UITheme.new("Frame", merge({
		BackgroundColor3 = Colors.Panel,
		BackgroundTransparency = 0.12,
		BorderSizePixel = 0,
	}, props))
	UITheme.corner(frame, UDim.new(0, 4))
	local stroke = UITheme.stroke(frame, Colors.White, 1.5, 0)
	UITheme.new("UIGradient", {
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, accentDark or Colors.AccentDark),
			ColorSequenceKeypoint.new(0.5, accent or Colors.Accent),
			ColorSequenceKeypoint.new(1, accentDark or Colors.AccentDark),
		}),
		Rotation = 35,
		Parent = stroke,
	})
	UITheme.gradient(frame, { Color3.fromRGB(255, 255, 255), Color3.fromRGB(190, 190, 196) })
	return frame
end

-- Pílula da HUD (como os bônus da foto de referência): fundo preto translúcido, ícone branco e valor em negrito.
-- Devolve (frame, iconLabel, valueLabel); o tamanho acompanha o texto.
function UITheme.pill(props, icon, value)
	local frame = UITheme.new("Frame", merge({
		Size = UDim2.fromOffset(0, 24),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundColor3 = Colors.Black,
		BackgroundTransparency = 0.45,
		BorderSizePixel = 0,
	}, props))
	UITheme.corner(frame, UDim.new(0.5, 0))
	UITheme.padding(frame, 0, 10, 0, 8)
	UITheme.list(frame, 5, Enum.FillDirection.Horizontal, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Center)
	local iconLabel = UITheme.label({
		Size = UDim2.fromOffset(16, 20),
		TextXAlignment = Enum.TextXAlignment.Center,
		Font = Fonts.Title,
		TextSize = 14,
		Text = icon or "",
		LayoutOrder = 1,
		Parent = frame,
	})
	local valueLabel = UITheme.label({
		Size = UDim2.fromOffset(0, 20),
		AutomaticSize = Enum.AutomaticSize.X,
		Font = Fonts.Number,
		TextSize = 13,
		TextStrokeTransparency = 0.6,
		Text = value or "",
		LayoutOrder = 2,
		Parent = frame,
	})
	return frame, iconLabel, valueLabel
end

-- Letra de tecla no estilo da foto (pincel atômico branco com contorno), para pôr em cima de um slot
function UITheme.keyLabel(props)
	return UITheme.label(merge({
		Size = UDim2.fromOffset(24, 20),
		TextXAlignment = Enum.TextXAlignment.Center,
		Font = Fonts.Marker,
		TextSize = 17,
		TextStrokeTransparency = 0.25,
	}, props))
end

-- Botão com degradê e animação de hover/clique (no hover a borda acende na cor de destaque e o botão treme).
-- accent (opcional): cor da borda no hover (padrão: o vermelho do tema)
function UITheme.button(props, color, accent)
	local button = UITheme.new("TextButton", merge({
		AutoButtonColor = false,
		BackgroundColor3 = color or Colors.Accent,
		BorderSizePixel = 0,
		Font = Fonts.Title,
		TextColor3 = Colors.Text,
		TextSize = 16,
	}, props))
	UITheme.corner(button, UDim.new(0, 3))
	local stroke = UITheme.stroke(button, Colors.Black, 2, 0.1)
	UITheme.gradient(button, { Color3.fromRGB(255, 255, 255), Color3.fromRGB(160, 150, 150) })

	local scale = UITheme.new("UIScale", { Parent = button })
	local baseRotation = button.Rotation
	button.MouseEnter:Connect(function()
		UITheme.tween(scale, 0.12, { Scale = 1.05 })
		stroke.Color = accent or Colors.Accent
		-- Tremida curta, como uma motosserra ligando
		button.Rotation = baseRotation + 1.5
		UITheme.tween(button, 0.18, { Rotation = baseRotation }, Enum.EasingStyle.Elastic)
	end)
	button.MouseLeave:Connect(function()
		UITheme.tween(scale, 0.12, { Scale = 1 })
		stroke.Color = Colors.Black
	end)
	button.MouseButton1Down:Connect(function()
		UITheme.tween(scale, 0.08, { Scale = 0.94 })
	end)
	button.MouseButton1Up:Connect(function()
		UITheme.tween(scale, 0.1, { Scale = 1.05 })
	end)
	return button
end

-- Barra com preenchimento em degradê, brilho no topo e um "rastro" claro que acompanha a perda com atraso.
-- Devolve { Frame, Fill, Label, Set(ratio, text?, instant?) }
function UITheme.bar(props, colors, textSize)
	local frame = UITheme.new("Frame", merge({
		BackgroundColor3 = Color3.fromRGB(10, 6, 7),
		BackgroundTransparency = 0.15,
		BorderSizePixel = 0,
		ClipsDescendants = true,
	}, props))
	UITheme.corner(frame, UDim.new(0, 3))
	UITheme.stroke(frame, Colors.Black, 2.5, 0)

	-- Rastro da perda: claro, some com atraso
	local trail = UITheme.new("Frame", {
		Name = "Trail",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.fromRGB(255, 235, 235),
		BackgroundTransparency = 0.35,
		BorderSizePixel = 0,
		ZIndex = 1,
		Parent = frame,
	})
	UITheme.corner(trail, UDim.new(0, 3))

	local fill = UITheme.new("Frame", {
		Name = "Fill",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Colors.White,
		BorderSizePixel = 0,
		ZIndex = 2,
		Parent = frame,
	})
	UITheme.corner(fill, UDim.new(0, 3))
	UITheme.gradient(fill, colors)

	local shine = UITheme.new("Frame", {
		Size = UDim2.new(1, 0, 0.4, 0),
		BackgroundColor3 = Colors.White,
		BackgroundTransparency = 0.82,
		BorderSizePixel = 0,
		Parent = fill,
	})
	UITheme.corner(shine, UDim.new(0, 3))

	local label = UITheme.label({
		Size = UDim2.fromScale(1, 1),
		TextXAlignment = Enum.TextXAlignment.Center,
		Font = Fonts.Title,
		TextSize = textSize or 14,
		TextStrokeTransparency = 0.35,
		ZIndex = 3,
		Parent = frame,
	})

	local api = { Frame = frame, Fill = fill, Label = label, Ratio = 1 }
	local trailTween

	function api.Set(ratio, text, instant)
		if text then
			label.Text = text
		end
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

		UITheme.tween(fill, 0.18, { Size = target })
		if ratio < previous then
			trailTween = TweenService:Create(
				trail,
				TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0, false, 0.35),
				{ Size = target }
			)
			trailTween:Play()
		else
			trail.Size = target
		end
	end

	return api
end

-- Texto que sobe e some (ex.: "+25 XP")
function UITheme.floatText(parent, text, color, position)
	local label = UITheme.label({
		AnchorPoint = Vector2.new(0.5, 1),
		Position = position or UDim2.fromScale(0.5, 0),
		Size = UDim2.fromOffset(160, 24),
		TextXAlignment = Enum.TextXAlignment.Center,
		Font = Fonts.Display,
		TextSize = 20,
		TextColor3 = color or Colors.Gold,
		TextStrokeTransparency = 0.2,
		Text = text,
		ZIndex = 10,
		Parent = parent,
	})
	local goal = label.Position - UDim2.fromOffset(0, 36)
	UITheme.tween(label, 1.1, { Position = goal, TextTransparency = 1, TextStrokeTransparency = 1 })
	task.delay(1.15, function()
		label:Destroy()
	end)
	return label
end

-- Escala a interface para caber em telas menores que o tamanho de projeto
function UITheme.autoScale(guiObject, designWidth, designHeight)
	local scale = UITheme.new("UIScale", { Parent = guiObject })
	local function update()
		local camera = workspace.CurrentCamera
		if not camera then return end
		local viewport = camera.ViewportSize
		scale.Scale = math.clamp(math.min((viewport.X - 24) / designWidth, (viewport.Y - 24) / designHeight), 0.5, 1)
	end
	update()
	local camera = workspace.CurrentCamera
	if camera then
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(update)
	end
	return scale
end

-- ================= Enfeites Chainsaw Man =================
-- Só com Frames e texto (sem imagens). O pai não pode ter UIListLayout (o enfeite entraria na lista).

-- Fileira de dentes de motosserra na borda do pai: edge "Top" (dentes para baixo) ou "Bottom" (para cima)
function UITheme.sawEdge(parent, edge, color, size, transparency)
	size = size or 14
	local top = edge ~= "Bottom"
	local holder = UITheme.new("Frame", {
		Name = "SawEdge",
		AnchorPoint = Vector2.new(0, if top then 0 else 1),
		Position = UDim2.fromScale(0, if top then 0 else 1),
		Size = UDim2.new(1, 0, 0, size),
		BackgroundTransparency = 1,
		ClipsDescendants = true,
		Parent = parent,
	})
	UITheme.label({
		Size = UDim2.fromScale(1, 1),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = if top then Enum.TextYAlignment.Top else Enum.TextYAlignment.Bottom,
		Font = Enum.Font.GothamBlack,
		TextSize = math.floor(size * 1.3),
		TextColor3 = color or Colors.Accent,
		TextTransparency = transparency or 0,
		Text = string.rep(if top then "▼" else "▲", 320),
		Parent = holder,
	})
	return holder
end

-- Sangue escorrendo da borda de baixo do pai. opts: Color, Count, MaxLength, Seed, From, To (faixa em X, 0 a 1)
function UITheme.drips(parent, opts)
	opts = opts or {}
	local rng = Random.new(opts.Seed or 7)
	local count = opts.Count or 6
	local maxLength = opts.MaxLength or 40
	local from, to = opts.From or 0.1, opts.To or 0.9
	local color = opts.Color or Colors.Accent
	local holder = UITheme.new("Frame", {
		Name = "Drips",
		Position = UDim2.new(0, 0, 1, -3),
		Size = UDim2.new(1, 0, 0, maxLength + 8),
		BackgroundTransparency = 1,
		Parent = parent,
	})
	for i = 1, count do
		local width = rng:NextInteger(3, 7)
		local length = rng:NextInteger(math.floor(maxLength * 0.3), maxLength)
		local x = from + (to - from) * ((i - 0.5) / count) + rng:NextNumber(-0.03, 0.03)
		local drip = UITheme.new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.fromScale(x, 0),
			Size = UDim2.fromOffset(width, 0),
			BackgroundColor3 = color,
			BorderSizePixel = 0,
			Parent = holder,
		})
		UITheme.corner(drip, UDim.new(0.5, 0))
		-- Gota mais gorda na ponta
		local bulb = UITheme.new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 1),
			Size = UDim2.fromOffset(width + 3, width + 3),
			BackgroundColor3 = color,
			BorderSizePixel = 0,
			Parent = drip,
		})
		UITheme.corner(bulb, UDim.new(0.5, 0))
		-- Escorre devagar
		UITheme.tween(drip, rng:NextNumber(1.2, 2.8), { Size = UDim2.fromOffset(width, length) }, Enum.EasingStyle.Sine)
	end
	return holder
end

-- Lâmina de motosserra girando (anel de dentes). Devolve (frame, setSpeed(graus por segundo)).
-- O frame vem centrado no pai; quem chama pode mudar Position/ZIndex.
function UITheme.sawBlade(parent, diameter, color, teeth)
	local holder = UITheme.new("Frame", {
		Name = "SawBlade",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(diameter, diameter),
		BackgroundTransparency = 1,
		Parent = parent,
	})
	local count = teeth or 14
	local tooth = diameter * 0.16
	local radius = diameter / 2 - tooth * 0.35
	for i = 1, count do
		local angle = (i / count) * math.pi * 2
		UITheme.new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, math.cos(angle) * radius, 0.5, math.sin(angle) * radius),
			Size = UDim2.fromOffset(tooth, tooth),
			Rotation = math.deg(angle) + 45,
			BackgroundColor3 = color or Colors.Gold,
			BorderSizePixel = 0,
			Parent = holder,
		})
	end
	local speed = 25
	local connection
	connection = RunService.RenderStepped:Connect(function(dt)
		if not holder.Parent then
			connection:Disconnect()
			return
		end
		holder.Rotation = (holder.Rotation + speed * dt) % 360
	end)
	return holder, function(value)
		speed = value
	end
end

-- 12345 -> "12.345"
function UITheme.formatNumber(n)
	local negative = n < 0
	local digits = tostring(math.floor(math.abs(n)))
	local formatted = digits:reverse():gsub("(%d%d%d)", "%1."):reverse()
	if formatted:sub(1, 1) == "." then
		formatted = formatted:sub(2)
	end
	return if negative then "-" .. formatted else formatted
end

-- ================= Fase 4: textos e helpers dos caminhos =================

-- Ícone de cada caminho do PathData ("None", "Hunter", "Fiend"): kanji brancos, como os da HUD e da árvore
UITheme.PathIcons = {
	None = "人",
	Hunter = "狩",
	Fiend = "魔",
}

-- Ícone de uma habilidade, contrato ou tipo de Infernal do PathData: o kanji (Glyph) ou, sem ele, o emoji (Icon)
function UITheme.glyphOf(entry)
	return entry and (entry.Glyph or entry.Icon) or "?"
end

-- Nome curto do tipo de habilidade (campo Kind do PathData)
UITheme.SkillKinds = {
	Cone = "cone à frente",
	Area = "área à frente",
	Dash = "investida",
	Projectile = "projétil",
	Mark = "marca",
	Buff = "em si mesmo",
}

-- string.upper não conhece letras acentuadas em UTF-8 ("Caçador" viraria "CAçADOR")
local UPPER_ACCENTS = {
	["á"] = "Á", ["à"] = "À", ["â"] = "Â", ["ã"] = "Ã",
	["é"] = "É", ["ê"] = "Ê", ["í"] = "Í",
	["ó"] = "Ó", ["ô"] = "Ô", ["õ"] = "Õ",
	["ú"] = "Ú", ["ü"] = "Ü", ["ç"] = "Ç",
}
function UITheme.upper(text)
	local result = string.upper(tostring(text))
	for lower, upper in UPPER_ACCENTS do
		result = string.gsub(result, lower, upper)
	end
	return result
end

-- Escapa texto livre (ex.: nome do jogador) para usar dentro de RichText
function UITheme.escape(text)
	local result = string.gsub(tostring(text), "&", "&amp;")
	result = string.gsub(result, "<", "&lt;")
	result = string.gsub(result, ">", "&gt;")
	return result
end

-- 0.1 -> "10%"
function UITheme.formatPercent(fraction)
	return `{math.floor(fraction * 100 + 0.5)}%`
end

-- 10 -> "10s", 0.5 -> "0,5s"
function UITheme.formatSeconds(seconds)
	if seconds == math.floor(seconds) then
		return `{seconds}s`
	end
	local text = string.gsub(string.format("%.1f", seconds), "%.", ",")
	return text .. "s"
end

-- Etiqueta arredondada com texto colorido (recompensas, custos, passivos)
function UITheme.chip(parent, text, color, order, textSize)
	local chip = UITheme.new("Frame", {
		Size = UDim2.fromOffset(0, 24),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundColor3 = Colors.Black,
		BackgroundTransparency = 0.4,
		LayoutOrder = order or 0,
		Parent = parent,
	})
	UITheme.corner(chip, UDim.new(0.5, 0))
	UITheme.stroke(chip, color, 1, 0.3)
	UITheme.padding(chip, 0, 10)
	UITheme.label({
		Size = UDim2.fromScale(0, 1),
		AutomaticSize = Enum.AutomaticSize.X,
		Font = Fonts.Title,
		TextSize = textSize or 13,
		TextColor3 = color,
		Text = text,
		Parent = chip,
	})
	return chip
end

-- Resumo de uma habilidade do PathData: "70 de dano  ·  atordoa 1s  ·  recarga 10s"
function UITheme.skillStats(skill)
	local parts = {}
	if type(skill.Damage) == "number" and skill.Damage > 0 then
		table.insert(parts, `{skill.Damage} de dano`)
	end
	if skill.Kind == "Mark" and skill.Delay then
		table.insert(parts, `explode em {UITheme.formatSeconds(skill.Delay)}`)
	end
	if skill.Kind == "Buff" and skill.Duration then
		table.insert(parts, `dura {UITheme.formatSeconds(skill.Duration)}`)
	end
	if type(skill.Stun) == "number" and skill.Stun > 0 then
		table.insert(parts, `atordoa {UITheme.formatSeconds(skill.Stun)}`)
	end
	if skill.Cooldown then
		table.insert(parts, `recarga {UITheme.formatSeconds(skill.Cooldown)}`)
	end
	return table.concat(parts, "  ·  ")
end

-- Custo de uso de uma habilidade: texto e cor
function UITheme.skillCost(skill)
	if skill.LifespanCost then
		return `{skill.LifespanCost} de tempo de vida`, Colors.Lifespan[1]
	elseif skill.HealthCost then
		return `{UITheme.formatPercent(skill.HealthCost)} da vida máxima`, Colors.Health[1]
	end
	return "Sem custo", Colors.TextDim
end

-- Versão curta do custo, para o slot da HUD ("⏳8", "🩸5%")
function UITheme.skillCostShort(skill)
	if skill.LifespanCost then
		return `⏳{skill.LifespanCost}`, Colors.Lifespan[1]
	elseif skill.HealthCost then
		return `🩸{UITheme.formatPercent(skill.HealthCost)}`, Colors.Health[1]
	end
	return "", Colors.TextDim
end

-- Passivo do PathData ({ DodgeChance?, LifeSteal?, SpeedBonus? }) em texto, ou nil se não tiver nada
function UITheme.passiveText(passive)
	if type(passive) ~= "table" then return nil end
	local parts = {}
	if type(passive.DodgeChance) == "number" and passive.DodgeChance > 0 then
		table.insert(parts, `{UITheme.formatPercent(passive.DodgeChance)} de chance de esquivar`)
	end
	if type(passive.LifeSteal) == "number" and passive.LifeSteal > 0 then
		table.insert(parts, `{UITheme.formatPercent(passive.LifeSteal)} do dano causado vira vida`)
	end
	if type(passive.SpeedBonus) == "number" and passive.SpeedBonus > 0 then
		table.insert(parts, `+{passive.SpeedBonus} de velocidade`)
	end
	if #parts == 0 then return nil end
	return table.concat(parts, "  ·  ")
end

-- ================= Balão de dica =================
-- Balão escuro que segue o mouse enquanto ele está em cima de um elemento (kanji da HUD, itens, casas...).
-- content: texto (aceita RichText, "\n" quebra a linha) ou função que devolve o texto na hora de mostrar.
-- Um balão só por jogador, numa ScreenGui própria acima de todas. No celular não aparece (não tem mouse em cima).
local tooltip -- { Gui, Frame, Label, Owner }

local function ensureTooltip()
	if tooltip and tooltip.Gui.Parent then return tooltip end
	local Players = game:GetService("Players")
	local player = Players.LocalPlayer
	local playerGui = player and player:FindFirstChildOfClass("PlayerGui")
	if not playerGui then return nil end
	local gui = UITheme.screen("Tooltip", 100, playerGui)
	gui.IgnoreGuiInset = true
	local frame = UITheme.new("Frame", {
		Size = UDim2.fromOffset(0, 0),
		AutomaticSize = Enum.AutomaticSize.XY,
		BackgroundColor3 = Colors.Background,
		BackgroundTransparency = 0.06,
		BorderSizePixel = 0,
		Visible = false,
		ZIndex = 10,
		Parent = gui,
	})
	UITheme.corner(frame, UDim.new(0, 5))
	UITheme.stroke(frame, Colors.Accent, 1, 0.1)
	UITheme.padding(frame, 6, 10, 7, 10)
	local label = UITheme.label({
		Size = UDim2.fromOffset(0, 0),
		AutomaticSize = Enum.AutomaticSize.XY,
		RichText = true,
		TextWrapped = true,
		Font = Fonts.Body,
		TextSize = 13,
		ZIndex = 11,
		Parent = frame,
	})
	UITheme.new("UISizeConstraint", { MaxSize = Vector2.new(280, math.huge), Parent = label })
	tooltip = { Gui = gui, Frame = frame, Label = label, Owner = nil }

	-- Segue o mouse e some junto com o dono (tela fechada, elemento escondido ou apagado)
	local UserInputService = game:GetService("UserInputService")
	RunService.RenderStepped:Connect(function()
		local owner = tooltip.Owner
		if not owner then return end
		local screen = owner:FindFirstAncestorWhichIsA("LayerCollector")
		if not owner.Parent or not owner.Visible or (screen and not screen.Enabled) then
			tooltip.Owner = nil
			frame.Visible = false
			return
		end
		local mouse = UserInputService:GetMouseLocation()
		local viewport = workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize or Vector2.new(1920, 1080)
		local size = frame.AbsoluteSize
		local x = math.min(mouse.X + 16, viewport.X - size.X - 6)
		local y = mouse.Y + 18
		if y + size.Y > viewport.Y - 6 then
			y = mouse.Y - size.Y - 10 -- perto do pé da tela: o balão fica em cima do mouse
		end
		frame.Position = UDim2.fromOffset(x, y)
	end)
	return tooltip
end

function UITheme.tooltip(guiObject, content)
	guiObject.MouseEnter:Connect(function()
		local tip = ensureTooltip()
		if not tip then return end
		local value = if type(content) == "function" then content() else content
		if type(value) ~= "string" or value == "" then return end
		tip.Owner = guiObject
		tip.Label.Text = value
		tip.Frame.Visible = true
	end)
	guiObject.MouseLeave:Connect(function()
		if tooltip and tooltip.Owner == guiObject then
			tooltip.Owner = nil
			tooltip.Frame.Visible = false
		end
	end)
end

-- Título do balão (negrito, branco) + texto: UITheme.tipText("Força", "+53 de dano por golpe")
function UITheme.tipText(title, body)
	local escapedTitle = UITheme.escape(title)
	if not body or body == "" then
		return `<b>{escapedTitle}</b>`
	end
	return `<b>{escapedTitle}</b>\n<font color="#{Colors.TextDim:ToHex()}">{body}</font>`
end

return UITheme
