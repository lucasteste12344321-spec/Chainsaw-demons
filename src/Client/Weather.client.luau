-- Clima por área (só no cliente): neve caindo em volta da câmera, névoa mais fechada e a cor da tela mais fria
-- enquanto o jogador está dentro de uma zona de clima, com transição suave ao entrar e sair.
-- Zonas: Parts na pasta workspace.WeatherZones (ou com a tag "WeatherZone"), do tamanho da área, em qualquer rotação.
-- O tipo vem do atributo Weather ("Snow" ou "Rain") ou do nome da Part ("Neve"/"Snow", "Chuva"/"Rain"). Atributo
-- opcional Intensity (padrão 1). As Parts ficam invisíveis e sem colisão sozinhas (aqui no cliente).
-- Os flocos ficam em workspace.CombatFX (o Fast Mode não desliga, mas aqui caem menos com ele ligado).
local CollectionService = game:GetService("CollectionService")
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local FastMode = require(script.Parent:WaitForChild("FastMode"))

local FADE_TIME = 2.5 -- entrar e sair da área
local CHECK_INTERVAL = 0.5 -- confere em que zona está
local EMITTER_HEIGHT = 28 -- a "nuvem" que solta os flocos fica isso acima da câmera
local EMITTER_SIZE = 90 -- largura da área com flocos em volta da câmera
local FAST_RATE = 0.35 -- com o Fast Mode, cai só essa fração

local WEATHERS = {
	Snow = {
		Names = { "neve", "snow" },
		Rate = 220,
		Particle = {
			Texture = "rbxasset://textures/particles/smoke_main.dds",
			Color = ColorSequence.new(Color3.fromRGB(255, 255, 255)),
			Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.22), NumberSequenceKeypoint.new(1, 0.16) }),
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 1),
				NumberSequenceKeypoint.new(0.1, 0.1),
				NumberSequenceKeypoint.new(0.85, 0.15),
				NumberSequenceKeypoint.new(1, 1),
			}),
			Lifetime = NumberRange.new(5, 7),
			Speed = NumberRange.new(5, 8),
			SpreadAngle = Vector2.new(25, 25),
			Rotation = NumberRange.new(0, 360),
			RotSpeed = NumberRange.new(-40, 40),
			Acceleration = Vector3.new(1.5, -1, 0.5), -- vento leve
			LightEmission = 0.2,
			LightInfluence = 0.6,
		},
		-- Névoa (Atmosphere do Lighting, se tiver) e cor da tela
		Atmosphere = { Density = 0.45, Haze = 2.2, Color = Color3.fromRGB(215, 225, 240) },
		ColorCorrection = { TintColor = Color3.fromRGB(225, 235, 255), Saturation = -0.2, Brightness = 0.03 },
	},
	Rain = {
		Names = { "chuva", "rain" },
		Rate = 420,
		Particle = {
			Texture = "rbxasset://textures/particles/sparkles_main.dds",
			Color = ColorSequence.new(Color3.fromRGB(190, 205, 230)),
			Size = NumberSequence.new(0.08),
			Squash = NumberSequence.new(-3), -- gota comprida
			Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.4), NumberSequenceKeypoint.new(1, 0.6) }),
			Lifetime = NumberRange.new(0.9, 1.2),
			Speed = NumberRange.new(55, 65),
			SpreadAngle = Vector2.new(4, 4),
			Rotation = NumberRange.new(0, 0),
			RotSpeed = NumberRange.new(0, 0),
			Acceleration = Vector3.new(0, -20, 0),
			LightEmission = 0.1,
			LightInfluence = 0.8,
			Orientation = Enum.ParticleOrientation.VelocityParallel,
		},
		Atmosphere = { Density = 0.4, Haze = 1.6, Color = Color3.fromRGB(170, 180, 195) },
		ColorCorrection = { TintColor = Color3.fromRGB(215, 222, 235), Saturation = -0.25, Brightness = -0.04 },
	},
}

-- ================= Zonas =================

local zones = {} -- [Part] = true

local function weatherOf(part)
	local attribute = part:GetAttribute("Weather")
	if type(attribute) == "string" and WEATHERS[attribute] then
		return attribute
	end
	local name = string.lower(part.Name)
	for kind, weather in WEATHERS do
		for _, word in weather.Names do
			if string.find(name, word, 1, true) then
				return kind
			end
		end
	end
	return nil
end

local function addZone(part)
	if not part:IsA("BasePart") or zones[part] then return end
	zones[part] = true
	part.Transparency = 1
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Destroying:Once(function()
		zones[part] = nil
	end)
end

local function watchFolder(folder)
	for _, descendant in folder:GetDescendants() do
		addZone(descendant)
	end
	folder.DescendantAdded:Connect(addZone)
end

task.spawn(function()
	local folder = workspace:WaitForChild("WeatherZones", 30)
	if folder then
		watchFolder(folder)
	end
end)
for _, part in CollectionService:GetTagged("WeatherZone") do
	addZone(part)
end
CollectionService:GetInstanceAddedSignal("WeatherZone"):Connect(addZone)

local function inside(part, position)
	local offset = part.CFrame:PointToObjectSpace(position)
	local half = part.Size / 2
	return math.abs(offset.X) <= half.X and math.abs(offset.Y) <= half.Y + 40 and math.abs(offset.Z) <= half.Z
end

-- Zona onde a posição está agora: (tipo, intensidade) ou nil
local function zoneAt(position)
	for part in zones do
		if part.Parent and inside(part, position) then
			local kind = weatherOf(part)
			if kind then
				local intensity = part:GetAttribute("Intensity")
				return kind, if type(intensity) == "number" then intensity else 1
			end
		end
	end
	return nil
end

-- ================= Efeitos =================

local function effectsFolder()
	local folder = workspace:FindFirstChild("CombatFX")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "CombatFX"
		folder.Parent = workspace
	end
	return folder
end

-- Uma "nuvem" por tipo de clima: Part invisível em cima da câmera, soltando partículas para baixo
local clouds = {} -- [tipo] = { Part, Emitter }
local function cloudFor(kind)
	if clouds[kind] then return clouds[kind] end
	local weather = WEATHERS[kind]
	local part = Instance.new("Part")
	part.Name = "Weather" .. kind
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Transparency = 1
	part.Size = Vector3.new(EMITTER_SIZE, 1, EMITTER_SIZE)
	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = "Weather"
	emitter.EmissionDirection = Enum.NormalId.Bottom
	emitter.Shape = Enum.ParticleEmitterShape.Box
	emitter.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
	emitter.Rate = 0
	emitter.LockedToPart = false
	for property, value in weather.Particle do
		emitter[property] = value
	end
	emitter.Parent = part
	part.Parent = effectsFolder()
	clouds[kind] = { Part = part, Emitter = emitter }
	return clouds[kind]
end

local colorCorrection = Instance.new("ColorCorrectionEffect")
colorCorrection.Name = "WeatherColor"
colorCorrection.Enabled = true
colorCorrection.Parent = Lighting

local savedAtmosphere = nil -- valores do Lighting antes de entrar na zona
local current, currentIntensity = nil, 0

local function tween(instance, goals)
	TweenService:Create(instance, TweenInfo.new(FADE_TIME, Enum.EasingStyle.Sine), goals):Play()
end

local function rateFor(kind, intensity)
	local rate = WEATHERS[kind].Rate * intensity
	return if FastMode.IsEnabled() then rate * FAST_RATE else rate
end

local function setWeather(kind, intensity)
	if kind == current and intensity == currentIntensity then return end
	-- Para o clima anterior (os flocos que já caíram terminam de cair)
	for otherKind, cloud in clouds do
		if otherKind ~= kind then
			cloud.Emitter.Rate = 0
		end
	end
	current, currentIntensity = kind, intensity

	local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
	if kind then
		local weather = WEATHERS[kind]
		cloudFor(kind).Emitter.Rate = rateFor(kind, intensity)
		if atmosphere then
			savedAtmosphere = savedAtmosphere
				or { Instance = atmosphere, Density = atmosphere.Density, Haze = atmosphere.Haze, Color = atmosphere.Color }
			tween(atmosphere, weather.Atmosphere)
		end
		tween(colorCorrection, weather.ColorCorrection)
	else
		if savedAtmosphere and savedAtmosphere.Instance.Parent then
			tween(savedAtmosphere.Instance, {
				Density = savedAtmosphere.Density, Haze = savedAtmosphere.Haze, Color = savedAtmosphere.Color,
			})
		end
		savedAtmosphere = nil
		tween(colorCorrection, { TintColor = Color3.new(1, 1, 1), Saturation = 0, Brightness = 0 })
	end
end

FastMode.Changed:Connect(function()
	if current and clouds[current] then
		clouds[current].Emitter.Rate = rateFor(current, currentIntensity)
	end
end)

-- Zona: confere a cada CHECK_INTERVAL pela posição do personagem (ou da câmera, sem personagem)
task.spawn(function()
	while true do
		task.wait(CHECK_INTERVAL)
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local camera = workspace.CurrentCamera
		local position = if root then root.Position elseif camera then camera.CFrame.Position else nil
		-- Menu principal aberto: sem clima (a câmera do menu fica em outro lugar)
		if position and player:GetAttribute("MenuOpen") ~= true then
			setWeather(zoneAt(position))
		else
			setWeather(nil)
		end
	end
end)

-- A nuvem acompanha a câmera (um pouco à frente, para os flocos aparecerem onde se olha)
RunService.RenderStepped:Connect(function()
	if not current then return end
	local cloud = clouds[current]
	local camera = workspace.CurrentCamera
	if not cloud or not camera then return end
	local look = camera.CFrame.LookVector
	local ahead = Vector3.new(look.X, 0, look.Z) * 12
	cloud.Part.CFrame = CFrame.new(camera.CFrame.Position + ahead + Vector3.new(0, EMITTER_HEIGHT, 0))
end)
