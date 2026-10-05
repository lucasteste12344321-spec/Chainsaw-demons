-- Tutorial guiado: o cliente (Tutorial.client.luau) mostra os passos e confere cada um; aqui fica o que precisa do
-- servidor: salvar o passo (profile.Tutorial do PlayerData), dar a recompensa uma vez só e o boneco de treino.
-- Atributos no player: TutorialStep (número), TutorialDone e TutorialRewarded (bool).
-- Remotes.TutorialAction (C->S):
--   "Step", n       chegou no passo n (salva para continuar dali na próxima entrada)
--   "Finish"        concluiu: recompensa (TutorialData.Reward) só se chegou no último passo, passou do level 1 e
--                   ainda não ganhou
--   "Skip"          pulou: termina sem recompensa
--   "Restart"       refazer (botão nas configurações da HUD); a recompensa não se repete
--   "Dummy", bool   cria/apaga o boneco de treino na frente do jogador
-- O boneco fica em workspace.Enemies (atributos Enemy, EnemyType "Boneco" e TrainingDummy = UserId do dono) para os
-- golpes valerem (CombatRules). Não anda, não ataca, não morre (a vida volta) e não dá XP nem maestria.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local StarterPlayer = game:GetService("StarterPlayer")

local Remotes = require(ReplicatedStorage:WaitForChild("Remotes"))
local TutorialData = require(ReplicatedStorage:WaitForChild("TutorialData"))
local PlayerData = require(ServerScriptService:WaitForChild("PlayerData"))

local ACTION_GAP = 0.2 -- intervalo mínimo entre dois pedidos iguais do mesmo jogador (cada ação conta separado)
local DUMMY_GAP = 2 -- intervalo mínimo entre dois bonecos criados
local DUMMY_HEALTH = 1000
local DUMMY_REFILL = 0.6 -- abaixo desta fração a vida volta toda
local DUMMY_DISTANCE = 9 -- studs na frente do jogador
local DUMMY_LIFETIME = 900 -- some sozinho depois disso (jogador parado no tutorial)
local DUMMY_COLOR = Color3.fromRGB(150, 108, 66)

local lastAction = {}
local lastDummy = {}
local dummies = {} -- [player] = Model

local function publish(player, tutorial)
	player:SetAttribute("TutorialStep", tutorial.Step)
	player:SetAttribute("TutorialDone", tutorial.Done)
	player:SetAttribute("TutorialRewarded", tutorial.Rewarded)
end

local function getTutorial(player)
	local profile = PlayerData.GetProfile(player)
	return profile and profile.Tutorial, profile
end

----------------------------------------------------------------------------------------------------
-- Boneco de treino
----------------------------------------------------------------------------------------------------

local function removeDummy(player)
	local dummy = dummies[player]
	dummies[player] = nil
	if dummy and dummy.Parent then
		dummy:Destroy()
	end
end

local function enemiesFolder()
	local folder = workspace:FindFirstChild("Enemies")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "Enemies"
		folder.Parent = workspace
	end
	return folder
end

-- Nome e barra de vida em cima da cabeça (a vida desce e volta)
local function dummyBar(dummy, humanoid)
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "EnemyBar"
	billboard.Adornee = dummy:FindFirstChild("Head")
	billboard.Size = UDim2.fromOffset(130, 32)
	billboard.StudsOffset = Vector3.new(0, 2.5, 0)
	billboard.MaxDistance = 80
	billboard.Parent = dummy

	local name = Instance.new("TextLabel")
	name.Size = UDim2.new(1, 0, 0, 16)
	name.BackgroundTransparency = 1
	name.Font = Enum.Font.GothamBold
	name.TextSize = 14
	name.TextColor3 = Color3.fromRGB(255, 255, 255)
	name.TextStrokeTransparency = 0.4
	name.Text = "Boneco de Treino"
	name.Parent = billboard

	local back = Instance.new("Frame")
	back.Position = UDim2.fromOffset(0, 20)
	back.Size = UDim2.new(1, 0, 0, 8)
	back.BackgroundColor3 = Color3.fromRGB(25, 25, 25)
	back.BorderSizePixel = 0
	back.Parent = billboard
	Instance.new("UICorner", back).CornerRadius = UDim.new(0, 4)

	local fill = Instance.new("Frame")
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundColor3 = Color3.fromRGB(200, 40, 40)
	fill.BorderSizePixel = 0
	fill.Parent = back
	Instance.new("UICorner", fill).CornerRadius = UDim.new(0, 4)

	humanoid.HealthChanged:Connect(function(health)
		fill.Size = UDim2.fromScale(math.clamp(health / humanoid.MaxHealth, 0, 1), 1)
	end)
end

local function spawnDummy(player)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local template = StarterPlayer:FindFirstChild("StarterCharacter")
	if not root or not template then return end

	removeDummy(player)

	-- Na frente do jogador, no chão (raio de cima para baixo sem pegar personagens nem inimigos)
	local look = root.CFrame.LookVector
	local flat = Vector3.new(look.X, 0, look.Z)
	flat = if flat.Magnitude > 0.01 then flat.Unit else Vector3.new(0, 0, -1)
	local spot = root.Position + flat * DUMMY_DISTANCE
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local exclude = { enemiesFolder() }
	for _, other in Players:GetPlayers() do
		if other.Character then
			table.insert(exclude, other.Character)
		end
	end
	params.FilterDescendantsInstances = exclude
	params.RespectCanCollide = true
	local ground = workspace:Raycast(spot + Vector3.new(0, 8, 0), Vector3.new(0, -30, 0), params)
	local groundY = if ground then ground.Position.Y else root.Position.Y - 3
	local position = Vector3.new(spot.X, groundY + 3, spot.Z) -- R6: a raiz fica 3 studs acima do chão
	local facing = Vector3.new(root.Position.X, position.Y, root.Position.Z)

	local archivable = template.Archivable
	template.Archivable = true
	local dummy = template:Clone()
	template.Archivable = archivable
	dummy.Name = "Boneco de Treino"
	for _, item in dummy:GetDescendants() do
		if item:IsA("BasePart") then
			item.Color = DUMMY_COLOR
			item.Material = Enum.Material.Wood
		elseif item:IsA("BodyColors") or item:IsA("Decal") or item:IsA("Clothing") or item:IsA("LuaSourceContainer") then
			item:Destroy()
		end
	end
	local humanoid = dummy:FindFirstChildOfClass("Humanoid")
	local dummyRoot = dummy:FindFirstChild("HumanoidRootPart")
	if not humanoid or not dummyRoot then
		dummy:Destroy()
		return
	end
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	humanoid.BreakJointsOnDeath = false
	humanoid.WalkSpeed = 0
	humanoid.JumpPower = 0
	humanoid.MaxHealth = DUMMY_HEALTH
	humanoid.Health = DUMMY_HEALTH
	dummyRoot.Anchored = true -- fica no lugar (empurrões e arremessos não tiram ele dali)

	dummy:SetAttribute("Enemy", true)
	dummy:SetAttribute("EnemyType", "Boneco")
	dummy:SetAttribute("TrainingDummy", player.UserId)
	dummy:PivotTo(CFrame.lookAt(position, facing))
	dummyBar(dummy, humanoid)
	dummy.Parent = enemiesFolder()
	dummies[player] = dummy

	-- Não morre: a vida volta toda abaixo de DUMMY_REFILL
	humanoid.HealthChanged:Connect(function(health)
		if health < humanoid.MaxHealth * DUMMY_REFILL and humanoid:GetState() ~= Enum.HumanoidStateType.Dead then
			humanoid.Health = humanoid.MaxHealth
		end
	end)
	task.delay(DUMMY_LIFETIME, function()
		if dummies[player] == dummy then
			removeDummy(player)
		end
	end)
end

----------------------------------------------------------------------------------------------------
-- Ações
----------------------------------------------------------------------------------------------------

local function giveReward(player, tutorial, profile)
	tutorial.Rewarded = true
	local reward = TutorialData.Reward
	local parts = {}
	if reward.Gold and reward.Gold > 0 then
		PlayerData.AddGold(player, reward.Gold, true)
		table.insert(parts, `+{reward.Gold} Gold`)
	end
	if reward.Spins and reward.Spins > 0 and type(profile.Spins) == "number" then
		profile.Spins += reward.Spins
		player:SetAttribute("ClanSpins", profile.Spins)
		table.insert(parts, if reward.Spins == 1 then "+1 giro de clã" else `+{reward.Spins} giros de clã`)
	end
	PlayerData.Notify(player, "Tutorial concluído!", table.concat(parts, " e "), 6)
end

local VALID_ACTIONS = { Step = true, Finish = true, Skip = true, Restart = true, Dummy = true }
local function onAction(player, action, value)
	-- Valida antes de indexar o limitador: nomes inventados não podem criar entradas sem limite.
	if type(action) ~= "string" or not VALID_ACTIONS[action] then return end
	local clock = os.clock()
	local times = lastAction[player]
	if not times then
		times = {}
		lastAction[player] = times
	end
	if clock - (times[action] or 0) < ACTION_GAP then return end
	times[action] = clock

	local tutorial, profile = getTutorial(player)
	if not tutorial then return end

	if action == "Step" then
		if tutorial.Done or type(value) ~= "number" or value ~= value then return end
		tutorial.Step = math.clamp(math.floor(value), 1, TutorialData.Count)
	elseif action == "Finish" then
		if tutorial.Done then return end
		tutorial.Done = true
		removeDummy(player)
		if not tutorial.Rewarded and tutorial.Step >= TutorialData.Count
			and PlayerData.GetLevel(player) >= TutorialData.MinLevelForReward then
			giveReward(player, tutorial, profile)
		end
	elseif action == "Skip" then
		tutorial.Done = true
		removeDummy(player)
	elseif action == "Restart" then
		tutorial.Done = false
		tutorial.Step = 1
	elseif action == "Dummy" then
		if value == true then
			if tutorial.Done or clock - (lastDummy[player] or 0) < DUMMY_GAP then return end
			lastDummy[player] = clock
			spawnDummy(player)
		else
			removeDummy(player)
		end
		return
	else
		return
	end
	publish(player, tutorial)
end

local function onProfile(player)
	local tutorial = getTutorial(player)
	if tutorial then
		publish(player, tutorial)
	end
end

Remotes.TutorialAction.OnServerEvent:Connect(onAction)
PlayerData.ProfileLoaded:Connect(onProfile)
for _, player in Players:GetPlayers() do
	onProfile(player)
end

Players.PlayerRemoving:Connect(function(player)
	removeDummy(player)
	lastAction[player] = nil
	lastDummy[player] = nil
end)
