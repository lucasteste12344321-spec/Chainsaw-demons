-- Segurar Z/X pausa o gesto no marcador Aim. Soltar retoma a animacao e envia apenas o ponto desejado.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ContextActionService = game:GetService("ContextActionService")
local Remotes = require(ReplicatedStorage:WaitForChild("Remotes"))
local PathData = require(ReplicatedStorage:WaitForChild("PathData"))
local Config = require(ReplicatedStorage:WaitForChild("FoxDevilConfig"))
local player = Players.LocalPlayer
local Aim = {}
local active

-- Jogando de controle: a mira é o centro da tela (o mouse fica escondido e a posição dele não vale)
local function usingGamepad()
	return string.sub(UserInputService:GetLastInputType().Name, 1, 7) == "Gamepad"
end

-- Raio da câmera pela mira: mouse (posição sem o inset do topo: ViewportPointToRay) ou o centro da tela no controle
local function aimRay(camera)
	if usingGamepad() then
		local size = camera.ViewportSize
		return camera:ViewportPointToRay(size.X / 2, size.Y / 2)
	end
	local mouse = UserInputService:GetMouseLocation()
	return camera:ViewportPointToRay(mouse.X, mouse.Y)
end
function Aim.IsFox(slot)
	local skill = PathData.PlayerSkill(player, slot)
	return skill ~= nil and skill.FoxBite == true -- mordida do Kon (ContractData), em qualquer forma
end
local function cleanup(state, cancel)
	if active ~= state then return end
	active = nil
	if state.connection then state.connection:Disconnect() end
	if state.markerConnection then state.markerConnection:Disconnect() end
	if state.reticle then state.reticle:Destroy() end
	state.character:SetAttribute("FoxAiming", nil)
	if state.humanoid.Parent then state.humanoid.AutoRotate = state.autoRotate end
	ContextActionService:UnbindAction("KonAimCombatLock")
	if state.animation then state.animation:SetAttribute("AllowAimHold", nil) end
	if state.track then
		state.track:AdjustSpeed(1)
		if cancel then state.track:Stop(0.1) end
		local remaining = if cancel then 0.2 else math.max(0.25, math.max(state.track.Length, Config.AimDuration or 0) - state.track.TimePosition + 0.15)
		task.delay(remaining, function() state.track:Destroy(); state.animation:Destroy() end)
	elseif state.animation then
		state.animation:Destroy()
	end
end
local function release(state)
	if active ~= state or not state.target then return end
	if state.track then
		state.track.TimePosition = math.max(state.track.TimePosition, Config.AimHoldTime)
		state.track:AdjustSpeed(1)
	end
	Players.LocalPlayer:SetAttribute("PredictedRootUntil", workspace:GetServerTimeNow() + 0.4) -- parado já na hora
	Remotes.UsePower:FireServer(state.slot, state.target)
	cleanup(state, false)
end
function Aim.Cancel()
	if active then cleanup(active, true) end
end
function Aim.Release(slot)
	if active and active.slot == slot then
		active.released = true
		if os.clock() - active.started >= Config.AimHoldTime then release(active) end
	end
end
function Aim.Begin(slot)
	if active then return end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not humanoid or not root or humanoid.Health <= 0 then return end
	local state = {slot = slot, character = character, humanoid = humanoid, root = root, autoRotate = humanoid.AutoRotate, started = os.clock()}
	active = state
	character:SetAttribute("FoxAiming", true)
	humanoid.AutoRotate = false
	ContextActionService:BindActionAtPriority("KonAimCombatLock", function() return Enum.ContextActionResult.Sink end, false, 3000,
		Enum.UserInputType.MouseButton1, Enum.KeyCode.Z, Enum.KeyCode.X, Enum.KeyCode.C, Enum.KeyCode.F,
		Enum.KeyCode.ButtonR2, Enum.KeyCode.ButtonB, Enum.KeyCode.ButtonY, Enum.KeyCode.ButtonR1, Enum.KeyCode.ButtonL2)
	local animation = Instance.new("Animation")
	animation.AnimationId = Config.AimAnimation
	animation:SetAttribute("AllowAimHold", true)
	state.animation = animation
	local animator = humanoid:FindFirstChildOfClass("Animator")
	if animator then
		local ok, track = pcall(function() return animator:LoadAnimation(animation) end)
		if ok then
			state.track = track
			track.Priority = Enum.AnimationPriority.Action4
			state.markerConnection = track:GetMarkerReachedSignal(Config.AimMarker):Connect(function()
				if active == state and not state.released then track:AdjustSpeed(0) end
			end)
			track:Play(0.08)
		end
	end
	local ringTemplate = ReplicatedStorage:FindFirstChild("VFX")
	ringTemplate = ringTemplate and ringTemplate:FindFirstChild("GoblinKing")
	ringTemplate = ringTemplate and ringTemplate:FindFirstChild("ImpactRing")
	if ringTemplate then
		local reticle = ringTemplate:Clone()
		for _, child in reticle:GetChildren() do child:Destroy() end
		reticle.Name = "KonAimReticle"
		reticle.Anchored = true; reticle.CanCollide = false; reticle.CanQuery = false; reticle.CanTouch = false
		reticle.Material = Enum.Material.Neon; reticle.Color = Color3.fromRGB(255, 185, 61)
		reticle.Size = Vector3.new(1.3, 1.3, 0.025)
		reticle.Parent = workspace
		state.reticle = reticle
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local excluded = {character}
	if state.reticle then table.insert(excluded, state.reticle) end
	local effects = workspace:FindFirstChild("PowerEffects")
	if effects then table.insert(excluded, effects) end
	params.FilterDescendantsInstances = excluded
	params.RespectCanCollide = true
	state.connection = RunService.RenderStepped:Connect(function()
		if player.Character ~= character or not root.Parent or humanoid.Health <= 0 or character:GetAttribute("Stunned") or not Aim.IsFox(slot) then cleanup(state, true); return end
		local elapsed = os.clock() - state.started
		if elapsed > Config.MaxHoldTime then cleanup(state, true); return end
		local camera = workspace.CurrentCamera
		if not camera then return end
		local ray = aimRay(camera)
		local hit = workspace:Raycast(ray.Origin, ray.Direction * 500, params)
		local target = if hit then hit.Position + (if hit.Normal.Y > 0.5 then Vector3.new(0, 3, 0) else hit.Normal * 1.5) else ray.Origin + ray.Direction * Config.MaxAimDistance
		local offset = target - root.Position
		if offset.Magnitude > Config.MaxAimDistance then target = root.Position + offset.Unit * Config.MaxAimDistance end
		state.target = target
		if state.reticle then state.reticle.CFrame = CFrame.lookAt(target, camera.CFrame.Position) end
		local flat = Vector3.new(target.X, root.Position.Y, target.Z)
		if (flat - root.Position).Magnitude > 0.1 then root.CFrame = CFrame.lookAt(root.Position, flat) end
		if elapsed >= Config.AimHoldTime then
			if state.released then release(state); return end
			if state.track and state.track.TimePosition >= Config.AimHoldTime then
				state.track.TimePosition = Config.AimHoldTime
				state.track:AdjustSpeed(0)
			end
		end
	end)
end
-- Bote da Raposa (ContractData, Kind "FoxLunge"): sem segurar. Vira para o ponto mirado (mouse; no celular, para onde a
-- câmera olha), faz o gesto de invocação (trecho rápido da AimAnimation) e pede o poder com o ponto.
function Aim.IsLunge(slot)
	local skill = PathData.PlayerSkill(player, slot)
	return skill ~= nil and skill.Kind == "FoxLunge"
end

local function aimPoint(character, root)
	local camera = workspace.CurrentCamera
	if not camera then return nil end
	if UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then
		local look = camera.CFrame.LookVector
		local flat = Vector3.new(look.X, 0, look.Z)
		return if flat.Magnitude > 0.01 then root.Position + flat.Unit * 30 else nil
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local excluded = { character }
	local effects = workspace:FindFirstChild("PowerEffects")
	if effects then table.insert(excluded, effects) end
	params.FilterDescendantsInstances = excluded
	params.RespectCanCollide = true
	local ray = aimRay(camera)
	local hit = workspace:Raycast(ray.Origin, ray.Direction * 500, params)
	return if hit then hit.Position else ray.Origin + ray.Direction * Config.MaxAimDistance
end

function Aim.Cast(slot)
	if active then return end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not humanoid or not root or humanoid.Health <= 0 then return end
	local target = aimPoint(character, root)
	if target then
		local flat = Vector3.new(target.X, root.Position.Y, target.Z)
		if (flat - root.Position).Magnitude > 0.5 then
			root.CFrame = CFrame.lookAt(root.Position, flat)
		end
	end
	local animator = humanoid:FindFirstChildOfClass("Animator")
	if animator then
		local animation = Instance.new("Animation")
		animation.AnimationId = Config.AimAnimation
		local ok, track = pcall(function() return animator:LoadAnimation(animation) end)
		if ok and track then
			track.Priority = Enum.AnimationPriority.Action4
			track:Play(0.05, 1, Config.CastSpeed)
			track.TimePosition = Config.CastStart
			task.delay(Config.CastLength, function()
				track:Stop(0.25)
				task.delay(0.4, function()
					track:Destroy()
					animation:Destroy()
				end)
			end)
		else
			animation:Destroy()
		end
	end
	Players.LocalPlayer:SetAttribute("PredictedRootUntil", workspace:GetServerTimeNow() + 0.4) -- parado já na hora
	Remotes.UsePower:FireServer(slot, target)
end

UserInputService.WindowFocusReleased:Connect(Aim.Cancel)
player.CharacterRemoving:Connect(Aim.Cancel)
return Aim
