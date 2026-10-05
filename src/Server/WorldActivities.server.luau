local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Remotes = require(ReplicatedStorage.Remotes)
local Data = require(script.Parent.WorldQuestData)
local Quests = require(script.Parent.QuestModule)
local PlayerData = require(script.Parent.PlayerData)
local Fishing = require(script.Parent.FishingService)
local WorldPropAssets = require(ReplicatedStorage:WaitForChild("WorldPropAssets"))
local world = workspace:WaitForChild("WorldActivities", 30)
if not world then warn("[WorldActivities] Install the authored WorldActivities model in Edit first."); return end

local nodes = world:WaitForChild("ActivityNodes"):GetChildren()
local eventNodes = world:WaitForChild("EventNodes"):GetChildren()
local cooldowns, carrying, requestTimes = {}, {}, {}
local current

local function rootOf(player)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	return if root and humanoid and humanoid.Health > 0 and not character:GetAttribute("Stunned") then root else nil
end

local function near(player, node, range)
	local root = rootOf(player)
	return root and (root.Position - node.Position).Magnitude <= (range or 14)
end

local function needs(player, kind, target, unique)
	for id, entry in Quests.GetActive(player) or {} do
		local quest = Quests.Quests[id]
		for i, objective in quest and quest.Objectives or {} do
			local match = objective.Target == target or (objective.Target == nil and (not objective.TargetList or table.find(objective.TargetList, target)))
			local key = kind .. ":" .. tostring(objective.Target or "*") .. ":" .. unique
			if objective.Type == kind and match and (entry.Progress[i] or 0) < objective.Amount
				and not (entry.ActivityVisits and entry.ActivityVisits[key]) then return true end
		end
	end
	return false
end

local function clearCarry(player)
	local info = carrying[player]; carrying[player] = nil
	if info and info.Visual then info.Visual:Destroy() end
end

local function snapshot(player)
	if not current then return end
	local contribution = current.Contributions[player] or 0
	Remotes.WorldActivityState:FireClient(player, {
		Id = current.Def.Id, Name = current.Def.Name, Region = current.Def.Region, Description = current.Def.Description,
		Progress = current.Progress, Goal = current.Def.Goal, EndsAt = current.EndsAt,
		NextAt = (current.Cycle + 1) * Data.EventPeriod, Status = current.Status,
		Contribution = contribution, Carrying = carrying[player] ~= nil, Position = current.Position,
	})
end

local function broadcast()
	for _, player in Players:GetPlayers() do snapshot(player) end
end

local function setEventVisuals()
	for _, node in eventNodes do
		local active = current and current.Status == "Active" and node:GetAttribute("EventId") == current.Def.Id
		local used = active and current.Used[node.Name]
		local prompt = node:FindFirstChildOfClass("ProximityPrompt")
		if prompt then prompt.Enabled = active == true and not used end
		local lamp = node:FindFirstChildOfClass("PointLight")
		if lamp then lamp.Enabled = active == true and used == true end
		local marker = node:FindFirstChild("EventMarker")
		if marker then marker.Enabled = active == true and not used end
		local glow = node:FindFirstChild("Glow")
		if glow and glow:IsA("BasePart") then glow.Material = if used then Enum.Material.Neon else Enum.Material.Glass end
		local visual = node:FindFirstChild("ItemVisual")
		if visual then
			for _, part in visual:GetDescendants() do
				if part:IsA("BasePart") and part:GetAttribute("LampGlow") then
					part.Material = if used then Enum.Material.Neon else Enum.Material.Glass
					part.Transparency = if used then .1 else .55
				end
			end
		end
	end
end

local function rewardEvent()
	current.Status = "Complete"
	for player, amount in current.Contributions do
		local profile = PlayerData.GetProfile(player)
		if player.Parent and profile and amount >= 2 then
			local claims = profile.WorldActivities.EventClaims
			if claims[current.Def.Id] ~= current.Cycle then
				claims[current.Def.Id] = current.Cycle
				PlayerData.AddGold(player, current.Def.Gold)
				PlayerData.AddXP(player, current.Def.XP)
				Quests.OnActivity(player, "WorldEvent", current.Def.Id, tostring(current.Cycle))
				PlayerData.Notify(player, "A região agradece", `{current.Def.Name}: +{current.Def.Gold} Gold e +{current.Def.XP} XP`, 5)
			end
		end
	end
	for player in carrying do clearCarry(player) end
	setEventVisuals(); broadcast()
end

local function contribute(player)
	if current.Status ~= "Active" or os.time() >= current.EndsAt then return end
	current.Progress += 1
	current.Contributions[player] = (current.Contributions[player] or 0) + 1
	if current.Progress >= current.Def.Goal then rewardEvent() else setEventVisuals(); broadcast() end
end

for _, node in nodes do
	if not node:IsA("BasePart") then continue end
	local prompt = node:FindFirstChildOfClass("ProximityPrompt")
	if not prompt then continue end
	prompt.Triggered:Connect(function(player)
		if not near(player, node) then return end
		local now = os.clock()
		local times = cooldowns[player] or {}; cooldowns[player] = times
		if now < (times[node.Name] or 0) then return end
		local kind, target = node:GetAttribute("ObjectiveType"), node:GetAttribute("Target")
		if not needs(player, kind, target, node.Name) then
			times[node.Name] = now + 3
			PlayerData.Notify(player, "Exploração", "Este ponto serve a uma missão da região. Fale com os moradores para aceitar o trabalho.", 3)
			return
		end
		times[node.Name] = now + (node:GetAttribute("RespawnSeconds") or 3)
		Quests.OnActivity(player, kind, target, node.Name)
		Remotes.WorldActivityState:FireClient(player, { Action = "Collected", Node = node.Name, Text = node:GetAttribute("Label") or "Objetivo atualizado" })
	end)
end

for _, node in eventNodes do
	local prompt = node:FindFirstChildOfClass("ProximityPrompt")
	if not prompt then continue end
	prompt.Triggered:Connect(function(player)
		if not current or current.Status ~= "Active" or os.time() >= current.EndsAt or not near(player, node) then return end
		if node:GetAttribute("EventId") ~= current.Def.Id or not PlayerData.GetProfile(player) then return end
		local role = node:GetAttribute("EventRole")
		if role == "Supply" then
			if carrying[player] then return end
			local times = cooldowns[player] or {}; cooldowns[player] = times
			if os.clock() < (times[node.Name] or 0) then return end
			times[node.Name] = os.clock() + 8
			local root = rootOf(player)
			local crate = WorldPropAssets.Attach(node:GetAttribute("CarryAsset") or "CarryCrate", root, CFrame.new(0, -.1, -1.7))
			if not crate then return end
			crate.Name = "RegionalSupplyCrate"
			carrying[player] = { Cycle = current.Cycle, At = os.clock(), Source = node.Position, Visual = crate }
			snapshot(player)
		elseif role == "Delivery" then
			local item = carrying[player]
			if not item or item.Cycle ~= current.Cycle or os.clock() - item.At < math.min(3, (node.Position - item.Source).Magnitude / 60) then return end
			clearCarry(player); contribute(player)
		elseif role == "Repair" and not current.Used[node.Name] then
			current.Used[node.Name] = true; contribute(player)
		end
	end)
end

Remotes.WorldActivityState.OnServerEvent:Connect(function(player)
	local now = os.clock(); if now - (requestTimes[player] or 0) < 2 then return end
	requestTimes[player] = now; snapshot(player)
end)
Players.PlayerRemoving:Connect(function(player)
	clearCarry(player); cooldowns[player] = nil; requestTimes[player] = nil
	if current then current.Contributions[player] = nil end
end)

Fishing.Init(world)
task.spawn(function()
	while world.Parent do
		local now = os.time(); local cycle = math.floor(now / Data.EventPeriod)
		if not current or current.Cycle ~= cycle then
			for player in carrying do clearCarry(player) end
			local def = Data.Events[cycle % #Data.Events + 1]
			local position = Vector3.zero
			for _, node in eventNodes do if node:GetAttribute("EventId") == def.Id then position = node.Position; break end end
			current = { Def = def, Cycle = cycle, EndsAt = cycle * Data.EventPeriod + Data.EventDuration,
				Status = "Active", Progress = 0, Contributions = {}, Used = {}, Position = position }
			setEventVisuals(); broadcast()
		end
		if current.Status == "Active" and now >= current.EndsAt then
			current.Status = "Expired"
			for player in carrying do clearCarry(player) end
			setEventVisuals(); broadcast()
		end
		for _, player in Players:GetPlayers() do
			local root = rootOf(player)
			if not root then
				if carrying[player] then clearCarry(player); snapshot(player) end
				continue
			end
			for _, node in nodes do
				if node:GetAttribute("ObjectiveType") == "Explore" and (root.Position - node.Position).Magnitude <= (node:GetAttribute("Radius") or 14) then
					local target = node:GetAttribute("Target")
					if needs(player, "Explore", target, node.Name) then
						Quests.OnActivity(player, "Explore", target, node.Name)
						PlayerData.Notify(player, "Local descoberto", node:GetAttribute("Label"), 3)
					end
				end
			end
		end
		task.wait(0.5)
	end
end)
