-- Minimapa (canto da tela): a cidade vista de cima, girando com a câmera (o que está à frente da câmera fica para
-- cima), com os símbolos por cima:
--   seta branca: você (aponta para onde o personagem olha) · pontos azuis: outros jogadores
--   pontos vermelhos: inimigos · losango vermelho: chefe
--   losango branco: NPC · "!" dourado: NPC com missão para pegar · "?" dourado: NPC que a missão manda procurar
--   círculo vermelho com "×": zona dos inimigos que a missão pede
-- O que a missão pede e está fora do círculo vira um ícone na borda, com uma seta e a distância. Clique no
-- minimapa para trocar o zoom. No PC fica embaixo à direita; no celular, em cima à direita (longe do pulo).
-- Fundo: quatro imagens 2D pre-calculadas da cidade. Nenhuma geometria e copiada no cliente.
-- Dados: Remotes.QuestEvent ("State": Quests[].Objectives { Type, Target, TargetList, Progress, Amount } e Givers),
-- tag QuestGiver + atributo NPCId (NPCs), atributo ZoneType nas zonas de workspace.EnemySpawns (escrito pelo
-- Spawner) e workspace.Enemies (atributos EnemyType e Boss).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local CollectionService = game:GetService("CollectionService")

local Remotes = require(ReplicatedStorage:WaitForChild("Remotes"))
local UITheme = require(ReplicatedStorage:WaitForChild("UITheme"))
local FastMode = require(script.Parent:WaitForChild("FastMode"))
local Atlas = require(ReplicatedStorage:WaitForChild("MinimapAtlas"))

local Colors = UITheme.Colors
local Fonts = UITheme.Fonts

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local SIZE = 190 -- diâmetro em pixels (antes da escala da tela)
local ZOOMS = { 120, 240, 480 } -- raio visível em studs em cada nível de zoom (clique troca)
local QUEST_TAG = "QuestGiver"
local EDGE_MARGIN = 12 -- ícone de fora do círculo: a quantos pixels da borda ele fica
local LIST_REFRESH = 0.25 -- intervalo para atualizar as listas (inimigos, jogadores, NPCs, zonas)
-- Limita o trabalho de UI; nao ha renderizacao 3D nem filas de clonagem.
local MAP_RATE, FAST_MAP_RATE = 20, 10
local ZONE_REFRESH = 2.0 -- intervalo para atualizar as zonas (mais raro que as listas de inimigos)

local RADIUS = SIZE / 2
local GOLD = Colors.Gold
local RED = Colors.Accent
local PAPER = Colors.Text
local PLAYER_BLUE = Color3.fromRGB(110, 190, 255)

local function new(className, props)
	return UITheme.new(className, props)
end

local function round(frame)
	UITheme.corner(frame, UDim.new(0.5, 0))
	return frame
end

-- ================= Tela =================

local screen = UITheme.screen("Minimap", 0, playerGui) -- abaixo da HUD (o painel de configurações abre por cima)
local touchOnly = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled

local holder = new("Frame", {
	Name = "Holder",
	AnchorPoint = if touchOnly then Vector2.new(1, 0) else Vector2.new(1, 1),
	Position = if touchOnly then UDim2.new(1, -12, 0, 12) else UDim2.new(1, -18, 1, -18),
	Size = UDim2.fromOffset(SIZE, SIZE),
	BackgroundTransparency = 1,
	Parent = screen,
})
UITheme.autoScale(holder, 1100, 700)
holder:SetAttribute("TutorialAnchor", "Minimap") -- o tutorial destaca o minimapa

-- Um unico recorte circular pequeno para o fundo 2D e os marcadores.
local disc = round(new("CanvasGroup", {
	Name = "Map2D",
	Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = Color3.fromRGB(25, 32, 37),
	ClipsDescendants = true,
	ZIndex = 1,
	Parent = holder,
}))
local mapTiles = {}
for index, tile in Atlas.Tiles do
	local image = new("ImageLabel", {
		Name = "Tile" .. index,
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Image = tile.Image,
		Visible = false,
		ZIndex = 1,
		Parent = disc,
	})
	table.insert(mapTiles, { Image = image, Center = tile.Center })
end
-- Carrega as quatro imagens em segundo plano antes de cruzar uma divisao do atlas.
task.spawn(function()
	local images = {}
	for _, tile in mapTiles do table.insert(images, tile.Image) end
	local ok, err = pcall(function() game:GetService("ContentProvider"):PreloadAsync(images) end)
	if not ok then warn("[Minimap] Falha ao carregar imagem 2D: " .. tostring(err)) end
end)

-- Símbolos de dentro (recortados pelo círculo) e de fora (na borda, sem recorte)
local inner = new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 2, Parent = disc })
local outer = new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 3, Parent = holder })

-- Aro: tinta por fora, vermelho escuro por dentro (como os painéis da HUD)
local rim = round(new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 2, Parent = holder }))
UITheme.stroke(rim, Colors.Black, 4)
local rimInner = round(new("Frame", {
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.new(1, -3, 1, -3),
	BackgroundTransparency = 1,
	ZIndex = 2,
	Parent = holder,
}))
UITheme.stroke(rimInner, Colors.Stroke, 2)

-- Norte: um "N" que anda pela borda conforme a câmera gira
local northLabel = UITheme.label({
	AnchorPoint = Vector2.new(0.5, 0.5),
	Size = UDim2.fromOffset(18, 18),
	TextXAlignment = Enum.TextXAlignment.Center,
	Font = Fonts.Display,
	TextSize = 16,
	TextColor3 = RED,
	TextStrokeTransparency = 0.2,
	Text = "N",
	ZIndex = 5,
	Parent = outer,
})

-- Você: seta no centro
local arrow = UITheme.label({
	Name = "PlayerArrow",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromOffset(20, 20),
	TextXAlignment = Enum.TextXAlignment.Center,
	Font = Fonts.Title,
	TextSize = 18,
	TextColor3 = PAPER,
	TextStrokeTransparency = 0,
	Text = "▲",
	ZIndex = 6,
	Parent = outer,
})

-- Zoom: clique troca; o nível aparece por um instante
local zoomButton = new("TextButton", {
	Name = "ZoomButton",
	Size = UDim2.fromScale(1, 1),
	BackgroundTransparency = 1,
	AutoButtonColor = false,
	ZIndex = 8,
	Parent = holder,
})
local zoomLabel = UITheme.label({
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 22),
	Size = UDim2.fromOffset(90, 16),
	TextXAlignment = Enum.TextXAlignment.Center,
	Font = Fonts.Title,
	TextSize = 12,
	TextStrokeTransparency = 0.3,
	TextTransparency = 1,
	ZIndex = 7,
	Parent = outer,
})

-- ================= Símbolos =================

-- Ícone redondo com um caractere (NPC de missão, alvo): fundo, contorno de tinta e texto
local function iconMarker(parent, size, fill, glyph, glyphColor)
	local frame = round(new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromOffset(size, size),
		BackgroundColor3 = fill,
		Visible = false,
		ZIndex = 4,
		Parent = parent,
	}))
	UITheme.stroke(frame, Colors.Black, 2)
	local label = UITheme.label({
		Size = UDim2.fromScale(1, 1),
		TextXAlignment = Enum.TextXAlignment.Center,
		Font = Fonts.Number,
		TextSize = size - 4,
		TextColor3 = glyphColor,
		Text = glyph,
		ZIndex = 5,
		Parent = frame,
	})
	return frame, label
end

-- Losango (NPC comum, chefe)
local function diamondMarker(parent, size, fill)
	local frame = new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromOffset(size, size),
		Rotation = 45,
		BackgroundColor3 = fill,
		BorderSizePixel = 0,
		Visible = false,
		ZIndex = 3,
		Parent = parent,
	})
	UITheme.stroke(frame, Colors.Black, 1.5)
	return frame
end

local function dotMarker(parent, size, fill)
	local frame = round(new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromOffset(size, size),
		BackgroundColor3 = fill,
		BorderSizePixel = 0,
		Visible = false,
		ZIndex = 3,
		Parent = parent,
	}))
	UITheme.stroke(frame, Colors.Black, 1)
	return frame
end

-- Alvo de missão: ícone (dentro do círculo ou na borda), seta apontando para fora e distância quando está longe
local function objectiveMarker(fill, glyph, glyphColor)
	local icon = iconMarker(outer, 20, fill, glyph, glyphColor)
	local pointer = UITheme.label({
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromOffset(12, 12),
		TextXAlignment = Enum.TextXAlignment.Center,
		Font = Fonts.Title,
		TextSize = 11,
		TextColor3 = fill,
		TextStrokeTransparency = 0,
		Text = "▲",
		Visible = false,
		ZIndex = 5,
		Parent = outer,
	})
	local distance = UITheme.label({
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromOffset(46, 12),
		TextXAlignment = Enum.TextXAlignment.Center,
		Font = Fonts.Title,
		TextSize = 10,
		TextColor3 = PAPER,
		TextStrokeTransparency = 0.2,
		Visible = false,
		ZIndex = 5,
		Parent = outer,
	})
	-- Anel pulsando em volta (o alvo chama atenção)
	local pulse = round(new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ZIndex = 4,
		Parent = icon,
	}))
	local pulseStroke = UITheme.stroke(pulse, fill, 2)
	return { Icon = icon, Pointer = pointer, Distance = distance, Pulse = pulse, PulseStroke = pulseStroke }
end

-- Pools: cada lista reusa os Frames entre atualizações
local pools = {}
local function pool(name, factory)
	pools[name] = { Items = {}, Used = 0, Factory = factory }
end
local function take(name)
	local p = pools[name]
	p.Used += 1
	local item = p.Items[p.Used]
	if not item then
		item = p.Factory()
		p.Items[p.Used] = item
	end
	return item
end
local function resetPools()
	for _, p in pools do
		p.Used = 0
	end
end
local function hideUnused()
	for _, p in pools do
		for i = p.Used + 1, #p.Items do
			local item = p.Items[i]
			if typeof(item) == "Instance" then
				item.Visible = false
			else
				item.Icon.Visible = false
				item.Pointer.Visible = false
				item.Distance.Visible = false
			end
		end
	end
end

pool("Enemy", function() return dotMarker(inner, 5, RED) end)
pool("Boss", function() return diamondMarker(inner, 11, Color3.fromRGB(150, 10, 18)) end)
pool("Player", function() return dotMarker(inner, 7, PLAYER_BLUE) end)
pool("Npc", function() return diamondMarker(inner, 8, PAPER) end)
pool("Zone", function()
	local frame = round(new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = RED,
		BackgroundTransparency = 0.78,
		Visible = false,
		ZIndex = 2,
		Parent = inner,
	}))
	UITheme.stroke(frame, RED, 1.5, 0.2)
	return frame
end)
pool("Giver", function() return objectiveMarker(GOLD, "!", Colors.Black) end)
pool("TalkTo", function() return objectiveMarker(GOLD, "?", Colors.Black) end)
pool("Kill", function() return objectiveMarker(RED, "×", PAPER) end)

-- ================= Estado das missões =================

local giverIds = {} -- [NPCId] = true: tem missão para pegar
local talkTargets = {} -- [NPCId] = true: objetivo "falar com"
local killTargets = {} -- [EnemyType] = true: objetivo "derrotar" (com alvo definido)

local function addTargets(set, objective)
	if type(objective.Target) == "string" then
		set[objective.Target] = true
	elseif type(objective.TargetList) == "table" then
		for _, target in objective.TargetList do
			if type(target) == "string" then
				set[target] = true
			end
		end
	end
end

local questConnection = Remotes.QuestEvent.OnClientEvent:Connect(function(data)
	if type(data) ~= "table" or data.Action ~= "State" then return end
	table.clear(giverIds)
	table.clear(talkTargets)
	table.clear(killTargets)
	for _, id in data.Givers or {} do
		giverIds[id] = true
	end
	for _, quest in data.Quests or {} do
		for _, objective in quest.Objectives or {} do
			if (objective.Progress or 0) < (objective.Amount or 1) then
				if objective.Type == "TalkTo" then
					addTargets(talkTargets, objective)
				elseif objective.Type == "Kill" then
					addTargets(killTargets, objective)
				end
			end
		end
	end
end)
-- O QuestGUI também pede; o servidor só responde com o estado atual
Remotes.QuestEvent:FireServer()

-- ================= Listas do mundo (atualizadas a cada LIST_REFRESH) =================

local npcs = {} -- { Id, Position }
local zones = {} -- { Type, Position, Radius }
local enemies = {} -- { Root, Type, Boss }
local others = {} -- HumanoidRootPart dos outros jogadores
local nearestByType = {} -- reusado a cada frame (não aloca novo)

local function modelPosition(model)
	if model:IsA("BasePart") then return model.Position end
	local root = model:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then return root.Position end
	return model:GetPivot().Position
end

local function refreshEntities()
	table.clear(npcs)
	for _, model in CollectionService:GetTagged(QUEST_TAG) do
		if model:IsDescendantOf(workspace) then
			local id = model:GetAttribute("NPCId")
			table.insert(npcs, { Id = if type(id) == "string" and id ~= "" then id else model.Name, Position = modelPosition(model) })
		end
	end

	table.clear(enemies)
	local folder = workspace:FindFirstChild("Enemies")
	if folder then
		for _, npc in folder:GetChildren() do
			local root = npc:FindFirstChild("HumanoidRootPart")
			local humanoid = npc:FindFirstChildOfClass("Humanoid")
			if root and humanoid and humanoid.Health > 0 then
				table.insert(enemies, { Root = root, Type = npc:GetAttribute("EnemyType"), Boss = npc:GetAttribute("Boss") == true })
			end
		end
	end

	table.clear(others)
	for _, other in Players:GetPlayers() do
		local root = other ~= player and other.Character and other.Character:FindFirstChild("HumanoidRootPart")
		if root then
			table.insert(others, root)
		end
	end
end

local function refreshZones()
	table.clear(zones)
	local spawns = workspace:FindFirstChild("EnemySpawns")
	if spawns then
		for _, part in spawns:GetDescendants() do
			local zoneType = part:IsA("BasePart") and part:GetAttribute("ZoneType")
			if type(zoneType) == "string" then
				table.insert(zones, { Type = zoneType, Position = part.Position, Radius = math.max(part.Size.X, part.Size.Z) / 2 })
			end
		end
	end
end

-- ================= Desenho =================

local zoomIndex = 1
local nextListRefresh = 0

local function showZoom()
	zoomLabel.Text = `ZOOM {zoomIndex}x`
	zoomLabel.TextTransparency = 0
	zoomLabel.TextStrokeTransparency = 0.3
	UITheme.tween(zoomLabel, 1.2, { TextTransparency = 1, TextStrokeTransparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
end

local zoomConnection = zoomButton.Activated:Connect(function()
	zoomIndex = zoomIndex % #ZOOMS + 1
	showZoom()
end)

-- Frente da câmera no plano (vira o "para cima" do minimapa)
local function heading()
	local camera = workspace.CurrentCamera
	if not camera then return Vector3.new(0, 0, -1) end
	local look = camera.CFrame.LookVector
	local flat = Vector3.new(look.X, 0, look.Z)
	if flat.Magnitude < 0.05 then
		local up = camera.CFrame.UpVector
		flat = Vector3.new(up.X, 0, up.Z)
	end
	return if flat.Magnitude > 0.001 then flat.Unit else Vector3.new(0, 0, -1)
end

local center, forward, right, scale = Vector3.zero, Vector3.new(0, 0, -1), Vector3.new(1, 0, 0), 1

-- Ponto do mundo -> pixels a partir do centro do minimapa
local function project(position)
	local offset = position - center
	return Vector2.new(offset:Dot(right) * scale, -offset:Dot(forward) * scale)
end

local function place(frame, point)
	frame.Position = UDim2.new(0.5, point.X, 0.5, point.Y)
	frame.Visible = true
end

-- Dentro do círculo (com uma folga)?
local function inside(point, margin)
	return point.Magnitude <= RADIUS - (margin or 0)
end

-- Alvo de missão: dentro do círculo fica no lugar; fora, vai para a borda com seta e distância
local function placeObjective(item, position, showDistance, pulse)
	local point = project(position)
	local within = inside(point, EDGE_MARGIN)
	if within then
		place(item.Icon, point)
		item.Pointer.Visible = false
		item.Distance.Visible = false
	else
		local direction = if point.Magnitude > 0.001 then point.Unit else Vector2.new(0, -1)
		place(item.Icon, direction * (RADIUS - EDGE_MARGIN))
		place(item.Pointer, direction * (RADIUS + 1))
		item.Pointer.Rotation = math.deg(math.atan2(direction.Y, direction.X)) + 90
		if showDistance then
			local studs = Vector3.new(position.X - center.X, 0, position.Z - center.Z).Magnitude
			item.Distance.Text = `{math.floor(studs + 0.5)}m`
			place(item.Distance, direction * (RADIUS - EDGE_MARGIN - 17))
		else
			item.Distance.Visible = false
		end
	end
	-- Anel pulsando nos alvos da missão
	local wave = (os.clock() * 1.4) % 1
	item.Pulse.Visible = pulse
	if pulse then
		item.Pulse.Size = UDim2.fromScale(1 + wave * 1.1, 1 + wave * 1.1)
		item.PulseStroke.Transparency = wave
	end
end

local function draw()
	resetPools()

	-- Inimigos e chefes
	for _, enemy in enemies do
		if enemy.Root.Parent then
			local point = project(enemy.Root.Position)
			if inside(point, 2) then
				place(take(if enemy.Boss then "Boss" else "Enemy"), point)
			end
		end
	end

	-- Outros jogadores
	for _, root in others do
		if root.Parent then
			local point = project(root.Position)
			if inside(point, 2) then
				place(take("Player"), point)
			end
		end
	end

	-- NPCs: "?" se a missão manda falar com ele, "!" se tem missão para pegar, losango se não
	for _, npc in npcs do
		if talkTargets[npc.Id] then
			placeObjective(take("TalkTo"), npc.Position, true, true)
		elseif giverIds[npc.Id] then
			placeObjective(take("Giver"), npc.Position, false, false)
		else
			local point = project(npc.Position)
			if inside(point, 4) then
				place(take("Npc"), point)
			end
		end
	end

	-- Zonas dos inimigos que a missão pede: o círculo da zona quando aparece e um ícone na mais perto
	table.clear(nearestByType)
	for _, zone in zones do
		if killTargets[zone.Type] then
			local point = project(zone.Position)
			local size = math.max(10, zone.Radius * 2 * scale)
			if point.Magnitude - size / 2 < RADIUS then
				local frame = take("Zone")
				frame.Size = UDim2.fromOffset(size, size)
				place(frame, point)
			end
			local distance = (zone.Position - center).Magnitude
			local best = nearestByType[zone.Type]
			if not best or distance < best.Distance then
				nearestByType[zone.Type] = { Position = zone.Position, Distance = distance }
			end
		end
	end
	-- Alvo sem zona (chefe) ou inimigo vivo mais perto que a zona: o ícone vai no inimigo
	for _, enemy in enemies do
		if enemy.Type and killTargets[enemy.Type] and enemy.Root.Parent then
			local distance = (enemy.Root.Position - center).Magnitude
			local best = nearestByType[enemy.Type]
			if not best or distance < best.Distance then
				nearestByType[enemy.Type] = { Position = enemy.Root.Position, Distance = distance }
			end
		end
	end
	for _, target in nearestByType do
		placeObjective(take("Kill"), target.Position, true, true)
	end

	hideUnused()

	-- Norte na borda: a direção (0, 0, -1) do mundo vista no minimapa
	place(northLabel, Vector2.new(-forward.X, forward.Z).Unit * (RADIUS - 9))
end

-- Some junto com a HUD (árvore de habilidades aberta, tela de título...)
local function hudVisible()
	local hud = playerGui:FindFirstChild("HUD")
	return hud == nil or (hud:IsA("ScreenGui") and hud.Enabled)
end

local accumulated = 0
local nextZoneRefresh = 0
local drawConnection = RunService.Heartbeat:Connect(function(dt)
	accumulated += dt
	local interval = 1 / (if FastMode.IsEnabled() then FAST_MAP_RATE else MAP_RATE)
	if accumulated < interval then return end
	accumulated %= interval
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	holder.Visible = root ~= nil and hudVisible()
	if not holder.Visible then return end

	local clock = os.clock()
	if clock >= nextListRefresh then
		nextListRefresh = clock + LIST_REFRESH
		refreshEntities()
	end
	if clock >= nextZoneRefresh then
		nextZoneRefresh = clock + ZONE_REFRESH
		refreshZones()
	end

	center = root.Position
	forward = heading()
	right = Vector3.new(-forward.Z, 0, forward.X)
	local radiusStuds = ZOOMS[zoomIndex]
	scale = RADIUS / radiusStuds

	-- Mesma projecao dos simbolos: mapa e marcadores permanecem alinhados ao girar/andar.
	local rotation = -math.deg(math.atan2(forward.X, -forward.Z))
	local halfTile = Atlas.TileSize / 2
	for _, tile in mapTiles do
		local delta = tile.Center - center
		local dx = math.max(0, math.abs(delta.X) - halfTile)
		local dz = math.max(0, math.abs(delta.Z) - halfTile)
		local visible = dx * dx + dz * dz <= (radiusStuds + 2) ^ 2
		tile.Image.Visible = visible
		if visible then
			local point = project(tile.Center)
			tile.Image.Position = UDim2.new(0.5, point.X, 0.5, point.Y)
			tile.Image.Size = UDim2.fromOffset(Atlas.TileSize * scale, Atlas.TileSize * scale)
			tile.Image.Rotation = rotation
		end
	end

	-- Seta: para onde o personagem olha, em relação à câmera
	local look = root.CFrame.LookVector
	local flatLook = Vector3.new(look.X, 0, look.Z)
	if flatLook.Magnitude > 0.001 then
		flatLook = flatLook.Unit
		arrow.Rotation = math.deg(math.atan2(-flatLook:Dot(forward), flatLook:Dot(right))) + 90
	end

	draw()
end)

script.Destroying:Connect(function()
	drawConnection:Disconnect()
	questConnection:Disconnect()
	zoomConnection:Disconnect()
	screen:Destroy()
end)
