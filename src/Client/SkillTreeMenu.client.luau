-- Árvore de habilidades (tecla M ou botão 📜 da HUD). Visual de mangá em preto e branco: o jogo fica cinza e
-- embaçado atrás, nós escuros com kanji branco ligados por correntes de metal, cadeado nos travados e um único
-- toque de vermelho no brilho dos nós que dá para pegar. Arrastar move; roda do mouse / barra / pinça dão zoom.
-- Passar o mouse mostra o nome do nó; clicar mostra o painel de baixo (efeitos, custo, maestria) com DESBLOQUEAR.
-- Menu lateral: Árvore, Caminho (abre o StatusMenu), Inventário (abre a tela do inventário, Inventory.client) e Fechar.
-- Dados em ReplicatedStorage.SkillTreeData; o servidor valida (Remotes.SkillTreeUnlock) e reseta (Remotes.StatusReset).
-- Lê do player: atributo SkillTree (JSON dos nós), Progress.StatusPoints (pontos livres) e a pasta Mastery.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")

local Remotes = require(ReplicatedStorage:WaitForChild("Remotes"))
local UITheme = require(ReplicatedStorage:WaitForChild("UITheme"))
local SkillTreeData = require(ReplicatedStorage:WaitForChild("SkillTreeData"))
local StatConfig = require(ReplicatedStorage:WaitForChild("StatConfig"))
local CombatStyles = require(ReplicatedStorage:WaitForChild("CombatStyles"))

local Fonts = UITheme.Fonts

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local leaderstats = player:WaitForChild("leaderstats", math.huge)
local progress = player:WaitForChild("Progress", math.huge)
local level = leaderstats:WaitForChild("Level")
local gold = leaderstats:WaitForChild("Gold")
local points = progress:WaitForChild("StatusPoints")
local masteryFolder = player:WaitForChild("Mastery", math.huge)

-- Paleta de mangá: tinta, prata, aço e um vermelho só para o que dá para pegar
local INK = Color3.fromRGB(12, 12, 14)
local PANEL = Color3.fromRGB(26, 26, 30)
local SILVER = Color3.fromRGB(234, 234, 238)
local STEEL = Color3.fromRGB(150, 150, 158)
local DARK_STEEL = Color3.fromRGB(62, 62, 68)
local GOLD_PALE = Color3.fromRGB(236, 214, 150)
local BLOOD = Color3.fromRGB(214, 22, 32)
local WHITE = Color3.new(1, 1, 1)
local BLACK = Color3.new(0, 0, 0)

local NODE_SIZE = 54
local ROOT_SIZE = 80
local LINK_SPACING = 10
local ZOOM_MIN, ZOOM_MAX, ZOOM_DEFAULT = 0.35, 1.6, 0.6
-- Telas escondidas enquanto a árvore está aberta (senão aparecem por trás do fundo)
local HIDE_WHILE_OPEN = { "HUD", "QuestTracker", "BossBar" }

local function new(className, props)
	return UITheme.new(className, props)
end

local function round(frame, radius)
	UITheme.corner(frame, radius or UDim.new(1, 0))
	return frame
end

local function outline(frame, color, thickness, transparency)
	return new("UIStroke", {
		Color = color,
		Thickness = thickness or 1,
		Transparency = transparency or 0,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Parent = frame,
	})
end

local function text(props)
	props.BackgroundTransparency = 1
	props.TextColor3 = props.TextColor3 or SILVER
	props.Font = props.Font or Fonts.Title
	return new("TextLabel", props)
end

-- ================= Tela =================

local screen = UITheme.screen("SkillTree", 5, playerGui)
screen.IgnoreGuiInset = true
screen.Enabled = false
local toggleEvent = new("BindableEvent", { Name = "Toggle", Parent = screen })

local backdrop = new("Frame", {
	Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = BLACK,
	BackgroundTransparency = 0.45,
	BorderSizePixel = 0,
	Parent = screen,
})
-- Vinheta: as bordas escurecem
for _, side in { { 0, 0, 1, 0.3, 90 }, { 0, 0.7, 1, 0.3, -90 }, { 0, 0, 0.25, 1, 0 }, { 0.75, 0, 0.25, 1, 180 } } do
	local edge = new("Frame", {
		Position = UDim2.fromScale(side[1], side[2]),
		Size = UDim2.fromScale(side[3], side[4]),
		BackgroundColor3 = BLACK,
		BorderSizePixel = 0,
		Parent = backdrop,
	})
	new("UIGradient", {
		Rotation = side[5],
		Transparency = NumberSequence.new(0.25, 1),
		Parent = edge,
	})
end

-- ----- Área da árvore (arrastar / zoom) -----
local viewport = new("Frame", {
	Size = UDim2.fromScale(1, 1),
	BackgroundTransparency = 1,
	ClipsDescendants = true,
	Active = true,
	Parent = screen,
})
local canvas = new("Frame", {
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromOffset(0, 0),
	BackgroundTransparency = 1,
	Parent = viewport,
})
local canvasScale = new("UIScale", { Scale = ZOOM_DEFAULT, Parent = canvas })
local markLayer = new("Frame", { Size = UDim2.fromOffset(0, 0), BackgroundTransparency = 1, ZIndex = 1, Parent = canvas })
local edgeLayer = new("Frame", { Size = UDim2.fromOffset(0, 0), BackgroundTransparency = 1, ZIndex = 2, Parent = canvas })
local nodeLayer = new("Frame", { Size = UDim2.fromOffset(0, 0), BackgroundTransparency = 1, ZIndex = 3, Parent = canvas })

-- ----- Etiqueta do nó (branca, como um recorte de papel) -----
local tooltip = new("Frame", {
	AnchorPoint = Vector2.new(0.5, 1),
	Size = UDim2.fromOffset(0, 24),
	AutomaticSize = Enum.AutomaticSize.X,
	BackgroundColor3 = Color3.fromRGB(246, 246, 246),
	BorderSizePixel = 0,
	Visible = false,
	ZIndex = 50,
	Parent = screen,
})
round(tooltip, UDim.new(0, 3))
new("UIPadding", { PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10), Parent = tooltip })
local tooltipText = text({
	Size = UDim2.fromOffset(0, 24),
	AutomaticSize = Enum.AutomaticSize.X,
	Font = Fonts.Title,
	TextSize = 13,
	TextColor3 = BLACK,
	ZIndex = 51,
	Parent = tooltip,
})

-- ----- Menu lateral -----
local nav = new("Frame", {
	AnchorPoint = Vector2.new(0, 0.5),
	Position = UDim2.new(0, 38, 0.42, 0),
	Size = UDim2.fromOffset(230, 0),
	AutomaticSize = Enum.AutomaticSize.Y,
	BackgroundTransparency = 1,
	Parent = screen,
})
UITheme.list(nav, 4)
UITheme.autoScale(nav, 1100, 700)

local NAV_ITEMS = {
	{ Id = "Tree", Text = "Árvore de habilidades", Icon = "⛓" },
	{ Id = "Path", Text = "Caminho", Icon = "◎" },
	{ Id = "Inventory", Text = "Inventário", Icon = "▦" },
	{ Id = "Close", Text = "Fechar", Icon = "×" },
}
local navButtons = {}
for index, item in NAV_ITEMS do
	local button = new("TextButton", {
		Size = UDim2.fromOffset(230, 30),
		BackgroundColor3 = WHITE,
		BackgroundTransparency = 1,
		AutoButtonColor = false,
		LayoutOrder = index,
		Parent = nav,
	})
	round(button, UDim.new(0, 4))
	local icon = text({
		Position = UDim2.fromOffset(8, 0),
		Size = UDim2.fromOffset(20, 30),
		TextXAlignment = Enum.TextXAlignment.Center,
		Font = Fonts.Title,
		TextSize = 15,
		TextColor3 = STEEL,
		Text = item.Icon,
		Parent = button,
	})
	local label = text({
		Position = UDim2.fromOffset(34, 0),
		Size = UDim2.new(1, -34, 1, 0),
		TextXAlignment = Enum.TextXAlignment.Left,
		Font = Fonts.Body,
		TextSize = 14,
		TextColor3 = STEEL,
		Text = item.Text,
		Parent = button,
	})
	navButtons[item.Id] = { Button = button, Icon = icon, Label = label }
end

-- ----- Maestria (canto de cima, à direita) -----
local masteryPanel = new("Frame", {
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, -40, 0, 34),
	Size = UDim2.fromOffset(210, 0),
	AutomaticSize = Enum.AutomaticSize.Y,
	BackgroundTransparency = 1,
	Parent = screen,
})
UITheme.list(masteryPanel, 8)
UITheme.autoScale(masteryPanel, 1100, 700)
text({
	Size = UDim2.new(1, 0, 0, 14),
	TextXAlignment = Enum.TextXAlignment.Right,
	Font = Fonts.Title,
	TextSize = 11,
	TextColor3 = STEEL,
	Text = "MAESTRIA",
	LayoutOrder = 0,
	Parent = masteryPanel,
})
local masteryRows = {} -- [estilo] = { Name, Level, Fill, XP }
for style in CombatStyles.Styles do
	local row = new("Frame", {
		Size = UDim2.new(1, 0, 0, 34),
		BackgroundTransparency = 1,
		LayoutOrder = 1,
		Parent = masteryPanel,
	})
	local name = text({
		Size = UDim2.new(1, 0, 0, 16),
		TextXAlignment = Enum.TextXAlignment.Left,
		Font = Fonts.Title,
		TextSize = 14,
		Text = style,
		Parent = row,
	})
	local lvl = text({
		Size = UDim2.new(1, 0, 0, 16),
		TextXAlignment = Enum.TextXAlignment.Right,
		Font = Fonts.Title,
		TextSize = 13,
		Text = "",
		Parent = row,
	})
	local track = new("Frame", {
		Position = UDim2.fromOffset(0, 21),
		Size = UDim2.new(1, 0, 0, 3),
		BackgroundColor3 = DARK_STEEL,
		BorderSizePixel = 0,
		Parent = row,
	})
	local fill = new("Frame", {
		Size = UDim2.fromScale(0, 1),
		BackgroundColor3 = SILVER,
		BorderSizePixel = 0,
		Parent = track,
	})
	local xpText = text({
		Position = UDim2.fromOffset(0, 25),
		Size = UDim2.new(1, 0, 0, 10),
		TextXAlignment = Enum.TextXAlignment.Right,
		Font = Fonts.Light,
		TextSize = 10,
		TextColor3 = STEEL,
		Text = "",
		Parent = row,
	})
	masteryRows[style] = { Level = lvl, Fill = fill, XP = xpText }
end

-- ----- Barra de baixo: zoom, pontos e o nó escolhido -----
local bottom = new("Frame", {
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, -26),
	Size = UDim2.fromOffset(660, 110),
	BackgroundTransparency = 1,
	Parent = screen,
})
UITheme.autoScale(bottom, 800, 700)

-- Zoom: porcentagem, trilho fino e lupa
local zoomTrack = new("Frame", {
	AnchorPoint = Vector2.new(0, 1),
	Position = UDim2.new(0, 0, 1, -14),
	Size = UDim2.fromOffset(110, 3),
	BackgroundColor3 = DARK_STEEL,
	BorderSizePixel = 0,
	Active = true,
	Parent = bottom,
})
local zoomFill = new("Frame", {
	Size = UDim2.fromScale(0.2, 1),
	BackgroundColor3 = SILVER,
	BorderSizePixel = 0,
	Parent = zoomTrack,
})
local zoomKnob = round(new("TextButton", {
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.2, 0.5),
	Size = UDim2.fromOffset(10, 10),
	BackgroundColor3 = SILVER,
	AutoButtonColor = false,
	Parent = zoomTrack,
}))
local zoomLabel = text({
	AnchorPoint = Vector2.new(0, 1),
	Position = UDim2.new(0, 0, 0, -6),
	Size = UDim2.fromOffset(60, 14),
	TextXAlignment = Enum.TextXAlignment.Left,
	Font = Fonts.Title,
	TextSize = 12,
	Text = "60%",
	Parent = zoomTrack,
})
local lens = round(new("Frame", {
	AnchorPoint = Vector2.new(0, 0.5),
	Position = UDim2.new(1, 8, 0.5, -2),
	Size = UDim2.fromOffset(9, 9),
	BackgroundTransparency = 1,
	Parent = zoomTrack,
}))
outline(lens, SILVER, 1.6)
new("Frame", {
	Position = UDim2.fromOffset(7, 8),
	Size = UDim2.fromOffset(5, 2),
	Rotation = 45,
	BackgroundColor3 = SILVER,
	BorderSizePixel = 0,
	Parent = lens,
})

-- Pontos: losango duplo
local pointsHolder = new("Frame", {
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0, 215, 1, 0),
	Size = UDim2.fromOffset(150, 96),
	BackgroundTransparency = 1,
	Parent = bottom,
})
local diamond = new("Frame", {
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.new(0.5, 0, 0, 38),
	Size = UDim2.fromOffset(48, 48),
	Rotation = 45,
	BackgroundColor3 = PANEL,
	BackgroundTransparency = 0.1,
	BorderSizePixel = 0,
	Parent = pointsHolder,
})
local diamondStroke = outline(diamond, SILVER, 2)
local diamondInner = new("Frame", {
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromOffset(36, 36),
	BackgroundTransparency = 1,
	Parent = diamond,
})
outline(diamondInner, STEEL, 1, 0.3)
local pointsLabel = text({
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.new(0.5, 0, 0, 38),
	Size = UDim2.fromOffset(48, 30),
	TextXAlignment = Enum.TextXAlignment.Center,
	Font = Fonts.Title,
	TextSize = 20,
	Text = "0",
	Parent = pointsHolder,
})
text({
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 72),
	Size = UDim2.fromOffset(150, 14),
	TextXAlignment = Enum.TextXAlignment.Center,
	Font = Fonts.Title,
	TextSize = 11,
	Text = "※ PONTOS DE HABILIDADE",
	Parent = pointsHolder,
})

-- Painel do nó escolhido (cresce para cima)
local info = new("Frame", {
	AnchorPoint = Vector2.new(0, 1),
	Position = UDim2.new(0, 300, 1, 0),
	Size = UDim2.fromOffset(330, 0),
	AutomaticSize = Enum.AutomaticSize.Y,
	BackgroundColor3 = PANEL,
	BackgroundTransparency = 0.12,
	BorderSizePixel = 0,
	Active = true,
	Parent = bottom,
})
round(info, UDim.new(0, 4))
outline(info, DARK_STEEL, 1, 0.2)
new("UIPadding", {
	PaddingTop = UDim.new(0, 10),
	PaddingBottom = UDim.new(0, 12),
	PaddingLeft = UDim.new(0, 14),
	PaddingRight = UDim.new(0, 14),
	Parent = info,
})
UITheme.list(info, 4)
local infoTitle = text({
	Size = UDim2.new(1, 0, 0, 22),
	TextXAlignment = Enum.TextXAlignment.Left,
	Font = Fonts.Title,
	TextSize = 18,
	Text = "",
	LayoutOrder = 1,
	Parent = info,
})
local infoBranch = text({
	Size = UDim2.new(1, 0, 0, 14),
	TextXAlignment = Enum.TextXAlignment.Left,
	Font = Fonts.Light,
	TextSize = 12,
	TextColor3 = STEEL,
	Text = "",
	LayoutOrder = 2,
	Parent = info,
})
local infoBody = text({
	Size = UDim2.new(1, 0, 0, 0),
	AutomaticSize = Enum.AutomaticSize.Y,
	TextXAlignment = Enum.TextXAlignment.Left,
	TextYAlignment = Enum.TextYAlignment.Top,
	TextWrapped = true,
	RichText = true,
	Font = Fonts.Body,
	TextSize = 13,
	TextColor3 = Color3.fromRGB(205, 205, 210),
	Text = "",
	LayoutOrder = 3,
	Parent = info,
})
local infoNeeds = text({
	Size = UDim2.new(1, 0, 0, 0),
	AutomaticSize = Enum.AutomaticSize.Y,
	TextXAlignment = Enum.TextXAlignment.Left,
	TextWrapped = true,
	RichText = true,
	Font = Fonts.Title,
	TextSize = 12,
	Text = "",
	LayoutOrder = 4,
	Parent = info,
})
local buttonRow = new("Frame", {
	Size = UDim2.new(1, 0, 0, 36),
	BackgroundTransparency = 1,
	LayoutOrder = 5,
	Parent = info,
})
local unlockButton = round(new("TextButton", {
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.fromScale(0.5, 1),
	Size = UDim2.fromOffset(190, 30),
	BackgroundColor3 = DARK_STEEL,
	AutoButtonColor = false,
	Font = Fonts.Title,
	TextSize = 14,
	TextColor3 = SILVER,
	Text = "",
	Parent = buttonRow,
}), UDim.new(0, 4))
local unlockStroke = outline(unlockButton, STEEL, 1, 0.5)

-- Reset (canto de baixo, à direita)
local resetButton = new("TextButton", {
	AnchorPoint = Vector2.new(1, 1),
	Position = UDim2.new(1, -40, 1, -30),
	Size = UDim2.fromOffset(280, 20),
	BackgroundTransparency = 1,
	AutoButtonColor = false,
	TextXAlignment = Enum.TextXAlignment.Right,
	Font = Fonts.Body,
	TextSize = 13,
	TextColor3 = STEEL,
	Text = "",
	Parent = screen,
})


-- ================= Árvore: nós e correntes =================

local nodeViews = {} -- [id] = view
local edgeViews = {} -- lista de { From, To, Rings, Bars }

-- Cadeado desenhado com Frames (o emoji sairia amarelo): arco, corpo e buraco da chave
local function drawLock(parent, size)
	local holder = new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(size, size),
		BackgroundTransparency = 1,
		Visible = false,
		ZIndex = 4,
		Parent = parent,
	})
	local thickness = math.max(2, math.floor(size * 0.1 + 0.5))
	local clip = new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0),
		Size = UDim2.fromOffset(size * 0.72, size * 0.5),
		BackgroundTransparency = 1,
		ClipsDescendants = true,
		ZIndex = 4,
		Parent = holder,
	})
	local arc = round(new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, thickness),
		Size = UDim2.fromOffset(size * 0.46, size * 0.62),
		BackgroundTransparency = 1,
		ZIndex = 4,
		Parent = clip,
	}))
	local arcStroke = outline(arc, STEEL, thickness)
	local body = round(new("Frame", {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromScale(0.5, 1),
		Size = UDim2.fromOffset(size * 0.78, size * 0.52),
		BackgroundColor3 = STEEL,
		BorderSizePixel = 0,
		ZIndex = 5,
		Parent = holder,
	}), UDim.new(0, math.max(2, size * 0.12)))
	round(new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.45),
		Size = UDim2.fromOffset(math.max(2, size * 0.12), math.max(3, size * 0.22)),
		BackgroundColor3 = INK,
		BorderSizePixel = 0,
		ZIndex = 6,
		Parent = body,
	}))
	return { Holder = holder, Stroke = arcStroke, Body = body }
end

local function paintLock(lock, color, transparency)
	lock.Stroke.Color = color
	lock.Stroke.Transparency = transparency
	lock.Body.BackgroundColor3 = color
	lock.Body.BackgroundTransparency = transparency
end

-- Corrente de A até B: elos alternados (anel de frente e barra de lado), com brilho de metal
local function drawChain(fromEntry, toEntry)
	local from, to = SkillTreeData.Position(fromEntry), SkillTreeData.Position(toEntry)
	local fromRadius = (if fromEntry.Id == "Root" then ROOT_SIZE else NODE_SIZE) / 2
	local delta = to - from
	local direction = delta.Unit
	local start = from + direction * (fromRadius + 3)
	local finish = to - direction * (NODE_SIZE / 2 + 3)
	local length = (finish - start).Magnitude
	local middle = (start + finish) / 2
	local holder = new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(middle.X, middle.Y),
		Size = UDim2.fromOffset(length, 14),
		Rotation = math.deg(math.atan2(delta.Y, delta.X)),
		BackgroundTransparency = 1,
		Parent = edgeLayer,
	})
	local view = { From = fromEntry.Id, To = toEntry.Id, Rings = {}, Bars = {} }
	local count = math.max(1, math.floor(length / LINK_SPACING))
	local spacing = length / count
	for i = 0, count do
		local x = i * spacing
		if i % 2 == 0 then
			local ring = round(new("Frame", {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.new(0, x, 0.5, 0),
				Size = UDim2.fromOffset(17, 10),
				BackgroundTransparency = 1,
				Parent = holder,
			}))
			local stroke = outline(ring, DARK_STEEL, 2.6)
			new("UIGradient", {
				Rotation = 90,
				Color = ColorSequence.new(WHITE, Color3.fromRGB(150, 150, 158)),
				Parent = stroke,
			})
			table.insert(view.Rings, stroke)
		else
			local bar = round(new("Frame", {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.new(0, x, 0.5, 0),
				Size = UDim2.fromOffset(13, 4),
				BackgroundColor3 = DARK_STEEL,
				BorderSizePixel = 0,
				Parent = holder,
			}))
			new("UIGradient", {
				Rotation = 90,
				Color = ColorSequence.new(WHITE, Color3.fromRGB(130, 130, 138)),
				Parent = bar,
			})
			table.insert(view.Bars, bar)
		end
	end
	table.insert(edgeViews, view)
end

local selected -- nó escolhido (entrada do SkillTreeData)
local hovered -- view com o mouse em cima
local selectNode -- definida depois

local function createNode(entry)
	local isRoot = entry.Id == "Root"
	local size = if isRoot then ROOT_SIZE else NODE_SIZE
	local position = SkillTreeData.Position(entry)
	local frame = round(new("TextButton", {
		Name = entry.Id,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(position.X, position.Y),
		Size = UDim2.fromOffset(size, size),
		BackgroundColor3 = INK,
		AutoButtonColor = false,
		Text = "",
		Parent = nodeLayer,
	}))
	local stroke = outline(frame, DARK_STEEL, 2)
	local scale = new("UIScale", { Parent = frame })

	-- Brilho vermelho (dá para pegar agora) e anel de seleção
	local glow = round(new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(1, 16, 1, 16),
		BackgroundTransparency = 1,
		Visible = false,
		ZIndex = 0,
		Parent = frame,
	}))
	local glowStroke = outline(glow, BLOOD, 3, 0.4)
	local ring = round(new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(1, 10, 1, 10),
		BackgroundTransparency = 1,
		Visible = false,
		Parent = frame,
	}))
	outline(ring, SILVER, 1.2, 0.1)

	local icon
	if isRoot then
		-- Centro: o rosto do jogador, com anel duplo
		icon = round(new("ImageLabel", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.new(1, -10, 1, -10),
			BackgroundColor3 = Color3.fromRGB(200, 200, 204),
			Image = `rbxthumb://type=AvatarHeadShot&id={player.UserId}&w=150&h=150`,
			Parent = frame,
		}))
		ring.Visible = true
	else
		icon = text({
			Size = UDim2.fromScale(1, 1),
			TextXAlignment = Enum.TextXAlignment.Center,
			Font = Fonts.Title,
			TextSize = 24,
			Text = entry.Icon,
			Parent = frame,
		})
	end

	local view = {
		Entry = entry,
		Frame = frame,
		Stroke = stroke,
		Glow = glow,
		GlowStroke = glowStroke,
		Ring = ring,
		Icon = icon,
		Lock = drawLock(frame, math.floor(size * 0.42)),
		Scale = scale,
		State = nil,
	}
	nodeViews[entry.Id] = view

	frame.MouseEnter:Connect(function()
		hovered = view
		UITheme.tween(scale, 0.12, { Scale = 1.1 })
	end)
	frame.MouseLeave:Connect(function()
		if hovered == view then
			hovered = nil
		end
		if selected ~= entry then
			UITheme.tween(scale, 0.12, { Scale = 1 })
		end
	end)
	frame.Activated:Connect(function()
		selectNode(entry)
	end)
end

for _, entry in SkillTreeData.Nodes do
	for _, required in entry.Requires do
		local parent = SkillTreeData.Get(required)
		if parent then
			drawChain(parent, entry)
		end
	end
end
for _, entry in SkillTreeData.Nodes do
	createNode(entry)
end

-- Marca d'água de cada galho: kanji gigante bem apagado depois do último nó, com o nome embaixo
for branchId, branch in SkillTreeData.Branches do
	local maxDepth = 0
	for _, entry in SkillTreeData.Nodes do
		if entry.Branch == branchId then
			maxDepth = math.max(maxDepth, entry.Depth)
		end
	end
	local angle = math.rad(branch.Angle)
	local position = Vector2.new(math.cos(angle), math.sin(angle)) * (maxDepth + 1) * SkillTreeData.Step
	text({
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(position.X, position.Y),
		Size = UDim2.fromOffset(140, 130),
		TextXAlignment = Enum.TextXAlignment.Center,
		Font = Fonts.Title,
		TextSize = 110,
		TextTransparency = 0.88,
		Text = branch.Icon,
		Parent = markLayer,
	})
	text({
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromOffset(position.X, position.Y + 58),
		Size = UDim2.fromOffset(200, 18),
		TextXAlignment = Enum.TextXAlignment.Center,
		Font = Fonts.Title,
		TextSize = 15,
		TextColor3 = STEEL,
		TextTransparency = 0.35,
		Text = branch.Name,
		Parent = markLayer,
	})
end

-- ================= Estado =================

local unlocked = {} -- conjunto de nós desbloqueados (inclui os padrão)
local levels = {} -- [estilo] = nível de maestria

local function readUnlocked()
	local ok, list = pcall(function()
		return HttpService:JSONDecode(player:GetAttribute("SkillTree") or "[]")
	end)
	return SkillTreeData.UnlockedSet(if ok and type(list) == "table" then list else {})
end

local function readMastery()
	local result = {}
	for _, value in masteryFolder:GetChildren() do
		if value:IsA("IntValue") then
			result[value.Name] = (SkillTreeData.MasteryLevel(value.Value))
		end
	end
	return result
end

local function isConnected(entry)
	for _, required in entry.Requires do
		if unlocked[required] then
			return true
		end
	end
	return #entry.Requires == 0
end

-- "Unlocked", "Available" (dá para pegar agora), "Locked" (ligado, falta ponto/maestria) ou "Hidden"
local function stateOf(entry)
	if unlocked[entry.Id] then return "Unlocked" end
	if not SkillTreeData.Blocker(entry, unlocked, levels, points.Value) then return "Available" end
	return if isConnected(entry) then "Locked" else "Hidden"
end

local function paintNode(view)
	local state = stateOf(view.Entry)
	view.State = state
	local frame, stroke = view.Frame, view.Stroke
	local isText = view.Icon:IsA("TextLabel")
	view.Glow.Visible = state == "Available"
	if state == "Unlocked" then
		frame.BackgroundTransparency = 0.05
		stroke.Color = SILVER
		stroke.Thickness = 2
		stroke.Transparency = 0
		view.Lock.Holder.Visible = false
		if isText then
			view.Icon.Visible = true
			view.Icon.TextColor3 = SILVER
			view.Icon.TextTransparency = 0
		end
	elseif state == "Available" then
		frame.BackgroundTransparency = 0.05
		stroke.Color = SILVER
		stroke.Thickness = 2
		stroke.Transparency = 0.3
		view.Lock.Holder.Visible = false
		if isText then
			view.Icon.Visible = true
			view.Icon.TextColor3 = SILVER
			view.Icon.TextTransparency = 0.25
		end
	elseif state == "Locked" then
		frame.BackgroundTransparency = 0.35
		stroke.Color = STEEL
		stroke.Thickness = 1.5
		stroke.Transparency = 0.55
		view.Lock.Holder.Visible = true
		paintLock(view.Lock, STEEL, 0.1)
		if isText then view.Icon.Visible = false end
	else
		frame.BackgroundTransparency = 0.65
		stroke.Color = DARK_STEEL
		stroke.Thickness = 1.5
		stroke.Transparency = 0.5
		view.Lock.Holder.Visible = true
		paintLock(view.Lock, Color3.fromRGB(100, 100, 108), 0.35)
		if isText then view.Icon.Visible = false end
	end
end

local function paintEdges()
	for _, view in edgeViews do
		local lit = unlocked[view.From] and unlocked[view.To]
		local color = if lit then SILVER else DARK_STEEL
		local transparency = if lit then 0 else 0.35
		for _, stroke in view.Rings do
			stroke.Color = color
			stroke.Transparency = transparency
		end
		for _, bar in view.Bars do
			bar.BackgroundColor3 = color
			bar.BackgroundTransparency = transparency
		end
	end
end

local function hex(color)
	return "#" .. color:ToHex()
end

local function paintInfo()
	local entry = selected
	if not entry then
		infoTitle.Text = "Árvore de habilidades"
		infoBranch.Text = "Escolha um nó"
		infoBody.Text = "Clique num nó para ver o que ele faz. Arraste para mover e use a roda do mouse para o zoom."
		infoNeeds.Text = ""
		buttonRow.Visible = false
		return
	end
	local branch = entry.Branch and SkillTreeData.Branches[entry.Branch]
	infoTitle.Text = entry.Name
	infoBranch.Text = if branch then `{branch.Icon}  {branch.Name}` else "鎖  CENTRO"
	local lines = {}
	for _, line in SkillTreeData.Describe(entry) do
		table.insert(lines, "· " .. line)
	end
	if entry.Flavor then
		table.insert(lines, `<font color="{hex(STEEL)}"><i>{UITheme.escape(entry.Flavor)}</i></font>`)
	end
	infoBody.Text = table.concat(lines, "\n")

	-- Requisitos: vermelho o que falta
	local needs = {}
	if not entry.Default then
		local enough = unlocked[entry.Id] or points.Value >= entry.Cost
		table.insert(needs, `<font color="{hex(if enough then SILVER else BLOOD)}">{entry.Cost} ponto(s)</font>`)
	end
	if entry.Mastery then
		local have = levels[entry.Mastery.Style] or 0
		local ok = have >= entry.Mastery.Level
		table.insert(needs, `<font color="{hex(if ok then SILVER else BLOOD)}">Maestria {entry.Mastery.Style} {entry.Mastery.Level} (você: {have})</font>`)
	end
	infoNeeds.Text = table.concat(needs, "   ·   ")

	local state = stateOf(entry)
	buttonRow.Visible = not entry.Default
	if state == "Unlocked" then
		unlockButton.Text = "✓  DESBLOQUEADO"
		unlockButton.BackgroundColor3 = Color3.fromRGB(58, 58, 64)
		unlockButton.TextColor3 = SILVER
		unlockStroke.Color = STEEL
	elseif state == "Available" then
		unlockButton.Text = "DESBLOQUEAR"
		unlockButton.BackgroundColor3 = BLOOD
		unlockButton.TextColor3 = WHITE
		unlockStroke.Color = Color3.fromRGB(255, 120, 120)
	else
		unlockButton.Text = "BLOQUEADO"
		unlockButton.BackgroundColor3 = Color3.fromRGB(34, 34, 38)
		unlockButton.TextColor3 = STEEL
		unlockStroke.Color = DARK_STEEL
	end
end

local function paintMastery()
	for style, row in masteryRows do
		local value = masteryFolder:FindFirstChild(style)
		local lvl, into, need = SkillTreeData.MasteryLevel(if value then value.Value else 0)
		local maxed = lvl >= SkillTreeData.Mastery.MaxLevel
		row.Level.Text = `Nv. {lvl}`
		row.Fill.Size = UDim2.fromScale(if maxed then 1 else math.clamp(into / math.max(1, need), 0, 1), 1)
		row.XP.Text = if maxed then "máximo" else `{into} / {need}`
	end
end

local resetArmedUntil = 0
local function paintReset()
	if os.clock() < resetArmedUntil then
		resetButton.Text = "Clique de novo para confirmar o reset"
		resetButton.TextColor3 = BLOOD
	else
		resetButton.Text = `Resetar árvore  ·  {UITheme.formatNumber(StatConfig.ResetCost(level.Value))} Gold`
		resetButton.TextColor3 = STEEL
	end
end

local function paintAll()
	unlocked = readUnlocked()
	levels = readMastery()
	pointsLabel.Text = tostring(points.Value)
	diamondStroke.Color = if points.Value > 0 then SILVER else DARK_STEEL
	for _, view in nodeViews do
		paintNode(view)
	end
	paintEdges()
	paintInfo()
	paintMastery()
	paintReset()
end

function selectNode(entry)
	local previous = selected and nodeViews[selected.Id]
	selected = entry
	if previous and previous.Entry ~= entry then
		UITheme.tween(previous.Scale, 0.12, { Scale = 1 })
		if previous.Entry.Id ~= "Root" then
			previous.Ring.Visible = false
		end
	end
	local view = nodeViews[entry.Id]
	if view then
		UITheme.tween(view.Scale, 0.12, { Scale = 1.12 })
		view.Ring.Visible = true
	end
	paintInfo()
end

-- Nó recém-desbloqueado: anel prateado abrindo e um clarão vermelho
local function burst(view)
	for i, color in { SILVER, BLOOD } do
		local wave = round(new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			ZIndex = 5,
			Parent = view.Frame,
		}))
		local stroke = outline(wave, color, 3 - i, 0)
		UITheme.tween(wave, 0.45 + i * 0.1, { Size = UDim2.fromScale(2.2 + i * 0.4, 2.2 + i * 0.4) })
		UITheme.tween(stroke, 0.45 + i * 0.1, { Transparency = 1 })
		task.delay(0.7, function()
			wave:Destroy()
		end)
	end
end

local lastUnlocked = readUnlocked()
player:GetAttributeChangedSignal("SkillTree"):Connect(function()
	local now = readUnlocked()
	for id in now do
		if not lastUnlocked[id] and nodeViews[id] then
			burst(nodeViews[id])
		end
	end
	lastUnlocked = now
	paintAll()
end)
points.Changed:Connect(paintAll)
gold.Changed:Connect(paintAll)
level.Changed:Connect(paintAll)
local function watchMastery(value)
	if value:IsA("IntValue") then
		value.Changed:Connect(paintAll)
	end
	paintAll()
end
masteryFolder.ChildAdded:Connect(watchMastery)
for _, value in masteryFolder:GetChildren() do
	watchMastery(value)
end

unlockButton.MouseButton1Click:Connect(function()
	if selected and stateOf(selected) == "Available" then
		Remotes.SkillTreeUnlock:FireServer(selected.Id)
	end
end)

-- Reset: pede confirmação com um segundo clique
resetButton.MouseButton1Click:Connect(function()
	if os.clock() < resetArmedUntil then
		resetArmedUntil = 0
		paintReset()
		Remotes.StatusReset:FireServer()
	else
		resetArmedUntil = os.clock() + 3
		paintReset()
		task.delay(3.05, paintReset)
	end
end)
resetButton.MouseEnter:Connect(function()
	if os.clock() >= resetArmedUntil then
		resetButton.TextColor3 = SILVER
	end
end)
resetButton.MouseLeave:Connect(paintReset)

-- Todo frame: brilho vermelho pulsando nos disponíveis e a etiqueta seguindo o nó
RunService.RenderStepped:Connect(function()
	if not screen.Enabled then return end
	local pulse = (math.sin(os.clock() * 4) + 1) / 2
	for _, view in nodeViews do
		if view.State == "Available" then
			view.GlowStroke.Transparency = 0.2 + pulse * 0.55
		end
	end
	local target = hovered or (selected and nodeViews[selected.Id])
	if target and viewport.Visible then
		local frame = target.Frame
		tooltipText.Text = target.Entry.Name
		tooltip.Position = UDim2.fromOffset(frame.AbsolutePosition.X + frame.AbsoluteSize.X / 2, frame.AbsolutePosition.Y - 10)
		tooltip.Visible = true
	else
		tooltip.Visible = false
	end
end)

-- ================= Arrastar e zoom =================

local pan = Vector2.new(0, -60) -- um pouco para cima: o painel de baixo não cobre o centro
local zoom = ZOOM_DEFAULT

local function applyView()
	canvas.Position = UDim2.new(0.5, pan.X, 0.5, pan.Y)
	canvasScale.Scale = zoom
	local ratio = (zoom - ZOOM_MIN) / (ZOOM_MAX - ZOOM_MIN)
	zoomFill.Size = UDim2.fromScale(ratio, 1)
	zoomKnob.Position = UDim2.fromScale(ratio, 0.5)
	zoomLabel.Text = `{math.floor(zoom * 100 + 0.5)}%`
end

local function setZoom(value)
	zoom = math.clamp(value, ZOOM_MIN, ZOOM_MAX)
	applyView()
end

local dragging, dragLast = nil, nil
viewport.InputBegan:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
		dragging = input
		dragLast = Vector2.new(input.Position.X, input.Position.Y)
	end
end)

local sliding = false
local function slideTo(x)
	local ratio = math.clamp((x - zoomTrack.AbsolutePosition.X) / math.max(1, zoomTrack.AbsoluteSize.X), 0, 1)
	setZoom(ZOOM_MIN + ratio * (ZOOM_MAX - ZOOM_MIN))
end
zoomKnob.InputBegan:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
		sliding = true
	end
end)
zoomTrack.InputBegan:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
		sliding = true
		slideTo(input.Position.X)
	end
end)

UserInputService.InputChanged:Connect(function(input)
	if not screen.Enabled then return end
	if sliding and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
		slideTo(input.Position.X)
		return
	end
	if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input == dragging) then
		local position = Vector2.new(input.Position.X, input.Position.Y)
		pan += position - dragLast
		dragLast = position
		applyView()
	elseif input.UserInputType == Enum.UserInputType.MouseWheel and viewport.Visible then
		setZoom(zoom * (1 + 0.1 * input.Position.Z))
	end
end)
UserInputService.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
		dragging = nil
		sliding = false
	end
end)

-- Pinça (celular)
local pinchStart = ZOOM_DEFAULT
UserInputService.TouchPinch:Connect(function(_, scale, _, state)
	if not screen.Enabled or not viewport.Visible then return end
	if state == Enum.UserInputState.Begin then
		pinchStart = zoom
	else
		setZoom(pinchStart * scale)
	end
end)


-- ================= Páginas e abrir / fechar =================

local isOpen = false
local page = "Tree"
local cameraEffects = {}
local hiddenGuis = {} -- telas escondidas ao abrir, para voltar como estavam

local function hideOthers(hide)
	if hide then
		for _, name in HIDE_WHILE_OPEN do
			local gui = playerGui:FindFirstChild(name)
			if gui and gui:IsA("ScreenGui") and gui.Enabled then
				gui.Enabled = false
				table.insert(hiddenGuis, gui)
			end
		end
	else
		for _, gui in hiddenGuis do
			if gui.Parent then
				gui.Enabled = true
			end
		end
		table.clear(hiddenGuis)
	end
end

-- O mundo atrás fica em preto e branco e embaçado (efeitos só na câmera deste jogador)
local function setCameraEffects(on)
	for _, effect in cameraEffects do
		effect:Destroy()
	end
	table.clear(cameraEffects)
	local camera = workspace.CurrentCamera
	if not on or not camera then return end
	local blur = new("BlurEffect", { Size = 0, Parent = camera })
	local grade = new("ColorCorrectionEffect", { Saturation = 0, Brightness = 0, Contrast = 0, Parent = camera })
	UITheme.tween(blur, 0.25, { Size = 18 })
	UITheme.tween(grade, 0.25, { Saturation = -1, Brightness = -0.08, Contrast = 0.08 })
	cameraEffects = { blur, grade }
end

local function setPage(id)
	page = id
	local tree = id == "Tree"
	viewport.Visible = tree
	bottom.Visible = tree
	masteryPanel.Visible = tree
	resetButton.Visible = tree
	for itemId, view in navButtons do
		local active = itemId == id
		local color = if active then GOLD_PALE else STEEL
		view.Label.TextColor3 = color
		view.Icon.TextColor3 = color
		view.Button.BackgroundTransparency = if active then 0.92 else 1
	end
end

local function setOpen(open)
	if open == isOpen then return end
	isOpen = open
	if open then
		paintAll()
		setPage("Tree")
		applyView()
		screen.Enabled = true
		hideOthers(true)
		setCameraEffects(true)
		backdrop.BackgroundTransparency = 1
		UITheme.tween(backdrop, 0.2, { BackgroundTransparency = 0.45 })
	else
		screen.Enabled = false
		hideOthers(false)
		setCameraEffects(false)
		dragging = nil
		sliding = false
		hovered = nil
	end
end

for itemId, view in navButtons do
	view.Button.MouseEnter:Connect(function()
		if page ~= itemId then
			view.Label.TextColor3 = SILVER
			view.Icon.TextColor3 = SILVER
		end
	end)
	view.Button.MouseLeave:Connect(function()
		if page ~= itemId then
			view.Label.TextColor3 = STEEL
			view.Icon.TextColor3 = STEEL
		end
	end)
	view.Button.MouseButton1Click:Connect(function()
		if itemId == "Close" then
			setOpen(false)
		elseif itemId == "Path" or itemId == "Inventory" then
			-- O caminho fica no StatusMenu e o inventário na tela própria (Inventory.client)
			setOpen(false)
			local menu = playerGui:FindFirstChild(if itemId == "Path" then "StatusMenu" else "Inventory")
			local toggle = menu and menu:FindFirstChild("Toggle")
			if toggle then
				toggle:Fire()
			end
		else
			setPage(itemId)
		end
	end)
end

toggleEvent.Event:Connect(function()
	setOpen(not isOpen)
end)

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed or player:GetAttribute("MenuOpen") then return end
	if input.KeyCode == Enum.KeyCode.M then
		setOpen(not isOpen)
	end
end)

selected = nil
paintAll()
