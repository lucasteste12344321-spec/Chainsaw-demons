-- Chefes (ReplicatedStorage.BossData). Nascem parados onde o modelo foi colocado no Studio (ex.: sentado no trono),
-- levantam quando um jogador chega perto ou bate neles e lutam com a IA dos inimigos (EnemyModule, pelo controle
-- que o SpawnEnemy devolve). Por cima disso, aqui ficam:
--   ataques especiais com aviso vermelho no chão (Pisão, Investida, Fúria), fase 2 (grito, mais rápido, reforços),
--   reações próprias (apanhar, tontura no parry, morte), placar de dano por jogador (atributo BossDamage em JSON,
--   lido pela barra do chefe no cliente), recompensa, missão e drops para todo mundo que ajudou (MinContribution)
--   e renascer depois de RespawnTime.
-- Atributos no modelo do chefe: Boss, BossAwake, BossPhase, BossDamage, OwnHitReaction (+ os de inimigo).
-- Especiais (campo Specials do BossData): Slam, Rush, Fury, Chain (corrente que puxa) e BloodDrink (cura que dá para
-- interromper). Slam e Rush com Destroy = true quebram o mapa (Destruction).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage = game:GetService("ServerStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local HttpService = game:GetService("HttpService")
local Debris = game:GetService("Debris")

local BossData = require(ReplicatedStorage:WaitForChild("BossData"))
local ItemData = require(ReplicatedStorage:WaitForChild("ItemData"))
local CombatStyles = require(ReplicatedStorage:WaitForChild("CombatStyles"))
local Remotes = require(ReplicatedStorage:WaitForChild("Remotes"))
local EnemyModule = require(ServerScriptService:WaitForChild("EnemyModule"))
local CombatRules = require(ServerScriptService:WaitForChild("CombatRules"))
local CombatState = require(ServerScriptService:WaitForChild("CombatState"))
local PlayerData = require(ServerScriptService:WaitForChild("PlayerData"))
local QuestModule = require(ServerScriptService:WaitForChild("QuestModule"))
local Destruction = require(ServerScriptService:WaitForChild("Destruction"))

local TICK = 0.1
local PUBLISH_INTERVAL = 0.25 -- placar de dano para os clientes
local ANNOUNCE_RANGE = 120 -- quem recebe os avisos do chefe (acordou, fase 2)
local HIT_HEIGHT = 10 -- diferença de altura aceita nos ataques em área
local ROAR_FALLBACK = 0.6 -- sem o marcador do grito, os reforços chegam nesse tempo
local WARNING_COLOR = Color3.fromRGB(255, 40, 40)

local Passes = require(script.Parent.GamepassEntitlements)
local rng = Random.new()

local warnings = Instance.new("Folder")
warnings.Name = "BossWarnings"
warnings.Parent = workspace

local templates

local function flat(vector)
	return Vector3.new(vector.X, 0, vector.Z)
end

-- ================= Jogadores e área =================

local function livePlayers()
	local list = {}
	for _, player in Players:GetPlayers() do
		local character = player.Character
		local hrp = character and character:FindFirstChild("HumanoidRootPart")
		local hum = character and character:FindFirstChildOfClass("Humanoid")
		if hrp and hum and hum.Health > 0 then
			table.insert(list, { Player = player, Character = character, Root = hrp, Humanoid = hum })
		end
	end
	return list
end

local function playersInCircle(center, radius)
	local list = {}
	for _, entry in livePlayers() do
		local offset = entry.Root.Position - center
		if flat(offset).Magnitude <= radius and math.abs(offset.Y) <= HIT_HEIGHT then
			table.insert(list, entry)
		end
	end
	return list
end

-- Retângulo que sai de origin e vai length studs na direção direction, com largura width
local function playersInBox(origin, direction, length, width)
	local right = Vector3.new(-direction.Z, 0, direction.X)
	local list = {}
	for _, entry in livePlayers() do
		local offset = entry.Root.Position - origin
		local along = flat(offset):Dot(direction)
		local side = math.abs(flat(offset):Dot(right))
		if along >= -2 and along <= length + 1 and side <= width / 2 + 1 and math.abs(offset.Y) <= HIT_HEIGHT then
			table.insert(list, entry)
		end
	end
	return list
end

-- Chão embaixo de um ponto (o aviso fica colado nele)
local function groundBelow(position)
	local ignore = { warnings }
	local enemies = workspace:FindFirstChild("Enemies")
	if enemies then
		table.insert(ignore, enemies)
	end
	for _, entry in livePlayers() do
		table.insert(ignore, entry.Character)
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = ignore
	params.IgnoreWater = true
	local result = workspace:Raycast(position + Vector3.new(0, 2, 0), Vector3.new(0, -80, 0), params)
	return if result then result.Position else position - Vector3.new(0, 6, 0)
end

-- ================= Avisos no chão =================

local function warningPart(size, cframe, shape)
	local part = Instance.new("Part")
	part.Name = "BossWarning"
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Material = Enum.Material.Neon
	part.Color = WARNING_COLOR
	part.Transparency = 0.75
	if shape then
		part.Shape = shape
	end
	part.Size = size
	part.CFrame = cframe
	part.Parent = warnings
	return part
end

-- O aviso fica mais forte até a hora do golpe e some
local function telegraph(part, duration)
	TweenService:Create(part, TweenInfo.new(duration, Enum.EasingStyle.Linear), { Transparency = 0.3 }):Play()
	Debris:AddItem(part, duration + 0.05)
end

local function warnCircle(center, radius, duration)
	local cframe = CFrame.new(center + Vector3.new(0, 0.15, 0)) * CFrame.Angles(0, 0, math.rad(90))
	telegraph(warningPart(Vector3.new(0.3, radius * 2, radius * 2), cframe, Enum.PartType.Cylinder), duration)
end

local function warnBox(origin, direction, length, width, duration)
	local middle = origin + direction * (length / 2) + Vector3.new(0, 0.15, 0)
	telegraph(warningPart(Vector3.new(width, 0.3, length), CFrame.lookAt(middle, middle + direction)), duration)
end

-- Onda de choque (pisão e o corpo caindo)
local function shockwave(center, radius)
	local cframe = CFrame.new(center + Vector3.new(0, 0.3, 0)) * CFrame.Angles(0, 0, math.rad(90))
	local part = warningPart(Vector3.new(0.4, 4, 4), cframe, Enum.PartType.Cylinder)
	part.Color = Color3.fromRGB(255, 220, 180)
	part.Transparency = 0.2
	TweenService:Create(part, TweenInfo.new(0.35, Enum.EasingStyle.Quad), {
		Size = Vector3.new(0.4, radius * 2.2, radius * 2.2),
		Transparency = 1,
	}):Play()
	Debris:AddItem(part, 0.4)
end

-- ================= Dano, avisos e recompensa =================

-- Golpe especial num jogador: dano (guarda e parry valem), efeito, reação, atordoamento e empurrão (impulseTime
-- segundos, padrão 0,25). Devolve true se o golpe entrou.
local function hitPlayer(npc, entry, damage, velocity, stun, strong, impulseTime)
	local _, result = CombatRules.DamageFromNPC(entry.Humanoid, damage, npc)
	if result ~= "Hit" then return false end
	CombatState.FX("Hit", { Character = entry.Character, Attacker = npc, Strong = strong == true })
	if entry.Humanoid.Health <= 0 then return true end
	EnemyModule.PlayReaction(entry.Humanoid)
	if stun and stun > 0 then
		CombatRules.Stun(entry.Humanoid, stun, "Hit")
	end
	if velocity then
		Remotes.CombatImpulse:FireClient(entry.Player, velocity, impulseTime or 0.25)
	end
	return true
end

local function announce(position, title, text)
	for _, entry in livePlayers() do
		if (entry.Root.Position - position).Magnitude <= ANNOUNCE_RANGE then
			PlayerData.Notify(entry.Player, title, text, 4)
		end
	end
end

-- Todo mundo que tirou pelo menos MinContribution da vida ganha XP, Gold, a missão e sorteia os drops
local function giveRewards(state, humanoid, enemyType, stats, config)
	local needed = humanoid.MaxHealth * (config.MinContribution or 0)
	for userId, damage in state.Damage do
		local player = Players:GetPlayerByUserId(userId)
		if not player then continue end
		if damage < needed then
			PlayerData.Notify(player, `{stats.DisplayName} derrotado!`,
				`Você precisava causar pelo menos {math.ceil(needed)} de dano para ganhar a recompensa.`, 6)
			continue
		end
		local awardedXP = PlayerData.AddXP(player, stats.XP) or 0
		local awardedGold = PlayerData.AddGold(player, stats.Gold) or 0
		QuestModule.OnEnemyKilled(player, enemyType, stats.Level)
		local won = {}
		for _, drop in config.Drops or {} do
			local item = ItemData.Get(drop.Item)
			if item and rng:NextNumber() < Passes.DropChance(player, drop.Chance) and PlayerData.AddItem(player, drop.Item, 1) then
				table.insert(won, item.Name)
			end
		end
		local text = `+{awardedXP} XP e +{awardedGold} Gold.`
			.. (if #won > 0 then ` Drop: {table.concat(won, ", ")}!` else " Nenhum item desta vez.")
		PlayerData.Notify(player, `{stats.DisplayName} derrotado!`, text, 7)
	end
end

-- ================= Um chefe =================

local function runBoss(enemyType, config, npc, controller, state)
	local humanoid, root, stats = controller.Humanoid, controller.Root, controller.Stats
	local animator = humanoid:FindFirstChildOfClass("Animator")
	local specials = config.Specials or {}
	local phase2 = config.Phase2
	local throne = config.Throne
	local reactions = config.Reactions

	npc:SetAttribute("Boss", true)
	npc:SetAttribute("BossPhase", 1)
	npc:SetAttribute("BossAwake", throne == nil)
	if reactions then
		npc:SetAttribute("OwnHitReaction", true) -- o CombatService não toca a reação genérica
	end
	if reactions and reactions.Death then
		humanoid.BreakJointsOnDeath = false -- a animação de morte precisa das juntas
	end
	-- A barra do chefe (cliente) substitui a barrinha em cima da cabeça
	local billboard = npc:FindFirstChild("EnemyBar")
	if billboard then
		billboard:Destroy()
	end

	-- Só atordoamento longo (parry) para o chefe; os golpes comuns não
	controller.IgnoreStun = function()
		return CombatState.StunRemaining(humanoid) < (config.MinStun or 0)
	end
	local function stunnedHard()
		return npc:GetAttribute("Stunned") == true and not controller.IgnoreStun()
	end

	-- Não é arremessado: tira o empurrão que o CombatService põe na raiz
	if config.KnockbackImmune then
		root.ChildAdded:Connect(function(child)
			if child.Name == "CombatKnockback" then
				task.defer(function()
					if child.Parent then
						child:Destroy()
					end
				end)
			end
		end)
	end

	-- Animações próprias do chefe, carregadas uma vez por ID
	local tracks = {}
	local function trackFor(id, priority, looped)
		if not id or not animator then return nil end
		if tracks[id] == nil then
			tracks[id] = EnemyModule.LoadAnimation(animator, id, looped == true, priority or Enum.AnimationPriority.Action3) or false
		end
		return tracks[id] or nil
	end
	local throneTrack = throne and trackFor(throne.Animation, Enum.AnimationPriority.Action, true)

	local sleeping = false
	local phase = 1
	local nextSpecialAt = math.huge
	local specialRunning = false
	local pendingRoar = false
	local summons = {}
	local damageDirty = false
	local lastReaction = 0
	local drinking = nil -- BloodDrink em andamento: { Damage = dano levado desde o começo }
	local drinksUsed = 0

	local function alive()
		return humanoid.Health > 0 and npc.Parent ~= nil and not sleeping
	end

	local function publishDamage()
		local data = {}
		for userId, damage in state.Damage do
			data[tostring(userId)] = math.floor(damage)
		end
		npc:SetAttribute("BossDamage", HttpService:JSONEncode(data))
		damageDirty = false
	end

	local function clearSummons()
		for _, minion in summons do
			if minion.Parent then
				minion:Destroy()
			end
		end
		table.clear(summons)
	end

	local function setPhase(value)
		phase = value
		npc:SetAttribute("BossPhase", value)
		controller.SpeedMultiplier = if value == 2 and phase2 then (phase2.SpeedMultiplier or 1) else 1
	end

	local function summonReinforcements()
		local summon = phase2 and phase2.Summon
		local template = summon and templates:FindFirstChild(EnemyModule.GetTemplateName(summon.Type))
		if not template then return end
		local count = summon.Count or 0
		for i = 1, count do
			local angle = (i / count) * math.pi * 2
			local position = root.Position + Vector3.new(math.cos(angle) * 10, 2, math.sin(angle) * 10)
			local minion = EnemyModule.SpawnEnemy(template, CFrame.new(position), {
				EnemyType = summon.Type,
				Level = summon.Level,
				Home = position,
				IgnoreAggroLimit = true,
			})
			if minion then
				table.insert(summons, minion)
			end
		end
	end

	-- Fase 2: já fica mais rápido; o grito (e os reforços) sai assim que ele terminar o que está fazendo
	local function enterPhase2()
		setPhase(2)
		pendingRoar = true
	end

	local function roar()
		pendingRoar = false
		local fired = false
		local function onRoar()
			if fired or not alive() then return end
			fired = true
			if phase2.Message then
				announce(root.Position, stats.DisplayName, phase2.Message)
			end
			summonReinforcements()
		end
		local track = trackFor(phase2.RoarAnimation)
		if not track then
			onRoar()
			return
		end
		local connections = CombatStyles.OnMarker(track, phase2.RoarMarker, onRoar)
		track:Play(0.1)
		task.delay(ROAR_FALLBACK, onRoar)
		task.wait(if track.Length > 0 then track.Length else 1.75)
		for _, connection in connections do
			connection:Disconnect()
		end
		onRoar()
	end

	-- Senta no trono: vida cheia, placar zerado, fase 1, reforços somem
	local function sleep()
		if not throne or humanoid.Health <= 0 then return end
		sleeping = true
		pendingRoar = false
		controller.Paused = true
		controller.CancelAttack()
		controller.StopMover()
		controller.ReleaseFacing()
		controller.SetRunning(false)
		humanoid:MoveTo(root.Position)
		npc:PivotTo(controller.HomeCFrame + (throne.SitOffset or Vector3.zero))
		root.Anchored = true
		humanoid.Health = humanoid.MaxHealth
		table.clear(state.Damage)
		publishDamage()
		setPhase(1)
		clearSummons()
		if throneTrack then
			throneTrack:Play(0.4)
		end
		npc:SetAttribute("BossAwake", false)
	end

	-- Levanta: a animação toca enquanto ele sobe do assento até onde o modelo foi colocado, depois luta
	local function wake()
		if not sleeping or humanoid.Health <= 0 then return end
		sleeping = false
		npc:SetAttribute("BossAwake", true)
		announce(root.Position, stats.DisplayName, throne.WakeMessage or "Levantou do trono!")
		if throneTrack then
			throneTrack:Stop(0.25)
		end
		local standTrack = trackFor(throne.StandUpAnimation, Enum.AnimationPriority.Action)
		if standTrack then
			standTrack:Play(0.15)
		end
		local standUp = throne.StandUpTime or 1
		nextSpecialAt = os.clock() + standUp + (specials.FirstDelay or 3)
		local from, to = npc:GetPivot(), controller.HomeCFrame
		task.spawn(function()
			local start = os.clock()
			while not sleeping and humanoid.Health > 0 do
				local alpha = math.clamp((os.clock() - start) / standUp, 0, 1)
				npc:PivotTo(from:Lerp(to, alpha))
				if alpha >= 1 then break end
				RunService.Heartbeat:Wait()
			end
			if sleeping or humanoid.Health <= 0 then return end
			root.Anchored = false
			if root:CanSetNetworkOwnership() then
				root:SetNetworkOwner(nil)
			end
			if not specialRunning then
				controller.Paused = false
			end
		end)
	end

	-- Sem ninguém por perto: volta para o trono e senta
	controller.OnIdle = function(distFromHome)
		if not throne then return false end
		if distFromHome <= 12 then
			sleep()
		else
			humanoid.WalkSpeed = stats.Speed
			humanoid:MoveTo(controller.Home)
			controller.SetRunning(true)
		end
		return true
	end
	controller.OnReturnedHome = sleep

	-- Reação de apanhar: de frente ou de lado conforme de onde veio o golpe (só fora de ataque e com intervalo)
	local function react(attackerId)
		if not reactions or not alive() or specialRunning or controller.IsBusy() or stunnedHard() then return end
		local clock = os.clock()
		if clock - lastReaction < (reactions.Interval or 0.6) then return end
		lastReaction = clock
		local attacker = type(attackerId) == "number" and Players:GetPlayerByUserId(attackerId)
		local attackerRoot = attacker and attacker.Character and attacker.Character:FindFirstChild("HumanoidRootPart")
		local id = reactions.Front
		if attackerRoot then
			local toAttacker = flat(attackerRoot.Position - root.Position)
			local look = flat(root.CFrame.LookVector)
			if toAttacker.Magnitude > 0.1 and look.Magnitude > 0.1 and look.Unit:Dot(toAttacker.Unit) < 0.5 then
				id = reactions.Side or id
			end
		end
		local track = trackFor(id, Enum.AnimationPriority.Action2)
		if track then
			track:Play(0.05)
		end
	end

	-- Tontura: no atordoamento longo (parry) toca a tontura; o especial em andamento para sozinho
	if reactions and reactions.Stagger then
		npc:GetAttributeChangedSignal("Stunned"):Connect(function()
			local track = trackFor(reactions.Stagger, Enum.AnimationPriority.Action4)
			if not track or humanoid.Health <= 0 then return end
			if stunnedHard() then
				track:Play(0.1)
			elseif track.IsPlaying then
				track:Stop(0.25)
			end
		end)
	end

	-- Morte: animação inteira no lugar (raiz ancorada, sem desmontar); o corpo caindo levanta poeira
	if reactions and reactions.Death then
		humanoid.Died:Connect(function()
			for _, track in animator:GetPlayingAnimationTracks() do
				track:Stop(0.2)
			end
			root.Anchored = true
			local track = trackFor(reactions.Death, Enum.AnimationPriority.Action4)
			if not track then return end
			local landed = false
			local connections
			connections = CombatStyles.OnMarker(track, reactions.LandMarker, function()
				for _, connection in connections do
					connection:Disconnect()
				end
				if not landed then
					landed = true
					shockwave(groundBelow(root.Position), 12)
				end
			end)
			track:Play(0.1)
		end)
	end

	-- Placar de dano (LastAttacker é marcado pelo CombatRules antes de cada dano), acordar, reação e fase 2
	local lastHealth = humanoid.Health
	humanoid.HealthChanged:Connect(function(health)
		local lost = lastHealth - health
		lastHealth = health
		if lost <= 0 then return end
		local attackerId = humanoid:GetAttribute("LastAttacker")
		if type(attackerId) == "number" then
			state.Damage[attackerId] = (state.Damage[attackerId] or 0) + lost
			damageDirty = true
		end
		if drinking then
			drinking.Damage += lost
		end
		if sleeping then
			wake()
		elseif health > 0 then
			react(attackerId)
		end
		if phase == 1 and phase2 and health > 0 and health <= humanoid.MaxHealth * phase2.At then
			enterPhase2()
		end
	end)

	-- ----- Especiais -----

	-- Pisão: círculo em volta; congela na pose de carga e solta para o impacto bater no fim do aviso
	local function slam(cfg, targetHrp)
		controller.SnapFacing(targetHrp.Position)
		local center = groundBelow(root.Position)
		warnCircle(center, cfg.Radius, cfg.Telegraph)
		local track = trackFor(cfg.Animation)
		if track then
			track:Play(0.1)
			local connections
			connections = CombatStyles.OnMarker(track, cfg.ChargeMarker, function()
				for _, connection in connections do
					connection:Disconnect()
				end
				track:AdjustSpeed(0)
			end)
			task.delay(math.max(0, cfg.Telegraph - (cfg.PowerTime or 0)), function()
				for _, connection in connections do
					connection:Disconnect()
				end
				if track.IsPlaying then
					track:AdjustSpeed(1)
				end
			end)
		end
		task.wait(cfg.Telegraph)
		if not alive() or stunnedHard() then return end
		shockwave(center, cfg.Radius)
		if cfg.Destroy then
			Destruction.Blast(center + Vector3.new(0, 2, 0), cfg.Radius * 0.7, { Power = 60 })
		end
		for _, entry in playersInCircle(center, cfg.Radius) do
			local away = flat(entry.Root.Position - center)
			away = if away.Magnitude > 0.1 then away.Unit else flat(root.CFrame.LookVector).Unit
			local push = away * cfg.Knockback + Vector3.new(0, cfg.Knockback * 0.5, 0)
			hitPlayer(npc, entry, stats.Damage * cfg.Damage, push, cfg.Stun, true)
		end
		task.wait(0.5)
	end

	-- Investida: faixa até o alvo; atravessa a faixa e acerta cada jogador do caminho uma vez
	local function rush(cfg, targetHrp)
		local toTarget = flat(targetHrp.Position - root.Position)
		if toTarget.Magnitude < 1 then return end
		local direction = toTarget.Unit
		local length = math.min(cfg.Distance, toTarget.Magnitude + 6)
		controller.SnapFacing(root.Position + direction)
		warnBox(groundBelow(root.Position), direction, length, cfg.Width, cfg.Telegraph)
		task.wait(cfg.Telegraph)
		if not alive() or stunnedHard() then return end
		local track = trackFor(cfg.Animation, nil, cfg.Looped)
		if track then
			track:Play(0.05)
		end
		local duration = length / cfg.Speed
		controller.StartMover(direction * cfg.Speed, duration)
		local hit = {}
		local startTime = os.clock()
		local brokenAt = nil -- quebra o mapa no caminho a cada 5 studs
		while os.clock() - startTime < duration and alive() and not stunnedHard() do
			if cfg.Destroy and (not brokenAt or (root.Position - brokenAt).Magnitude >= 5) then
				brokenAt = root.Position
				Destruction.Blast(root.Position + direction * 3, cfg.Width / 2 + 1, { Power = 60 })
			end
			for _, entry in playersInCircle(root.Position, cfg.Width / 2 + 2) do
				if not hit[entry.Player] then
					hit[entry.Player] = true
					local rel = flat(entry.Root.Position - root.Position)
					local side = rel - direction * rel:Dot(direction)
					side = if side.Magnitude > 0.1 then side.Unit else Vector3.new(-direction.Z, 0, direction.X)
					local push = (side + direction).Unit * cfg.Knockback + Vector3.new(0, cfg.Knockback * 0.35, 0)
					hitPlayer(npc, entry, stats.Damage * cfg.Damage, push, cfg.Stun, true)
				end
			end
			task.wait()
		end
		controller.StopMover()
		if track and track.IsPlaying then
			track:Stop(0.2)
		end
		task.wait(0.4)
	end

	-- Fúria: retângulo na frente; vários socos rápidos, o último arremessa
	local function fury(cfg, targetHrp)
		controller.SnapFacing(targetHrp.Position)
		local look = flat(root.CFrame.LookVector)
		look = if look.Magnitude > 0.01 then look.Unit else Vector3.new(0, 0, -1)
		warnBox(groundBelow(root.Position), look, cfg.Range, cfg.Width, cfg.Telegraph)
		task.wait(cfg.Telegraph)
		if not alive() or stunnedHard() then return end
		local track = trackFor(cfg.Animation)
		if track then
			track:Play(0.05)
		end
		for i = 1, cfg.Hits do
			if not alive() or stunnedHard() then break end
			local last = i == cfg.Hits
			for _, entry in playersInBox(root.Position, look, cfg.Range, cfg.Width) do
				local push = if last then look * cfg.Knockback + Vector3.new(0, cfg.Knockback * 0.3, 0) else nil
				hitPlayer(npc, entry, stats.Damage * cfg.Damage, push, if last then 0.5 else cfg.Stun, last)
			end
			task.wait(cfg.Interval)
		end
		task.wait(0.3)
	end

	-- Corrente: linha até o alvo; o primeiro jogador na linha é puxado até o chefe e leva um corte ao chegar
	local function chain(cfg, targetHrp)
		local toTarget = flat(targetHrp.Position - root.Position)
		if toTarget.Magnitude < 1 then return end
		local direction = toTarget.Unit
		local length = math.min(cfg.Range, toTarget.Magnitude + 3)
		controller.SnapFacing(root.Position + direction)
		warnBox(groundBelow(root.Position), direction, length, cfg.Width, cfg.Telegraph)
		task.wait(cfg.Telegraph)
		if not alive() or stunnedHard() then return end

		-- O mais perto dele dentro da faixa
		local caught, nearest = nil, math.huge
		for _, entry in playersInBox(root.Position, direction, length, cfg.Width) do
			local along = flat(entry.Root.Position - root.Position):Dot(direction)
			if along < nearest then
				caught, nearest = entry, along
			end
		end

		-- A corrente: estica até onde pegou (ou até o fim da linha, se errou) e volta
		local tip = if caught then caught.Root else nil
		local missPoint = root.Position + direction * length
		local link = Instance.new("Part")
		link.Name = "BossChain"
		link.Anchored = true
		link.CanCollide = false
		link.CanQuery = false
		link.CanTouch = false
		link.CastShadow = false
		link.Material = Enum.Material.DiamondPlate
		link.Color = Color3.fromRGB(120, 120, 128)
		link.Parent = warnings
		local function drawChain()
			local from = root.Position + Vector3.new(0, 0.5, 0)
			local to = if tip and tip.Parent then tip.Position else missPoint
			local gap = (to - from).Magnitude
			link.Size = Vector3.new(0.35, 0.35, math.max(gap, 0.1))
			link.CFrame = CFrame.lookAt(from:Lerp(to, 0.5), to)
		end
		drawChain()

		if not caught then
			task.wait(0.3)
			link:Destroy()
			task.wait(0.3)
			return
		end
		local pullTime = math.clamp((nearest - 3.5) / cfg.PullSpeed, 0.08, 0.6)
		local pull = -direction * cfg.PullSpeed + Vector3.new(0, 4, 0)
		local held = hitPlayer(npc, caught, stats.Damage * cfg.Damage, pull, pullTime + cfg.Stun, false, pullTime)
		if not held then
			link:Destroy()
			task.wait(0.4)
			return
		end
		local startTime = os.clock()
		while os.clock() - startTime < pullTime and alive() do
			drawChain()
			RunService.Heartbeat:Wait()
		end
		link:Destroy()
		if not alive() or stunnedHard() then return end
		local push = direction * cfg.SlashKnockback + Vector3.new(0, cfg.SlashKnockback * 0.3, 0)
		hitPlayer(npc, caught, stats.Damage * cfg.SlashDamage, push, cfg.Stun, true)
		task.wait(0.4)
	end

	-- Beber sangue: para, fica vermelho e se cura aos poucos; apanhar demais nesse tempo interrompe (fica tonto)
	local function bloodDrink(cfg)
		drinksUsed += 1
		if cfg.Message then
			announce(root.Position, stats.DisplayName, cfg.Message)
		end
		local glow = Instance.new("Highlight")
		glow.Name = "BloodDrink"
		glow.FillColor = Color3.fromRGB(200, 0, 20)
		glow.OutlineColor = Color3.fromRGB(255, 60, 60)
		glow.FillTransparency = 0.55
		glow.Parent = npc
		local track = cfg.Animation and trackFor(cfg.Animation)
		if track then
			track:Play(0.1)
		end
		drinking = { Damage = 0 }
		local steps = math.max(1, math.floor(cfg.Duration / 0.25))
		local perStep = humanoid.MaxHealth * cfg.Heal / steps
		local interrupted = false
		for _ = 1, steps do
			task.wait(0.25)
			if not alive() or stunnedHard() then break end
			if drinking.Damage >= humanoid.MaxHealth * cfg.InterruptDamage then
				interrupted = true
				break
			end
			humanoid.Health = math.min(humanoid.MaxHealth, humanoid.Health + perStep)
		end
		drinking = nil
		glow:Destroy()
		if track and track.IsPlaying then
			track:Stop(0.2)
		end
		if interrupted and alive() then
			announce(root.Position, stats.DisplayName, "Interrompido!")
			CombatState.Stun(humanoid, cfg.InterruptStun, true)
		end
	end

	local SPECIALS = { Slam = slam, Rush = rush, Fury = fury, Chain = chain }

	-- Longe: investida. Perto: pisão (sempre, se tiver 2+ jogadores em volta) ou fúria.
	local function chooseSpecial(targetHrp)
		local dist = flat(targetHrp.Position - root.Position).Magnitude
		local choices = {}
		local slamCfg, rushCfg, furyCfg = specials.Slam, specials.Rush, specials.Fury
		if rushCfg and dist >= rushCfg.MinRange and dist <= rushCfg.Distance then
			table.insert(choices, "Rush")
		end
		if slamCfg and dist <= slamCfg.Radius * 0.75 then
			if #playersInCircle(root.Position, slamCfg.Radius) >= 2 then
				return "Slam"
			end
			table.insert(choices, "Slam")
		end
		if furyCfg and dist <= furyCfg.Range then
			table.insert(choices, "Fury")
		end
		local chainCfg = specials.Chain
		if chainCfg and dist >= chainCfg.MinRange and dist <= chainCfg.Range then
			table.insert(choices, "Chain")
		end
		if #choices == 0 then return nil end
		return choices[rng:NextInteger(1, #choices)]
	end

	-- Um especial ou o grito: a IA para enquanto ele acontece
	local function perform(name, action, ...)
		specialRunning = true
		controller.Paused = true
		controller.SetRunning(false)
		humanoid:MoveTo(root.Position)
		local ok, err = pcall(action, ...)
		if not ok then
			warn(`[BossService] {name} de {npc.Name} falhou: {err}`)
		end
		specialRunning = false
		if not sleeping and humanoid.Health > 0 then
			controller.Paused = false
		end
	end

	-- Nasce sentado
	if throne then
		sleep()
	else
		nextSpecialAt = os.clock() + (specials.FirstDelay or 3)
	end

	task.spawn(function()
		local lastPublish = 0
		while humanoid.Health > 0 and npc.Parent do
			task.wait(TICK)
			local clock = os.clock()
			if damageDirty and clock - lastPublish >= PUBLISH_INTERVAL then
				lastPublish = clock
				publishDamage()
			end

			if sleeping then
				-- Alguém chegou perto do trono: levanta
				for _, entry in livePlayers() do
					if (entry.Root.Position - root.Position).Magnitude <= throne.WakeRange then
						wake()
						break
					end
				end
				continue
			end

			if specialRunning or controller.Paused then continue end
			if controller.IsBusy() or stunnedHard() then continue end

			if pendingRoar then
				perform("Grito", roar)
				continue
			end

			-- Vida baixa na fase 2: bebe sangue (fora da recarga dos especiais)
			local drink = specials.BloodDrink
			if drink and phase == 2 and drinksUsed < (drink.Uses or 1)
				and humanoid.Health <= humanoid.MaxHealth * drink.At then
				perform("Beber sangue", bloodDrink, drink)
				nextSpecialAt = os.clock() + 1.5
				continue
			end

			if clock < nextSpecialAt then continue end
			local targetHrp = controller.GetTarget()
			if not targetHrp then continue end
			local kind = chooseSpecial(targetHrp)
			if not kind then continue end
			perform(kind, SPECIALS[kind], specials[kind], targetHrp)
			local multiplier = if phase == 2 and phase2 then (phase2.CooldownMultiplier or 1) else 1
			nextSpecialAt = os.clock() + (specials.Cooldown or 6) * multiplier
		end
		if damageDirty and npc.Parent then
			publishDamage()
		end
	end)
end

-- Nasce onde o modelo foi colocado no Studio e renasce RespawnTime segundos depois de morrer
local function spawnBoss(enemyType, config)
	local templateName = EnemyModule.GetTemplateName(enemyType)
	local template = templates:WaitForChild(templateName, 15)
	if not template then
		warn(`[BossService] Não existe EnemyTemplates.{templateName} (chefe {enemyType})`)
		return
	end
	local state = { Damage = {} }
	local cframe = template:GetPivot()
	local npc, controller = EnemyModule.SpawnEnemy(template, cframe, {
		EnemyType = enemyType,
		Home = cframe.Position,
		HomeCFrame = cframe,
		IgnoreAggroLimit = true,
		GiveRewards = function(humanoid, _, stats)
			giveRewards(state, humanoid, enemyType, stats, config)
		end,
		OnDied = function()
			task.wait(config.RespawnTime or 300)
			spawnBoss(enemyType, config)
		end,
	})
	if npc and controller then
		runBoss(enemyType, config, npc, controller, state)
	end
end

-- Os modelos ficam em ServerStorage.EnemyTemplates (o Spawner tira do workspace)
templates = ServerStorage:WaitForChild("EnemyTemplates", 30)
if not templates then
	warn("[BossService] Nenhuma pasta EnemyTemplates: nenhum chefe vai nascer.")
	return
end
for enemyType, config in BossData.Bosses do
	task.spawn(spawnBoss, enemyType, config)
end
