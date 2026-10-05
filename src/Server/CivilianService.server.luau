-- Civis (pedido do usuário, 2026-10-05: "civis andando pelo mapa, falando uns diálogos, e dar para matar e brigar"):
-- bonecos do StarterCharacter com aparência sorteada (AppearanceData) que passeiam pela cidade, cumprimentam quem
-- passa perto e só reagem a quem bate neles. A IA é a do EnemyModule (opções Passive, Flee e AlertGroup):
--   Civilian      (medroso) foge de quem bateu
--   CivilianTough (valentão) briga com quem bateu, e os civis em volta (grupo "Civilians") também reagem
-- Recompensa pequena (XP e Gold), sem contar em missões, diárias nem marcos (não dá para farmar civil).
-- Zonas: Parts em workspace.CivilianZones (ancoradas, invisíveis, sem colisão); os civis nascem e passeiam dentro da
-- área da Part (X/Z). Atributos opcionais: MaxCivilians (4), BrawlerChance (0.25), RespawnTime (20).
-- Sem a pasta: FALLBACK_COUNT civis em volta do primeiro SpawnLocation.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local StarterPlayer = game:GetService("StarterPlayer")
local CollectionService = game:GetService("CollectionService")

local AppearanceData = require(ReplicatedStorage:WaitForChild("AppearanceData"))
local EnemyModule = require(ServerScriptService:WaitForChild("EnemyModule"))
local PlayerData = require(ServerScriptService:WaitForChild("PlayerData"))

local DEFAULT_MAX = 4
local DEFAULT_BRAWLER = 0.25
local DEFAULT_RESPAWN = 20
local FALLBACK_COUNT = 6
local FALLBACK_RADIUS = 80
local WALK_MULTIPLIER = 0.45 -- passeando (fração da Speed do EnemyData)
local PAUSE_MIN, PAUSE_MAX = 2, 6 -- parado olhando a rua entre um passeio e outro
local WALK_TIMEOUT = 15 -- não chegou no destino nesse tempo: escolhe outro
local GREET_RANGE = 14
local GREET_COOLDOWN = { 8, 15 }
local REACT_COOLDOWN = 2
local BUBBLE_TIME = 3.5
local BUBBLE_DISTANCE = 60

local Lines = {
	Greet = {
		"Nice weather today, huh?",
		"Watch out, I heard devils were spotted nearby.",
		"Are you one of those devil hunters?",
		"Hey there!",
		"Don't cause any trouble around here.",
		"I'm late for work again...",
		"Have you seen my cat?",
		"The canal smells worse every day.",
		"Stay safe out there.",
		"Those goblins keep stealing from the market.",
		"Is it true there's a guy with a chainsaw for a head?",
		"I just want a normal day for once.",
	},
	ToughGreet = {
		"What are you looking at?",
		"Keep walking, pal.",
		"This is my street.",
		"You think you're tough?",
	},
	Hurt = {
		"Ow! What was that for?!",
		"Help! Somebody help!",
		"Stop! I didn't do anything!",
		"Call the hunters!",
		"Please, leave me alone!",
		"Aaah!",
	},
	Taunt = {
		"Oh, you want a fight?",
		"Big mistake, buddy!",
		"You picked the wrong guy!",
		"Come on then!",
		"That all you got?",
	},
	Death = {
		"Ugh...",
		"Why...",
		"Tell my mom...",
	},
}

local rng = Random.new()
local templateCache = nil

local function pick(list)
	return list[rng:NextInteger(1, #list)]
end

-- Balão de fala em cima da cabeça (servidor: todos veem). AlwaysOnTop desligado: com ele o BillboardGui não aparecia
-- no Studio (ver "Revisão do combate" no AGENTS.md).
local function say(npc, text)
	local head = npc:FindFirstChild("Head")
	if not head then return end
	local old = head:FindFirstChild("SpeechBubble")
	if old then old:Destroy() end

	local gui = Instance.new("BillboardGui")
	gui.Name = "SpeechBubble"
	gui.Size = UDim2.fromOffset(220, 60)
	gui.StudsOffset = Vector3.new(0, 3.4, 0)
	gui.MaxDistance = BUBBLE_DISTANCE
	gui.AlwaysOnTop = false
	gui.LightInfluence = 0
	gui.ResetOnSpawn = false

	local bubble = Instance.new("TextLabel")
	bubble.AnchorPoint = Vector2.new(0.5, 1)
	bubble.Position = UDim2.fromScale(0.5, 1)
	bubble.Size = UDim2.fromScale(1, 1)
	bubble.AutomaticSize = Enum.AutomaticSize.None
	bubble.BackgroundColor3 = Color3.fromRGB(245, 242, 236)
	bubble.BackgroundTransparency = 0.05
	bubble.TextColor3 = Color3.fromRGB(25, 22, 22)
	bubble.Font = Enum.Font.BuilderSansMedium
	bubble.TextScaled = true
	bubble.TextWrapped = true
	bubble.Text = text
	bubble.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = bubble
	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 8)
	padding.PaddingRight = UDim.new(0, 8)
	padding.PaddingTop = UDim.new(0, 4)
	padding.PaddingBottom = UDim.new(0, 4)
	padding.Parent = bubble
	local limit = Instance.new("UITextSizeConstraint")
	limit.MaxTextSize = 18
	limit.Parent = bubble

	gui.Parent = head
	task.delay(BUBBLE_TIME, function()
		if gui.Parent then gui:Destroy() end
	end)
end

-- Cópia limpa do StarterCharacter (sem scripts, tags nem prompts)
local function baseCharacter()
	if templateCache then
		return templateCache
	end
	local source = StarterPlayer:FindFirstChild("StarterCharacter")
	if not source or not source:FindFirstChildOfClass("Humanoid") or not source:FindFirstChild("HumanoidRootPart") then
		return nil
	end
	local archivable = source.Archivable
	source.Archivable = true
	local copy = source:Clone()
	source.Archivable = archivable
	if not copy then return nil end
	for _, item in { copy, table.unpack(copy:GetDescendants()) } do
		for _, tag in CollectionService:GetTags(item) do
			CollectionService:RemoveTag(item, tag)
		end
		if item:IsA("LuaSourceContainer") or item:IsA("ProximityPrompt") then
			item:Destroy()
		end
	end
	copy.Name = "Civilian" -- casa com EnemyKits.Civilian
	templateCache = copy
	return copy
end

-- Template com aparência sorteada (o EnemyModule clona; este é apagado depois)
local function buildTemplate()
	local base = baseCharacter()
	if not base then return nil end
	local template = base:Clone()
	template.Name = "Civilian"
	local ok, err = pcall(AppearanceData.Apply, template, AppearanceData.Random(rng))
	if not ok then
		warn(`[CivilianService] Aparência não aplicada: {err}`)
	end
	return template
end

-- Zona: { Part = BasePart? } ou { Center, Radius } (fallback)
local function zonePoint(zone)
	local x, z, top
	if zone.Part then
		local part = zone.Part
		local size = part.Size
		local offset = Vector3.new(
			rng:NextNumber(-size.X / 2, size.X / 2),
			size.Y / 2,
			rng:NextNumber(-size.Z / 2, size.Z / 2)
		)
		local world = part.CFrame:PointToWorldSpace(offset)
		x, z, top = world.X, world.Z, world.Y
	else
		local angle = rng:NextNumber(0, math.pi * 2)
		local radius = math.sqrt(rng:NextNumber()) * zone.Radius
		x = zone.Center.X + math.cos(angle) * radius
		z = zone.Center.Z + math.sin(angle) * radius
		top = zone.Center.Y
	end

	local exclude = { workspace:FindFirstChild("Enemies"), workspace:FindFirstChild("CivilianZones") }
	for _, player in Players:GetPlayers() do
		if player.Character then table.insert(exclude, player.Character) end
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = exclude
	params.RespectCanCollide = true
	local hit = workspace:Raycast(Vector3.new(x, top + 20, z), Vector3.new(0, -80, 0), params)
	if not hit then return nil end
	return hit.Position
end

local function rewardKiller(humanoid, _enemyType, stats)
	local attackerId = humanoid:GetAttribute("LastAttacker")
	local killer = attackerId and Players:GetPlayerByUserId(attackerId)
	if not killer then return end
	PlayerData.AddXP(killer, stats.XP)
	PlayerData.AddGold(killer, stats.Gold)
end

local civilians = {} -- [npc] = { Tough, NextGreet, NextReact }

local spawnCivilian

local function hookCivilian(zone, npc, controller, tough)
	local state = { Tough = tough, NextGreet = os.clock() + rng:NextNumber(2, 8), NextReact = 0 }
	civilians[npc] = state

	-- Passeio: um ponto da zona, anda devagar, para um pouco e escolhe outro
	local destination, pauseUntil, walkStarted = nil, 0, 0
	controller.OnIdle = function()
		local humanoid, root = controller.Humanoid, controller.Root
		local now = os.clock()
		if destination then
			local flat = Vector3.new(destination.X - root.Position.X, 0, destination.Z - root.Position.Z)
			if flat.Magnitude < 3 or now - walkStarted > WALK_TIMEOUT then
				destination = nil
				pauseUntil = now + rng:NextNumber(PAUSE_MIN, PAUSE_MAX)
				humanoid:MoveTo(root.Position)
				controller.SetRunning(false)
			else
				humanoid.WalkSpeed = controller.Stats.Speed * controller.SpeedMultiplier * WALK_MULTIPLIER
				humanoid:MoveTo(destination)
				controller.SetRunning(true, WALK_MULTIPLIER)
			end
		elseif now >= pauseUntil then
			destination = zonePoint(zone)
			walkStarted = now
			if not destination then
				pauseUntil = now + 2
			end
		end
		return true
	end

	-- Apanhou: grita (medroso) ou provoca (valentão)
	local humanoid = controller.Humanoid
	local lastHealth = humanoid.Health
	humanoid.HealthChanged:Connect(function(health)
		local lost = health < lastHealth
		lastHealth = health
		if not lost then return end
		destination = nil
		if health <= 0 then
			if rng:NextNumber() < 0.5 then say(npc, pick(Lines.Death)) end
			return
		end
		local now = os.clock()
		if now < state.NextReact then return end
		state.NextReact = now + REACT_COOLDOWN
		say(npc, pick(if tough then Lines.Taunt else Lines.Hurt))
	end)
end

spawnCivilian = function(zone)
	local position = zonePoint(zone)
	local template = buildTemplate()
	if not position or not template then
		if template then template:Destroy() end
		task.delay(5, spawnCivilian, zone)
		return
	end
	local tough = rng:NextNumber() < zone.BrawlerChance
	local facing = rng:NextNumber(0, math.pi * 2)
	local cframe = CFrame.new(position + Vector3.new(0, 3, 0)) * CFrame.Angles(0, facing, 0)
	local npc, controller = EnemyModule.SpawnEnemy(template, cframe, {
		EnemyType = if tough then "CivilianTough" else "Civilian",
		Passive = true,
		Flee = not tough,
		AlertGroup = "Civilians",
		GiveRewards = rewardKiller,
		OnDied = function(deadNpc)
			civilians[deadNpc] = nil
			zone.Alive -= 1
			task.delay(zone.RespawnTime, function()
				if zone.Alive < zone.Max then
					zone.Alive += 1
					spawnCivilian(zone)
				end
			end)
		end,
	})
	template:Destroy()
	if not npc then
		zone.Alive -= 1
		return
	end
	npc:SetAttribute("Civilian", true)
	hookCivilian(zone, npc, controller, tough)
	-- Apagado por fora (sem morrer): sai da lista e libera a vaga
	npc.AncestryChanged:Connect(function(_, parent)
		if parent == nil and civilians[npc] then
			civilians[npc] = nil
			zone.Alive -= 1
		end
	end)
end

local function startZone(zone)
	for _ = 1, zone.Max do
		zone.Alive += 1
		task.spawn(spawnCivilian, zone)
		task.wait(0.2)
	end
end

local function zoneFromPart(part)
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Transparency = 1
	local function number(name, default)
		local value = part:GetAttribute(name)
		return if type(value) == "number" then value else default
	end
	return {
		Part = part,
		Max = math.max(0, math.floor(number("MaxCivilians", DEFAULT_MAX))),
		BrawlerChance = math.clamp(number("BrawlerChance", DEFAULT_BRAWLER), 0, 1),
		RespawnTime = math.max(3, number("RespawnTime", DEFAULT_RESPAWN)),
		Alive = 0,
	}
end

-- Cumprimentos: civil parado ou passeando sem alvo fala com quem chega perto
local function greetLoop()
	while true do
		task.wait(1)
		local now = os.clock()
		for npc, state in civilians do
			local root = npc:FindFirstChild("HumanoidRootPart")
			local humanoid = npc:FindFirstChildOfClass("Humanoid")
			if root and humanoid and humanoid.Health > 0 and now >= state.NextGreet and not npc:GetAttribute("Stunned") then
				for _, player in Players:GetPlayers() do
					local character = player.Character
					local playerRoot = character and character:FindFirstChild("HumanoidRootPart")
					if playerRoot and (playerRoot.Position - root.Position).Magnitude <= GREET_RANGE then
						state.NextGreet = now + rng:NextNumber(GREET_COOLDOWN[1], GREET_COOLDOWN[2])
						if humanoid.Health >= humanoid.MaxHealth then
							say(npc, pick(if state.Tough and rng:NextNumber() < 0.7 then Lines.ToughGreet else Lines.Greet))
						end
						break
					end
				end
			end
		end
	end
end

local function start()
	if not baseCharacter() then
		warn("[CivilianService] Sem StarterPlayer.StarterCharacter com Humanoid e HumanoidRootPart: sem civis")
		return
	end
	local folder = workspace:FindFirstChild("CivilianZones")
	local zones = {}
	if folder then
		for _, item in folder:GetDescendants() do
			if item:IsA("BasePart") then
				table.insert(zones, zoneFromPart(item))
			end
		end
	end
	if #zones == 0 then
		local spawn = workspace:FindFirstChildWhichIsA("SpawnLocation", true)
		local center = if spawn then spawn.Position else Vector3.new(0, 0, 0)
		table.insert(zones, {
			Center = center,
			Radius = FALLBACK_RADIUS,
			Max = FALLBACK_COUNT,
			BrawlerChance = DEFAULT_BRAWLER,
			RespawnTime = DEFAULT_RESPAWN,
			Alive = 0,
		})
	end
	for _, zone in zones do
		task.spawn(startZone, zone)
	end
	task.spawn(greetLoop)
end

if workspace:GetAttribute("CiviliansDisabled") ~= true then
	task.defer(start)
end
