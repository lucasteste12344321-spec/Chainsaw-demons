-- Pacote visual da Katana. O Claude controla ataques, alvos e remotes; este modulo nao causa dano.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
local VFX = {}
VFX.__index = VFX
local WHITE = Color3.fromRGB(240, 249, 255)
local RED = Color3.fromRGB(240, 31, 52)
local INK = Color3.fromRGB(17, 11, 22)
local function tween(object, duration, properties)
	local t = TweenService:Create(object, TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), properties)
	t:Play()
	return t
end
local function rootOf(character)
	return typeof(character) == "Instance" and character:IsA("Model") and character:FindFirstChild("HumanoidRootPart") or nil
end
local function noCollision(part)
	part.Anchored = true
	part.CanCollide, part.CanTouch, part.CanQuery, part.CastShadow = false, false, false, false
end
function VFX.new(fastMode)
	local self = setmetatable({}, VFX)
	self.fastMode = fastMode or function() return false end
	self.random = Random.new()
	self.groups = {}
	self.bindings = {}
	self.folder = Instance.new("Folder")
	self.folder.Name = "KatanaVisuals"
	self.folder.Parent = workspace
	return self
end
function VFX:Group(character, kind, life)
	if #self.groups >= 24 then self.groups[1].Cancel() end
	local folder = Instance.new("Folder")
	folder.Name = kind
	folder.Parent = self.folder
	local group = {Folder = folder, Character = character, Kind = kind}
	function group.Cancel()
		if group.Closed then return end
		group.Closed = true
		if group.Connection then group.Connection:Disconnect() end
		local i = table.find(self.groups, group)
		if i then table.remove(self.groups, i) end
		folder:Destroy()
	end
	table.insert(self.groups, group)
	task.delay(life, group.Cancel)
	Debris:AddItem(folder, life + 0.1)
	return group
end
function VFX:Cancel(character, kind)
	for i = #self.groups, 1, -1 do
		local group = self.groups[i]
		if group.Character == character and (not kind or group.Kind == kind) then group.Cancel() end
	end
end
function VFX:Mesh(group, name, cf, size, color, alpha)
	local assets = ReplicatedStorage:FindFirstChild("VFX")
	assets = assets and assets:FindFirstChild("Katana")
	local template = assets and assets:FindFirstChild(name)
	if not template or not template:IsA("BasePart") then return nil end
	local part = template:Clone()
	noCollision(part)
	part.Size, part.CFrame, part.Color = size, cf, color
	part.Material = if color == INK then Enum.Material.SmoothPlastic else Enum.Material.Neon
	part.Transparency = alpha or 0
	part.Parent = group.Folder
	return part
end
function VFX:Anchor(group, cf)
	local part = Instance.new("Part")
	noCollision(part)
	part.Name = "EmissionOrigin"
	part.Transparency = 1
	part.Size = Vector3.one * 0.1
	part.CFrame = cf
	part.Parent = group.Folder
	return part
end
function VFX:Ring(group, cf, diameter, color, life, start)
	local part = self:Mesh(group, "PressureRing", cf, Vector3.new(start or 0.8, start or 0.8, 0.035), color, 0.08)
	if part then tween(part, life, {Size = Vector3.new(diameter, diameter, 0.025), Transparency = 1}) end
	return part
end
function VFX:Sparks(group, cf, count, speed)
	local anchor = self:Anchor(group, cf)
	local p = Instance.new("ParticleEmitter")
	p.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	p.Rate = 0
	p.LightEmission, p.LightInfluence, p.Brightness = 1, 0, 3
	p.Color = ColorSequence.new(WHITE, RED)
	p.Lifetime = NumberRange.new(0.16, 0.42)
	p.Speed = NumberRange.new(speed * 0.5, speed)
	p.EmissionDirection = Enum.NormalId.Front
	p.SpreadAngle = Vector2.new(55, 55)
	p.Drag = 6
	p.Acceleration = Vector3.new(0, -12, 0)
	p.Size = NumberSequence.new({NumberSequenceKeypoint.new(0, 0.15), NumberSequenceKeypoint.new(1, 0)})
	p.Parent = anchor
	p:Emit(if self.fastMode() then math.ceil(count / 3) else count)
end
function VFX:Flash(group, cf, size)
	local part = self:Mesh(group, "SteelFlash", cf, Vector3.new(size, size, 0.025), WHITE)
	if part then tween(part, 0.18, {Size = Vector3.new(size * 1.6, size * 1.6, 0.025), Transparency = 1}) end
	if self.fastMode() then return end
	local anchor = self:Anchor(group, cf)
	local light = Instance.new("PointLight")
	light.Color, light.Range, light.Brightness = RED, 14, 2.5
	light.Shadows = false
	light.Parent = anchor
	tween(light, 0.2, {Brightness = 0})
end
function VFX:Dust(group, cf, character)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local excluded = {self.folder}
	if character then table.insert(excluded, character) end
	params.FilterDescendantsInstances = excluded
	params.RespectCanCollide = true
	local hit = workspace:Raycast(cf.Position, Vector3.new(0, -6, 0), params)
	if not hit then return end
	local anchor = self:Anchor(group, CFrame.new(hit.Position + hit.Normal * 0.15))
	local dust = Instance.new("ParticleEmitter")
	dust.Texture = "rbxasset://textures/particles/smoke_main.dds"
	dust.Color = ColorSequence.new(Color3.fromRGB(171, 165, 164))
	dust.Rate = 0
	dust.Lifetime = NumberRange.new(0.3, 0.6)
	dust.Speed = NumberRange.new(2, 6)
	dust.SpreadAngle = Vector2.new(80, 80)
	dust.Drag = 5
	dust.Size = NumberSequence.new({NumberSequenceKeypoint.new(0, 0.7), NumberSequenceKeypoint.new(1, 3)})
	dust.Transparency = NumberSequence.new({NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 1)})
	dust.Rotation = NumberRange.new(0, 360)
	dust.Parent = anchor
	dust:Emit(if self.fastMode() then 4 else 10)
end
function VFX:Slash(group, cf, diameter, horizontal)
	local plane = cf * CFrame.Angles(if horizontal then math.rad(72) else 0, 0, if horizontal then 0 else math.rad(-38))
	local life = if horizontal then 0.35 else 0.25
	for i = 1, (if self.fastMode() then 2 else 3) do
		local size = diameter * (if i == 1 then 1.1 elseif i == 2 then 1 else 0.98)
		local color = if i == 1 then RED elseif i == 2 then INK else WHITE
		if self.fastMode() and i == 2 then color = WHITE end
		local part = self:Mesh(group, if i == 3 then "ThinCrescent" else "CutCrescent", plane * CFrame.new(0, 0, -i * 0.035), Vector3.new(size, size * 0.78, 0.055), color, if i == 1 then 0.12 else 0)
		if part then tween(part, life, {Size = part.Size * 1.22, CFrame = part.CFrame * CFrame.Angles(0, 0, math.rad(48)), Transparency = 1}) end
	end
	self:Flash(group, cf, if horizontal then 2.1 else 1.3)
	self:Sparks(group, cf, if horizontal then 24 else 16, if horizontal then 23 else 17)
end
function VFX:Follow(group, part, duration, callback)
	local started = os.clock()
	group.Connection = RunService.RenderStepped:Connect(function(dt)
		local elapsed = os.clock() - started
		if group.Closed then return end
		if elapsed > duration then group.Connection:Disconnect(); group.Connection = nil; return end
		if not part.Parent or (group.Character and group.Character:GetAttribute("Stunned")) then group.Cancel(); return end
		callback(elapsed, dt, part.CFrame)
	end)
end
function VFX:Play(skill, phase, data)
	if self.destroyed or type(data) ~= "table" then return nil end
	local character = data.Character
	if phase == "Cancel" or phase == "End" then self:Cancel(character); return nil end
	local root = rootOf(character)
	local cf = if typeof(data.Origin) == "CFrame" then data.Origin else root and root.CFrame
	if not cf then return nil end
	local camera = workspace.CurrentCamera
	if camera and (camera.CFrame.Position - cf.Position).Magnitude > (if self.fastMode() then 130 else 220) then return nil end
	local targetRoot = rootOf(data.Target)
	local contact = if typeof(data.HitPosition) == "Vector3" then data.HitPosition else targetRoot and targetRoot.Position
	if skill == "Z" and phase == "Dash" then
		self:Cancel(character, "Dash")
		local g = self:Group(character, "Dash", 0.75)
		self:Ring(g, cf * CFrame.new(0, 0, 0.6), 7, WHITE, 0.25)
		self:Dust(g, cf, character)
		local last = -1
		local function streaks(t, _, current)
			if t - last < (if self.fastMode() then 0.085 else 0.035) then return end
			last = t
			for _ = 1, (if self.fastMode() then 1 else 3) do
				local x, y = self.random:NextNumber(-2, 2), self.random:NextNumber(-1.7, 1.7)
				local p = self:Mesh(g, "SpeedShard", current * CFrame.new(x, y, 1) * CFrame.Angles(math.pi / 2, 0, 0), Vector3.new(0.13, self.random:NextNumber(3, 6), 0.025), if x > 0 then WHITE else RED, 0.1)
				if p then tween(p, 0.19, {CFrame = p.CFrame + current.LookVector * -3, Transparency = 1}) end
			end
		end
		streaks(0, 0, cf)
		if root then self:Follow(g, root, 0.23, streaks) end
		return g.Cancel
	elseif skill == "Z" and phase == "Slash" then
		self:Cancel(character, "Dash")
		local g = self:Group(character, "AdvanceCut", 0.85)
		self:Slash(g, cf * CFrame.new(0, 0.3, -3.2), 7.5, false)
		self:Ring(g, cf * CFrame.new(0, 0, -3), 8.5, RED, 0.32)
		return g.Cancel
	elseif skill == "X" and phase == "Reach" then
		local g = self:Group(character, "Reach", 0.4)
		self:Ring(g, cf * CFrame.new(-0.4, 0.3, -2), 2.8, WHITE, 0.2)
		return g.Cancel
	elseif skill == "X" and phase == "Grab" then
		if not contact then return nil end -- somente depois do agarrao confirmado
		self:Cancel(character, "Grab")
		local g = self:Group(character, "Grab", 0.8)
		local pos = CFrame.new(contact) * cf.Rotation
		local ring = self:Mesh(g, "PressureRing", pos, Vector3.new(4.2, 4.2, 0.04), RED, 0.05)
		if ring then tween(ring, 0.15, {Size = Vector3.new(2.2, 2.2, 0.03), Transparency = 0.45}) end
		self:Flash(g, pos, 1.5)
		self:Sparks(g, pos, 16, 13)
		if targetRoot and ring then
			self:Follow(g, targetRoot, 0.5, function(t, _, current)
				ring.CFrame = CFrame.new(current.Position) * cf.Rotation * CFrame.Angles(0, 0, t * 5)
			end)
		end
		return g.Cancel
	elseif skill == "X" and phase == "Strike" then
		if not contact then return nil end
		self:Cancel(character, "Grab")
		local g = self:Group(character, "GrabCut", 0.8)
		local pos = CFrame.new(contact) * cf.Rotation
		self:Slash(g, pos, 5.2, false)
		self:Ring(g, pos, 6, WHITE, 0.22)
		return g.Cancel
	elseif skill == "X" and phase == "Release" then
		self:Cancel(character, "Grab")
	elseif skill == "C" and phase == "Charge" then
		self:Cancel(character, "Charge")
		local g = self:Group(character, "Charge", 0.65)
		local flash = self:Mesh(g, "SteelFlash", cf * CFrame.new(-1.05, -0.5, -0.3), Vector3.new(0.3, 0.3, 0.03), WHITE)
		if flash then tween(flash, 0.22, {Size = Vector3.new(1.8, 1.8, 0.025)}) end
		if root and flash then self:Follow(g, root, 0.28, function(t, _, current) flash.CFrame = current * CFrame.new(-1.05, -0.5, -0.3) * CFrame.Angles(0, 0, t * 2) end) end
		self:Sparks(g, cf * CFrame.new(-1.05, -0.5, -0.3), 6, 4)
		return g.Cancel
	elseif skill == "C" and phase == "Slash" then
		self:Cancel(character, "Charge")
		local g = self:Group(character, "DrawCut", 1)
		self:Slash(g, cf * CFrame.new(0, 0, -2.8), 13, true)
		self:Dust(g, cf, character)
		self:Ring(g, cf * CFrame.new(0, 0, -3), 11, WHITE, 0.3)
		if not self.fastMode() then
			task.delay(0.055, function()
				if g.Closed then return end
				local line = self:Mesh(g, "ThinCrescent", cf * CFrame.new(0, 0, -3.4) * CFrame.Angles(math.rad(76), 0, math.rad(-12)), Vector3.new(15, 10, 0.03), RED, 0.2)
				if line then tween(line, 0.3, {Transparency = 1, Size = line.Size * 1.18}) end
			end)
		end
		return g.Cancel
	elseif skill == "C" and phase == "Sheathe" then
		local g = self:Group(character, "Sheathe", 0.35)
		self:Flash(g, cf * CFrame.new(-1.05, -0.5, -0.3), 0.65)
		return g.Cancel
	end
	return nil
end
function VFX:BindTrack(track, skill, context)
	local connections = {}
	local effects = {}
	local closed = false
	local function close()
		if closed then return end
		closed = true
		for _, connection in connections do connection:Disconnect() end
		for _, cancel in effects do cancel() end
		self.bindings[close] = nil
	end
	if self.destroyed then return close end
	self.bindings[close] = true
	for _, phase in {"Dash", "Slash", "Reach", "Grab", "Strike", "Release", "Charge", "Sheathe"} do
		table.insert(connections, track:GetMarkerReachedSignal(phase):Connect(function()
			local data = context()
			if data then
				local cancel = self:Play(skill, phase, data)
				if cancel then table.insert(effects, cancel) end
			end
		end))
	end
	table.insert(connections, track.Stopped:Connect(close))
	return close
end
function VFX:Destroy()
	if self.destroyed then return end
	self.destroyed = true
	local bindings = {}
	for close in self.bindings do table.insert(bindings, close) end
	for _, close in bindings do close() end
	for i = #self.groups, 1, -1 do self.groups[i].Cancel() end
	self.folder:Destroy()
end
return VFX
