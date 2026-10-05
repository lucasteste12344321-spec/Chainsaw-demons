-- Contador do chefe global no lugar dele (pedido do usuário: "tem que ser no lugar que fica o boss"). Para cada chefe
-- global, o BossService publica no ReplicatedStorage: GlobalBoss_<Tipo> (os.time do próximo horário), GlobalBossPos_<Tipo>
-- (onde ele aparece), GlobalBossTitle_<Tipo> e GlobalBossActive_<Tipo>. Aqui uma placa flutua em cima desse ponto,
-- vista de longe: "DENJI · aparece em 1h 42min" e, com ele no mapa, "DENJI ESTÁ AQUI!" piscando.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local UI = require(ReplicatedStorage:WaitForChild("UITheme"))

local HEIGHT = 14 -- studs acima do ponto onde o chefe aparece
local MAX_DISTANCE = 700

local beacons = {} -- [tipo] = { Part, Title, Timer }

local function beaconFor(bossType)
	if beacons[bossType] then return beacons[bossType] end
	local part = Instance.new("Part")
	part.Name = "BossBeacon_" .. bossType
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Transparency = 1
	part.Size = Vector3.one
	part.Parent = workspace
	local billboard = UI.new("BillboardGui", { Parent = part, Size = UDim2.fromOffset(260, 74), MaxDistance = MAX_DISTANCE,
		LightInfluence = 0, AlwaysOnTop = false })
	local frame = UI.new("Frame", { Parent = billboard, Size = UDim2.fromScale(1, 1), BackgroundColor3 = UI.Colors.Black,
		BackgroundTransparency = 0.35, BorderSizePixel = 0 })
	UI.corner(frame, UDim.new(0, 10))
	local stroke = UI.stroke(frame, UI.Colors.Accent, 2, 0.1)
	local title = UI.label({ Parent = frame, Position = UDim2.fromOffset(0, 6), Size = UDim2.new(1, 0, 0, 30), TextSize = 24,
		Font = UI.Fonts.Display, TextXAlignment = Enum.TextXAlignment.Center })
	local timer = UI.label({ Parent = frame, Position = UDim2.fromOffset(0, 38), Size = UDim2.new(1, 0, 0, 26), TextSize = 16,
		Font = UI.Fonts.Title, TextXAlignment = Enum.TextXAlignment.Center })
	beacons[bossType] = { Part = part, Title = title, Timer = timer, Stroke = stroke }
	return beacons[bossType]
end

local function formatTime(seconds)
	seconds = math.max(0, math.floor(seconds))
	local hours = math.floor(seconds / 3600)
	local minutes = math.floor(seconds % 3600 / 60)
	if hours > 0 then return `{hours}h {minutes}min` end
	return string.format("%d:%02d", minutes, seconds % 60)
end

local blink = false
while true do
	blink = not blink
	for name, nextAt in ReplicatedStorage:GetAttributes() do
		local bossType = string.match(name, "^GlobalBoss_(.+)$")
		local position = bossType and ReplicatedStorage:GetAttribute("GlobalBossPos_" .. bossType)
		if bossType and type(nextAt) == "number" and typeof(position) == "Vector3" then
			local beacon = beaconFor(bossType)
			beacon.Part.Position = position + Vector3.new(0, HEIGHT, 0)
			local bossTitle = ReplicatedStorage:GetAttribute("GlobalBossTitle_" .. bossType) or bossType
			beacon.Title.Text = string.upper(bossTitle)
			if ReplicatedStorage:GetAttribute("GlobalBossActive_" .. bossType) == true then
				beacon.Timer.Text = "IS HERE!"
				beacon.Timer.TextColor3 = if blink then UI.Colors.Accent else UI.Colors.Text
				beacon.Stroke.Color = if blink then UI.Colors.Accent else UI.Colors.White
			else
				beacon.Timer.Text = `shows up in {formatTime(nextAt - workspace:GetServerTimeNow())}`
				beacon.Timer.TextColor3 = UI.Colors.TextDim
				beacon.Stroke.Color = UI.Colors.Accent
			end
		end
	end
	task.wait(0.5)
end
