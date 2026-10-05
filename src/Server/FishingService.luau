local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")
local Lighting = game:GetService("Lighting")
local Remotes = require(ReplicatedStorage.Remotes)
local Data = require(ReplicatedStorage.FishingData)
local Rules = require(ReplicatedStorage.FishingRules)
local PlayerData = require(script.Parent.PlayerData)
local Quests = require(script.Parent.QuestModule)
local Service = {}
local sessions, readySpots, limits, cooldowns = {}, {}, {}, {}
local spots, fisherman, initialized
local Passes = require(script.Parent.GamepassEntitlements)
local rng = Random.new()
local recentDamage, mealCooldowns, healing, characterConnections = {}, {}, {}, {}
local cook

local function alive(player)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not root or not humanoid or humanoid.Health <= 0 or character:GetAttribute("Stunned") then return nil end
	return root, humanoid, character
end

local function save(player)
	local profile = PlayerData.GetProfile(player)
	return profile and profile.Fishing
end

local function nearNPC(player)
	local root = alive(player)
	local target = fisherman and fisherman:FindFirstChild("HumanoidRootPart")
	return root and target and (root.Position - target.Position).Magnitude <= 18
end

local function allowed(player)
	local now = os.clock()
	local bucket = limits[player] or { Time = now, Tokens = 14 }
	bucket.Tokens = math.min(14, bucket.Tokens + (now - bucket.Time) * 9); bucket.Time = now
	limits[player] = bucket
	if bucket.Tokens < 1 then return false end
	bucket.Tokens -= 1
	return true
end

local function nearCook(player)
	local root = alive(player)
	local target = cook and cook:FindFirstChild("HumanoidRootPart")
	return root and target and (root.Position - target.Position).Magnitude <= 18
end

local function sendMenu(player)
	local data = save(player)
	if not data then return end
	Remotes.FishingState:FireClient(player, { Phase = "Menu", Data = data, Value = Data.SaleValue(data) * Passes.Multiplier(player, "DoubleGold"), CanTrade = nearNPC(player) == true, CanCook = nearCook(player) == true })
end

local function fx(kind, player, session, extra)
	for _, other in Players:GetPlayers() do
		local root = other.Character and other.Character:FindFirstChild("HumanoidRootPart")
		if other == player or (root and (root.Position - session.Point).Magnitude < 220) then
			Remotes.FishingFX:FireClient(other, kind, { UserId = player.UserId, Id = session.Id, Point = session.Point, Fish = extra })
		end
	end
end

local function finish(player, reason, caught)
	local session = sessions[player]
	if not session then return end
	sessions[player] = nil -- retire before touching rewards; replays cannot grant another fish
	cooldowns[player] = os.clock() + 1.2
	player:SetAttribute("Fishing", false)
	local data = save(player)
	if caught and data and Data.BagCount(data) < Data.BagLimit then
		local id = session.Fish
		local fish = Data.Fish[id]
		local kg = math.floor(rng:NextNumber(fish.MinKg, fish.MaxKg) * 100 + 0.5) / 100
		data.Counts[id] = (data.Counts[id] or 0) + 1
		data.Catches += 1
		data.Records[id] = math.max(data.Records[id] or 0, kg)
		PlayerData.AddXP(player, 10)
		Quests.OnActivity(player, "Fish", id, session.Id)
		Remotes.FishingState:FireClient(player, { Phase = "Caught", Fish = id, Kg = kg, Data = data, SpotId = session.Spot.Name })
		fx("Catch", player, session, id)
	else
		Remotes.FishingState:FireClient(player, { Phase = "Ended", Reason = reason or "A linha foi recolhida.", SpotId = session.Spot.Name })
		fx("End", player, session)
	end
end

local function rod(player)
	local character, backpack = player.Character, player:FindFirstChildOfClass("Backpack")
	if not character or not backpack then return nil end
	for _, container in { character, backpack } do
		for _, item in container:GetChildren() do if item:IsA("Tool") and item:GetAttribute("FishingRod") then return item end end
	end
	local vfx = ReplicatedStorage:FindFirstChild("VFX")
	local library = vfx and vfx:FindFirstChild("WorldActivities")
	local template = library and library:FindFirstChild("FishingRod")
	if not template then warn("[Fishing] Missing authored FishingRod template"); return nil end
	local item = template:Clone(); item.CanBeDropped = false; item.Parent = backpack
	return item
end

local function prepare(player, spot)
	local root, humanoid = alive(player)
	local data = save(player)
	if not root or not data or (root.Position - spot.Position).Magnitude > Data.SpotRange then return end
	if not data.HasRod then PlayerData.Notify(player, "Pesca", "Pegue a vara gratuita com Daichi no píer principal. Use R para abrir a banca."); return end
	if Data.BagCount(data) >= Data.BagLimit then PlayerData.Notify(player, "Cesta cheia", "Venda seus peixes para Daichi antes de continuar."); return end
	finish(player, "Você mudou de ponto de pesca.")
	local item = rod(player)
	if not item then return end
	humanoid:EquipTool(item)
	readySpots[player] = spot
	Remotes.FishingState:FireClient(player, { Phase = "Ready", SpotId = spot.Name, Data = data, Hotspot = spot:GetAttribute("Hotspot") == true })
end

local function chooseFish(tier, hotspot)
	local weights, total = {}, 0
	for _, id in Data.Order do
		local weight = Data.CatchWeight(id, tier, Lighting.ClockTime, hotspot)
		total += weight; table.insert(weights, { id, total })
	end
	local roll = rng:NextNumber() * total
	for _, item in weights do if roll <= item[2] then return item[1] end end
	return Data.Order[1]
end

local function start(player, spotId, strength)
	if sessions[player] or os.clock() < (cooldowns[player] or 0) then return end
	if type(strength) ~= "number" or strength ~= strength or math.abs(strength) == math.huge then return end
	local spot = readySpots[player]
	if not spot or spot.Name ~= spotId or not spot:IsDescendantOf(workspace) then return end
	local root, _, character = alive(player)
	local data = save(player)
	if not root or not data or not data.HasRod or Data.BagCount(data) >= Data.BagLimit then return end
	local held = character:FindFirstChildOfClass("Tool")
	if not held or not held:GetAttribute("FishingRod") then return end
	if (root.Position - spot.Position).Magnitude > Data.SpotRange then return end
	local point = spot:GetAttribute("CastPosition")
	if typeof(point) ~= "Vector3" then return end
	-- All target geometry comes from the server-authored fishing spot, never a client hit.
	point += Vector3.new(0, 0, (1 - math.clamp(strength, 0, 1)) * 6)
	if (root.Position - point).Magnitude > Data.MaxCastRange then return end
	local ray = RaycastParams.new(); ray.FilterType = Enum.RaycastFilterType.Exclude
	ray.FilterDescendantsInstances = { character, spots.Parent }; ray.IgnoreWater = true; ray.RespectCanCollide = true
	local origin = root.Position + Vector3.new(0, 2, 0)
	local obstruction = workspace:Raycast(origin, point + Vector3.new(0, 1.5, 0) - origin, ray)
	if obstruction and (obstruction.Position - point).Magnitude > 5 then
		PlayerData.Notify(player, "Pesca", "A linha está bloqueada. Fique na ponta do píer."); return
	end
	local now = os.clock()
	local session = { Id = HttpService:GenerateGUID(false), Spot = spot, Point = point, Origin = root.Position, Character = character,
		Phase = "Casting", Started = now, Next = now + 0.7, Fish = chooseFish(data.RodTier, spot:GetAttribute("Hotspot") == true),
		Tier = data.RodTier, Holding = false, Tension = 0.4, Progress = 0.12, Danger = 0, Slack = 0, Seed = rng:NextNumber(0, 6.28), Sent = 0 }
	sessions[player] = session; player:SetAttribute("Fishing", true)
	Remotes.FishingState:FireClient(player, { Phase = "Casting", Id = session.Id, SpotId = spotId })
	fx("Cast", player, session)
end

local function action(player, kind, id, value)
	if type(kind) ~= "string" or #kind > 20 or not allowed(player) then return end
	if id ~= nil and (type(id) ~= "string" or #id > 80) then return end
	if kind == "Bag" then if not sessions[player] then sendMenu(player) end; return end
	if kind == "Cook" then
		local data = save(player)
		if not data or not nearCook(player) or sessions[player] then return end
		local profile = PlayerData.GetProfile(player)
		if (profile.Quests.Completed.Side_HotSupper or 0) <= 0 then PlayerData.Notify(player,"Receita de Nori","Conclua a missão Jantar no fim do mundo para aprender a receita."); return end
		if data.Meals >= 20 then PlayerData.Notify(player,"Despensa cheia","Você já tem 20 sopas."); return end
		if data.Counts.RiverCarp < 2 or data.Counts.Trout < 1 then PlayerData.Notify(player,"Ingredientes","Você precisa de 2 carpas e 1 truta na cesta."); return end
		data.Counts.RiverCarp -= 2; data.Counts.Trout -= 1; data.Meals += 1
		PlayerData.Notify(player,"Sopa preparada","Use a cesta de pesca para tomar a sopa fora de combate.",4); sendMenu(player); return
	end
	if kind == "Eat" then
		local data = save(player); local _, humanoid = alive(player); local now = os.clock()
		if not data or not humanoid or sessions[player] or healing[player] or data.Meals < 1 then return end
		if humanoid.Health >= humanoid.MaxHealth then PlayerData.Notify(player,"Sopa","Sua vida já está cheia."); return end
		if now - (recentDamage[player] or -100) < 10 or now < (mealCooldowns[player] or 0) then PlayerData.Notify(player,"Sopa","Espere 10 segundos sem sofrer dano e 60 segundos entre refeições."); return end
		data.Meals -= 1; mealCooldowns[player] = now + 60; healing[player] = humanoid; sendMenu(player)
		PlayerData.Notify(player,"Refeição quente","Recuperando 25% de vida em 5 segundos. Sofrer dano interrompe a recuperação.",5)
		task.spawn(function()
			for _ = 1, 5 do
				task.wait(1)
				local _, currentHumanoid = alive(player)
				if currentHumanoid ~= humanoid or healing[player] ~= humanoid or (recentDamage[player] or -100) > now then break end
				humanoid.Health = math.min(humanoid.MaxHealth, humanoid.Health + humanoid.MaxHealth * .05)
			end
			if healing[player] == humanoid then healing[player] = nil end
		end)
		return
	end
	if kind == "Cancel" then
		finish(player, "Pesca encerrada."); readySpots[player] = nil
		local _, humanoid, character = alive(player)
		local held = character and character:FindFirstChildOfClass("Tool")
		if held and held:GetAttribute("FishingRod") then humanoid:UnequipTools() end
		return
	end
	if kind == "Start" then start(player, id, value); return end
	if kind == "Reopen" then
		local spot = spots and spots:FindFirstChild(id or "")
		if spot and spot:IsA("BasePart") then prepare(player, spot) end
		return
	end
	if kind == "ClaimRod" or kind == "Sell" or kind == "Upgrade" or kind == "Menu" then
		if not nearNPC(player) or sessions[player] then return end
		local data = save(player); if not data then return end
		if kind == "ClaimRod" then
			data.HasRod = true; rod(player)
		elseif kind == "Sell" then
			local amount = Data.SaleValue(data)
			if amount > 0 then
				for _, fishId in Data.Order do data.Counts[fishId] = 0 end
				amount = PlayerData.AddGold(player, amount, true, true) or amount
				PlayerData.Notify(player, "Peixes vendidos", `Você recebeu {amount} Gold.`, 4)
			end
		elseif kind == "Upgrade" then
			local nextRod = Data.Rods[data.RodTier + 1]
			if not data.HasRod or not nextRod then return end
			if data.Catches < nextRod.Catches then PlayerData.Notify(player, "Vara", `Capture {nextRod.Catches} peixes ao todo para liberar esta melhoria.`); return end
			if not PlayerData.SpendGold(player, nextRod.Price) then PlayerData.Notify(player, "Vara", `A melhoria custa {nextRod.Price} Gold.`); return end
			data.RodTier += 1
			PlayerData.Notify(player, "Vara melhorada", nextRod.Name, 4)
		end
		sendMenu(player); return
	end
	local session = sessions[player]
	if not session or session.Id ~= id or not alive(player) then return end
	if kind == "Hook" and session.Phase == "Bite" and os.clock() <= session.Next then
		session.Phase = "Reeling"; session.ReelStart = os.clock(); session.Holding = false
		Remotes.FishingState:FireClient(player, { Phase = "Reeling", Id = session.Id, Tension = session.Tension, Progress = session.Progress })
		fx("Hook", player, session)
	elseif kind == "Reel" and session.Phase == "Reeling" and type(value) == "boolean" then
		session.Holding = value
	end
end

function Service.Init(world)
	if initialized then return end; initialized = true
	spots = world:WaitForChild("FishingSpots")
	fisherman = world.NPCs:WaitForChild(Data.NPCId)
	cook = world.NPCs:WaitForChild("KuroNori")
	local cookPrompt = cook.HumanoidRootPart:FindFirstChild("CookingMarket")
	if cookPrompt then cookPrompt.Triggered:Connect(function(player) if nearCook(player) then sendMenu(player) end end) end
	local function trackCharacter(player, character)
		local old = characterConnections[player]; if old then old:Disconnect() end
		healing[player] = nil
		local humanoid = character:WaitForChild("Humanoid",10); if not humanoid or player.Character ~= character then return end
		local previous = humanoid.Health
		characterConnections[player] = humanoid.HealthChanged:Connect(function(health)
			if health < previous then recentDamage[player] = os.clock() end
			previous = health
		end)
	end
	local function trackPlayer(player)
		player.CharacterAdded:Connect(function(character) trackCharacter(player,character) end)
		if player.Character then task.spawn(trackCharacter,player,player.Character) end
	end
	Players.PlayerAdded:Connect(trackPlayer)
	for _, player in Players:GetPlayers() do trackPlayer(player) end
	for _, spot in spots:GetChildren() do
		local prompt = spot:FindFirstChildOfClass("ProximityPrompt")
		if prompt then prompt.Triggered:Connect(function(player) prepare(player, spot) end) end
	end
	local market = fisherman.HumanoidRootPart:FindFirstChild("FishingMarket")
	if market then market.Triggered:Connect(function(player) if nearNPC(player) then sendMenu(player) end end) end
	Remotes.FishingAction.OnServerEvent:Connect(action)
	Players.PlayerRemoving:Connect(function(player)
		finish(player); readySpots[player] = nil; limits[player] = nil; cooldowns[player] = nil
		if characterConnections[player] then characterConnections[player]:Disconnect(); characterConnections[player] = nil end
		recentDamage[player] = nil; mealCooldowns[player] = nil; healing[player] = nil
	end)
	local elapsed = 0
	RunService.Heartbeat:Connect(function(dt)
		elapsed += dt; if elapsed < 0.05 then return end
		local step = math.min(elapsed, 0.15); elapsed = 0
		local now = os.clock()
		for player, session in sessions do
			local root, _, character = alive(player)
			local held = character and character:FindFirstChildOfClass("Tool")
			if not root or character ~= session.Character or not held or not held:GetAttribute("FishingRod")
				or (root.Position - session.Origin).Magnitude > Data.MoveLimit then
				finish(player, "Pesca interrompida: você se afastou, trocou de equipamento ou foi atingido."); continue
			end
			if session.Phase == "Casting" and now >= session.Next then
				session.Phase = "Waiting"; session.Next = now + rng:NextNumber(4, 9)
				Remotes.FishingState:FireClient(player, { Phase = "Waiting", Id = session.Id })
			elseif session.Phase == "Waiting" and now >= session.Next then
				session.Phase = "Bite"; session.Next = now + Data.HookWindow
				Remotes.FishingState:FireClient(player, { Phase = "Bite", Id = session.Id, Deadline = workspace:GetServerTimeNow() + Data.HookWindow })
				fx("Bite", player, session)
			elseif session.Phase == "Bite" and now > session.Next then finish(player, "O peixe escapou da isca. Tente fisgar quando a boia afundar.")
			elseif session.Phase == "Reeling" then
				local result = Rules.Step(session, session.Holding, step, now - session.ReelStart, Data.Rods[session.Tier].Control, Data.Fish[session.Fish].Difficulty)
				if result then finish(player, if result == "Snapped" then "A linha arrebentou. Solte um pouco antes da tensão chegar ao vermelho." else "O peixe escapou. Alterne recolher e aliviar a linha.", result == "Caught")
				elseif now - session.Sent >= 0.1 then
					session.Sent = now
					Remotes.FishingState:FireClient(player, { Phase = "Reeling", Id = session.Id, Tension = session.Tension, Progress = session.Progress })
				end
			end
		end
	end)
	task.spawn(function()
		local last
		while world.Parent do
			if #spots:GetChildren() == 0 then task.wait(5); continue end
			local index = math.floor(os.time() / 180) % #spots:GetChildren() + 1
			if index ~= last then
				last = index
				local list = spots:GetChildren(); table.sort(list, function(a,b) return a.Name < b.Name end)
				for i, spot in list do
					spot:SetAttribute("Hotspot", i == index)
					local prompt = spot:FindFirstChildOfClass("ProximityPrompt")
					if prompt then prompt.ObjectText = if i == index then "Rio Kuro • cardume ativo" else "Rio Kuro" end
				end
			end
			task.wait(5)
		end
	end)
end

return Service
