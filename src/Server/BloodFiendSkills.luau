-- Chamado pelo PathSkills APOS validar caminho, custo e cooldown. Nao conecta remotes.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Remotes = require(ReplicatedStorage:WaitForChild("Remotes"))
local Config = require(ReplicatedStorage:WaitForChild("BloodFiendConfig"))
local Rules = require(script.Parent:WaitForChild("CombatRules"))
local State = require(script.Parent:WaitForChild("CombatState"))
local BloodFiendSkills = {}
local serial = 0

function BloodFiendSkills.Handles(id)
	return id == "LancaSangue" or id == "MarteloSangue"
end

local function fx(ctx, phase, extra)
	local data = extra or {}
	data.Phase = phase
	data.Character = ctx.Character
	data.SkillId = ctx.Skill.Id
	data.CastId = ctx.BloodCastId
	data.StartTime = ctx.BloodStartTime
	Remotes.CombatFX:FireAllClients("BloodFiend", data)
end

local function alive(ctx)
	return ctx.Player.Character == ctx.Character and ctx.Character.Parent ~= nil
		and ctx.Root.Parent ~= nil and ctx.Humanoid.Health > 0
		and ctx.Character:GetAttribute("Stunned") ~= true
end

local function waitUntil(ctx, when)
	while workspace:GetServerTimeNow() < when do
		if not alive(ctx) then return false end
		RunService.Heartbeat:Wait()
	end
	return alive(ctx)
end

local function clear(from, to, params)
	local delta = to - from
	return delta.Magnitude < 0.01 or workspace:Raycast(from, delta, params) == nil
end

local function targets(ctx, position, radius)
	local found, seen = {}, {}
	for _, part in workspace:GetPartBoundsInRadius(position, radius, ctx.Overlap) do
		local model = part:FindFirstAncestorOfClass("Model")
		while model and not model:FindFirstChildOfClass("Humanoid") do model = model:FindFirstAncestorOfClass("Model") end
		if model and not seen[model] then
			seen[model] = true
			local hum = model:FindFirstChildOfClass("Humanoid")
			local root = model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart
			if hum and hum.Health > 0 and root and root:IsA("BasePart") and Rules.CanDamage(ctx.Player, model) then
				table.insert(found, { Model = model, Humanoid = hum, Root = root })
			end
		end
	end
	return found
end

local function hit(ctx, target)
	if ctx.HitSet[target.Model] then return end
	ctx.HitSet[target.Model] = true
	local dealt, result = Rules.Damage(ctx.Player, target.Humanoid, ctx.Skill.Damage or 0)
	if (dealt or 0) > 0 then
		table.insert(ctx.Hits, target)
		if target.Humanoid.Health > 0 then Rules.Stun(target.Humanoid, ctx.Skill.Stun or 0, result) end
	end
end

local function groundTarget(ctx)
	local origin = ctx.Root.Position
	local center = origin + ctx.Look * (ctx.Skill.Range or 6)
	local wall = workspace:Raycast(origin, center - origin, ctx.Obstacles)
	if wall then center = wall.Position - ctx.Look * 0.5 end
	local floor = workspace:Raycast(center + Vector3.new(0, 3, 0), Vector3.new(0, -18, 0), ctx.Obstacles)
	return floor and floor.Position or center - Vector3.new(0, 3, 0), floor and floor.Normal or Vector3.yAxis
end

local function spear(ctx)
	local cfg = Config.LancaSangue
	if not waitUntil(ctx, ctx.BloodStartTime + cfg.ReleaseTime) then fx(ctx, "Cancel"); return end
	local direction = ctx.Look
	local from = ctx.Root.Position + Vector3.new(0, 0.5, 0) + direction * 2
	local wallAtStart = workspace:Raycast(ctx.Root.Position + Vector3.new(0, .5, 0), direction * 2, ctx.Obstacles)
	if wallAtStart then fx(ctx, "Impact", {Position = wallAtStart.Position, Normal = wallAtStart.Normal}); return end
	local range, speed = ctx.Skill.Range or 60, ctx.Skill.Speed or 90
	local radius = ctx.Skill.Radius or 3
	fx(ctx, "Launch", {Position = from, Direction = direction, Speed = speed, Range = range, LaunchTime = workspace:GetServerTimeNow()})
	local traveled = 0
	while traveled < range do
		local dt = RunService.Heartbeat:Wait()
		local distance = math.min(speed * dt, range - traveled)
		local to = from + direction * distance
		local wall = workspace:Raycast(from, to - from, ctx.Obstacles)
		if wall then to = wall.Position; distance = (to - from).Magnitude end
		local nearest, nearestAlong
		for _, target in targets(ctx, from:Lerp(to, .5), radius + distance * .5) do
			local offset = target.Root.Position - from
			local along = math.clamp(offset:Dot(direction), 0, distance)
			local point = from + direction * along
			if (target.Root.Position - point).Magnitude <= radius
				and clear(point, target.Root.Position, ctx.Obstacles) and (not nearestAlong or along < nearestAlong) then
				nearest, nearestAlong = target, along
			end
		end
		if nearest then
			hit(ctx, nearest)
			fx(ctx, "Impact", {Position = from + direction * nearestAlong, Normal = -direction, Target = nearest.Model})
			return
		end
		if wall then fx(ctx, "Impact", {Position = wall.Position, Normal = wall.Normal}); return end
		traveled += distance; from = to
	end
	fx(ctx, "Dissolve", {Position = from, Normal = -direction})
end

-- Onde quem invocou vai cair do pulo: a mesma conta do cliente (BloodFiendVFX.leap), feita no LeapStart. Vale a conta e
-- nao a posicao replicada no ImpactTime, que chega atrasada (o cliente move o proprio personagem).
local function leapLanding(ctx)
	local start, distance = ctx.Root.Position, Config.MarteloSangue.LeapDistance or 0
	if distance <= 0 then return start end
	local hit = workspace:Blockcast(CFrame.lookAt(start, start + ctx.Look), Vector3.new(2, 2.5, 1), ctx.Look * distance, ctx.Obstacles)
	if hit and hit.Normal.Y < 0.6 then distance = math.max(0, hit.Distance - 1) end
	return start + ctx.Look * distance
end

-- Onde o martelo bate: SlamOffset studs a frente de onde caiu (a cabeca do martelo encosta no chao ali)
local function slamPoint(ctx, landing)
	local center = landing + ctx.Look * (Config.MarteloSangue.SlamOffset or 3)
	local wall = workspace:Raycast(landing, center - landing, ctx.Obstacles)
	if wall then center = wall.Position - ctx.Look * 0.5 end
	local floor = workspace:Raycast(center + Vector3.new(0, 3, 0), Vector3.new(0, -18, 0), ctx.Obstacles)
	return floor and floor.Position or center - Vector3.new(0, 3, 0), floor and floor.Normal or Vector3.yAxis
end

local function hammer(ctx)
	local cfg = Config.MarteloSangue
	if not waitUntil(ctx, ctx.BloodStartTime + (cfg.LeapStart or 0)) then fx(ctx, "Cancel"); return end
	local landing = leapLanding(ctx)
	if not waitUntil(ctx, ctx.BloodStartTime + cfg.ImpactTime) then fx(ctx, "Cancel"); return end
	local point, normal = slamPoint(ctx, landing)
	local radius = ctx.Skill.Radius or 12
	fx(ctx, "Impact", {Position = point, Normal = normal, Radius = radius, Direction = ctx.Look})
	for _, target in targets(ctx, point + normal, radius) do
		if (target.Root.Position - point).Magnitude <= radius + 1
			and clear(point + normal, target.Root.Position, ctx.Obstacles) then hit(ctx, target) end
	end
end

function BloodFiendSkills.Cast(ctx)
	if not BloodFiendSkills.Handles(ctx.Skill.Id) or not alive(ctx) then return end
	serial += 1
	ctx.BloodCastId = tostring(ctx.Player.UserId) .. ":" .. tostring(serial)
	ctx.BloodStartTime = workspace:GetServerTimeNow()
	ctx.HitSet = ctx.HitSet or {}; ctx.Hits = ctx.Hits or {}
	local cfg = Config[ctx.Skill.Id]
	local source = "BloodFiend:" .. ctx.BloodCastId
	State.SetBusy(ctx.Player, ctx.BloodStartTime + cfg.Duration)
	State.SetSpeed(ctx.Player, source, .45)
	local released = false
	local function release()
		if released then return end
		released = true
		State.SetSpeed(ctx.Player, source, nil)
	end
	task.delay(cfg.Duration, release)
	local point, normal = groundTarget(ctx)
	fx(ctx, "Cast", {Position = ctx.Root.Position, Direction = ctx.Look, Ground = point, Normal = normal})
	local ok, message = xpcall(function()
		if ctx.Skill.Id == "LancaSangue" then spear(ctx) else hammer(ctx) end
	end, debug.traceback)
	if not ok or not alive(ctx) then release(); fx(ctx, "Cancel") end
	if not ok then warn("[BloodFiendSkills] " .. tostring(message)) end
end

return BloodFiendSkills
