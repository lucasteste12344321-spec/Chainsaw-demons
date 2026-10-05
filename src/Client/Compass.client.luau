-- Refines the authored StarterGui.Compass; the old nested LocalScript is disabled in Edit.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local RS = game:GetService("ReplicatedStorage")
local UI = require(RS:WaitForChild("UITheme"))
local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local gui = playerGui:WaitForChild("Compass", 15)
if not gui then warn("[Compass] StarterGui.Compass is missing"); return end
gui.ResetOnSpawn = false
local frame = gui:WaitForChild("Compass")
local legacy = frame:FindFirstChildOfClass("LocalScript")
if legacy then legacy.Enabled = false end
frame.AnchorPoint = Vector2.new(.5, 0)
frame.Position = UDim2.new(.5, 0, 0, 4)
frame.Size = UDim2.fromOffset(360, 46)
frame.BackgroundColor3 = UI.Colors.Panel
frame.BackgroundTransparency = .25
frame.BorderSizePixel = 0
frame.ClipsDescendants = true
local gradient = frame:FindFirstChildOfClass("UIGradient")
if gradient then gradient.Enabled = false end
local oldArrow = frame:FindFirstChild("Arrow")
if oldArrow then oldArrow.Visible = false end
UI.corner(frame, UDim.new(0, 5))
local directions = {{"N", 0}, {"NE", 45}, {"E", 90}, {"SE", 135}, {"S", 180}, {"SW", 225}, {"W", 270}, {"NW", 315}}
local units, ticks = {}, {}
for _, info in directions do
	local label = frame:FindFirstChild(info[1])
	if label and label:IsA("TextLabel") then
		label.AnchorPoint = Vector2.new(.5, 0); label.Size = UDim2.fromOffset(28, 17)
		label.TextScaled = false; label.Font = UI.Fonts.Title
		label.TextSize = if info[2] % 90 == 0 then 13 else 10
		label.TextColor3 = if info[1] == "N" then UI.Colors.Accent else UI.Colors.Text
		label.TextStrokeTransparency = .7
		label.ZIndex = 3; table.insert(units, {Label = label, Bearing = info[2]})
	end
end
for bearing = 0, 355, 5 do
	local tick = UI.new("Frame", {Name = "Tick" .. bearing, Parent = frame, AnchorPoint = Vector2.new(.5, 0),
		Size = UDim2.fromOffset(1, if bearing % 15 == 0 then 6 else 3), BorderSizePixel = 0,
		BackgroundColor3 = UI.Colors.TextDim, ZIndex = 2})
	table.insert(ticks, {Frame = tick, Bearing = bearing})
end
UI.label({Name = "CenterPointer", Parent = frame, Position = UDim2.new(.5, -5, 0, -4),
	Size = UDim2.fromOffset(10, 12), Text = "▼", Font = UI.Fonts.Title, TextSize = 10,
	TextXAlignment = Enum.TextXAlignment.Center, TextColor3 = UI.Colors.Gold, ZIndex = 5})
local degrees = UI.label({Name = "Degrees", Parent = frame, Position = UDim2.fromOffset(8, 28),
	Size = UDim2.fromOffset(40, 13), TextSize = 10, Font = UI.Fonts.Number, TextColor3 = UI.Colors.TextDim, ZIndex = 4})
local destination = UI.label({Name = "Destination", Parent = frame, Position = UDim2.fromOffset(50, 28),
	Size = UDim2.new(1, -58, 0, 13), TextSize = 10, TextColor3 = UI.Colors.Gold,
	TextXAlignment = Enum.TextXAlignment.Center, TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 4})
local marker = UI.label({Name = "DestinationMarker", Parent = frame, AnchorPoint = Vector2.new(.5, 0),
	Size = UDim2.fromOffset(14, 14), Text = "◆", TextSize = 11, TextColor3 = UI.Colors.Gold,
	TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 5, Visible = false})

local function wrap(degreesValue) return (degreesValue + 180) % 360 - 180 end
local currentBearing
local previousCamera
local lastWidth = 0
local textAt = 0
local binding = "ChainsawHorizontalCompass"
RunService:BindToRenderStep(binding, Enum.RenderPriority.Camera.Value + 2, function(dt)
	local camera = workspace.CurrentCamera
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	local hud = playerGui:FindFirstChild("HUD")
	local visible = camera ~= nil and root ~= nil and not player:GetAttribute("MenuOpen") and (not hud or hud.Enabled)
	frame.Visible = visible
	if not visible or not gui.Enabled then return end
	local viewport = camera.ViewportSize
	local width = math.clamp(viewport.X * .36, 220, 420)
	if width ~= lastWidth then frame.Size = UDim2.fromOffset(width, 46); lastWidth = width end
	-- In portrait, stay below the top-right map and its navigation card.
	frame.Position = UDim2.new(.5, 0, 0, if viewport.X < 600 and viewport.Y > viewport.X then 202 else 4)
	local look = camera.CFrame.LookVector
	if look.X * look.X + look.Z * look.Z > .0025 then
		local desired = math.deg(math.atan2(look.X, -look.Z)) % 360
		if currentBearing == nil or camera ~= previousCamera then currentBearing = desired
		else currentBearing = (currentBearing + wrap(desired - currentBearing) * (1 - math.exp(-14 * math.min(dt, .25)))) % 360 end
	end
	currentBearing = currentBearing or 0; previousCamera = camera
	local function project(bearing)
		local delta = wrap(bearing - currentBearing)
		return .5 + delta / 180, math.abs(delta), delta
	end
	for _, unit in units do
		local x, angle = project(unit.Bearing)
		unit.Label.Visible = angle < 87
		if unit.Label.Visible then
			unit.Label.Position = UDim2.new(x, 0, 0, 5)
			unit.Label.TextTransparency = math.clamp((angle - 62) / 30, 0, .85)
		end
	end
	for _, tick in ticks do
		local x, angle = project(tick.Bearing)
		tick.Frame.Visible = angle < 87
		if tick.Frame.Visible then
			tick.Frame.Position = UDim2.new(x, 0, 0, 21)
			tick.Frame.BackgroundTransparency = math.clamp((angle - 55) / 35, .2, .9)
		end
	end
	local map = playerGui:FindFirstChild("Minimap")
	local position = map and map:GetAttribute("NavigationPosition")
	marker.Visible = typeof(position) == "Vector3"
	if marker.Visible then
		local offset = position - root.Position
		local bearing = math.deg(math.atan2(offset.X, -offset.Z)) % 360
		local x, angle, delta = project(bearing)
		marker.Position = UDim2.new(math.clamp(x, .035, .965), 0, 0, 14)
		marker.Text = if angle <= 84 then "◆" elseif delta < 0 then "‹" else "›"
	end
	if os.clock() >= textAt then
		textAt = os.clock() + .1
		degrees.Text = string.format("%03d°", math.floor(currentBearing + .5) % 360)
		destination.Text = if marker.Visible then map:GetAttribute("NavigationName") or "" else ""
	end
end)
script.Destroying:Connect(function() RunService:UnbindFromRenderStep(binding) end)
