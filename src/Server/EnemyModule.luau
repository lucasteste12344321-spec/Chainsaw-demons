-- Inimigos: spawn, IA (persegue, ataca, volta para casa) e recompensas ao morrer.
-- Os stats de cada tipo ficam em EnemyData. Vários tipos podem reusar o mesmo modelo (campo Template),
-- mudando a cor (Tint) e o tamanho (Scale): assim há inimigos do level 1 ao 40+ com um só modelo.
-- Animações, arma na mão, combo e dash de cada modelo ficam em EnemyKits.
--
-- IA (a cada AI_TICK):
--   sem alvo: anda um pouco em volta de onde nasceu
--   longe do alvo: corre até ele mirando para onde ele vai, com dash para encurtar; travou num obstáculo, pula;
--     continuou travado, calcula um caminho (PathfindingService)
--   perto: fica virado para o alvo, ataca em combo (com um passo para a frente) e, na recarga, anda de lado em
--     volta dele
--   apanhou: persegue quem bateu e chama os inimigos em volta (ALERT_RANGE) para o mesmo alvo
-- O golpe no jogador tem efeito, reação de apanhar e atordoamento curto (sem stunlock: NPC_STUN_GAP); o último do
-- combo bate mais forte e empurra.
--
-- SpawnEnemy devolve (npc, controle). O controle deixa outro sistema (ex.: BossService) comandar o inimigo sem
-- reescrever a IA: pausar, virar, empurrar, ver o alvo, mudar a velocidade e ser avisado sem alvo / em casa.
local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local PathfindingService = game:GetService("PathfindingService")

local CombatRules = require(script.Parent:WaitForChild("CombatRules"))
local CombatState = require(script.Parent:WaitForChild("CombatState"))
local EnemyData = require(script.Parent:WaitForChild("EnemyData"))
local EnemyKits = require(script.Parent:WaitForChild("EnemyKits"))
local PlayerData = require(script.Parent:WaitForChild("PlayerData"))
local QuestModule = require(script.Parent:WaitForChild("QuestModule"))
local CombatStyles = require(ReplicatedStorage:WaitForChild("CombatStyles"))
local Remotes = require(ReplicatedStorage:WaitForChild("Remotes"))
local StatConfig = require(ReplicatedStorage:WaitForChild("StatConfig"))

local EnemyModule = {}

local AI_TICK = 0.1
local CORPSE_TIME = 3
local DEVOURED_TIME = 1.5 -- corpo devorado pelo Kon (os clientes já o esconderam): só o tempo de eles copiarem
local AGGRO_ON_HIT_TIME = 10 -- segundos perseguindo quem bateu, mesmo fora do AggroRange
local ALERT_RANGE = 28 -- quem apanha chama os inimigos até essa distância para o mesmo alvo
local RETURN_TIMEOUT = 15 -- se não conseguir voltar para casa andando, teleporta
-- Perseguição (2026-10-01, pedido do usuário: o inimigo largava a luta no meio, voltava para a área e curava tudo):
-- perseguindo alguém, só desiste bem longe de casa (LeashRange x CHASE_LEASH_MULTIPLIER) ou quando o alvo some de
-- vista (LOSE_RANGE dele). Sem alvo, o limite continua o LeashRange. Voltar para casa não cura mais (só o chefe, que
-- recomeça a luta): a vida volta devagar depois de REGEN_DELAY segundos sem apanhar e sem alvo.
local CHASE_LEASH_MULTIPLIER = 3.5
local LOSE_RANGE = 110
local REGEN_DELAY = 8
local REGEN_RATE = 0.04 -- fração da vida máxima por segundo
local TINT_STRENGTH = 0.6 -- padrão do quanto o Tint cobre a cor original (0 a 1)
local ATTACK_RANGE_MARGIN = 2 -- no momento do acerto o alvo pode estar até AttackRange + isso
local NPC_STUN_GAP = 1.2 -- depois de um atordoamento de inimigo, o jogador fica esse tempo sem levar outro (anti-stunlock)
local HIT_REACTION_GAP = 0.3 -- reação própria de apanhar (kit Hit): no máximo uma a cada isso
-- Ajuste geral de dificuldade (2026-10-01, teste com amigos: "muito difícil upar", NPC forte e batendo no meio do M1).
-- Vale para todos os tipos e chefes, por cima do EnemyData e da curva de level.
local BALANCE = {
	Damage = 0.65, -- dano dos golpes (e dos especiais dos chefes, que usam o Damage como base)
	AttackCooldown = 1.25, -- recarga entre um combo e outro
	AttackSpeed = 0.8, -- velocidade da animação de golpe: o corte sai mais tarde (dá para reagir e bloquear)
	XP = 1.25,
}
-- Prioridade de quem bateu primeiro: M1 do jogador começado antes do golpe do inimigo (e com o inimigo na frente,
-- no alcance) cancela o golpe do inimigo, porque o do jogador vai chegar e atordoar. Vale por este tempo depois do
-- começo do M1 (o acerto do jogador chega no marcador de impacto + ping). Chefes não entram nisso.
local PRIORITY_WINDOW = 0.45
-- Por detecção (só chegando perto), no máximo esses inimigos perseguem o mesmo jogador. Quem apanha e os que ele
-- chama (ALERT_RANGE) não têm limite: o jogador decide quantos puxa.
local DETECTION_LIMIT = 2
local STUCK_TIME = 0.7 -- perseguindo sem sair do lugar: pula; o dobro disso: calcula um caminho
local PATH_DURATION = 4 -- segundos seguindo um caminho calculado antes de voltar a correr direto
local STRAFE_SPEED = 0.5 -- velocidade andando de lado na recarga (fração da Speed)
local WANDER_SPEED = 0.4 -- velocidade passeando sem alvo
local WALK_BELOW = 0.75 -- abaixo dessa fração da velocidade, anda (Walk do kit) em vez de correr
local BODY_COLOR_PROPS = { "HeadColor3", "TorsoColor3", "LeftArmColor3", "RightArmColor3", "LeftLegColor3", "RightLegColor3" }
local PUNHOS = CombatStyles.Styles.Punhos -- reação de quem apanha (animações "Hit") e sons do acerto

-- Usado para tipos sem entrada em EnemyData e para campos que faltarem numa entrada
local DEFAULT_STATS = {
	Level = 1,
	Health = 100,
	Damage = 13,
	Speed = 16,
	AggroRange = 35,
	AttackRange = 4,
	AttackCooldown = 0.8,
	LeashRange = 70,
	XP = 38,
	Gold = 8,
}

local rng = Random.new()
-- Inimigos vivos: [npc] = função chamada quando alguém do grupo apanha (recebe o jogador que bateu)
local alertHandlers = {}
-- [Humanoid do jogador] = até quando golpe de inimigo não atordoa de novo. Tabela comum (com chave fraca a entrada podia
-- sumir na coleta de lixo e o intervalo contra stunlock falhava); cada entrada sai ao vencer, mesmo sem outro golpe.
local npcStunUntil = {}
-- [jogador] = { [npc] = true }: quem está perseguindo cada jogador agora (para o DETECTION_LIMIT)
local chasers = {}

-- Nome do modelo em ServerStorage.EnemyTemplates usado por um tipo (campo Template ou o próprio tipo)
function EnemyModule.GetTemplateName(enemyType)
	local data = EnemyData[enemyType]
	if data and type(data.Template) == "string" and data.Template ~= "" then
		return data.Template
	end
	return enemyType
end

-- Curva de um inimigo comum de level L (a mesma do comentário do EnemyData)
local function curve(level)
	return {
		Health = 100 + 60 * (level - 1),
		Damage = 13 + 3.2 * (level - 1),
		XP = 23 + 15 * level,
		Gold = 5 + 3 * level,
	}
end

function EnemyModule.GetStats(enemyType, level)
	local base = EnemyData[enemyType] or {}
	local stats = table.clone(DEFAULT_STATS)
	for key, value in base do
		stats[key] = value
	end
	stats.DisplayName = base.DisplayName or enemyType
	stats.Scale = if type(base.Scale) == "number" and base.Scale > 0 then base.Scale else 1

	-- Zona com Level diferente do base do tipo: os números seguem a curva padrão (ver curve), mantendo a
	-- proporção do tipo (elite continua elite). Um Goblin level 10 fica como um inimigo comum de level 10.
	local baseLevel = stats.Level
	level = if type(level) == "number" then math.clamp(math.floor(level), 1, StatConfig.MaxLevel) else baseLevel
	local from, to = curve(baseLevel), curve(level)

	stats.Level = level
	stats.Health = math.floor(stats.Health * to.Health / from.Health)
	stats.Damage = stats.Damage * to.Damage / from.Damage
	stats.XP = math.floor(stats.XP * to.XP / from.XP * BALANCE.XP)
	stats.Gold = math.floor(stats.Gold * to.Gold / from.Gold)
	stats.Damage *= BALANCE.Damage
	stats.AttackCooldown *= BALANCE.AttackCooldown
	-- Inimigo maior alcança mais longe
	stats.AttackRange *= math.max(1, stats.Scale)
	return stats
end

local function getEnemiesFolder()
	local folder = workspace:FindFirstChild("Enemies")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "Enemies"
		folder.Parent = workspace
	end
	return folder
end

local function aliveCharacter(player)
	local char = player and player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if hrp and hum and hum.Health > 0 then
		return hrp, hum
	end
	return nil, nil
end

-- Quantos inimigos (fora except) estão perseguindo o jogador
local function chaserCount(player, except)
	local count = 0
	for npc in chasers[player] or {} do
		if npc ~= except then
			count += 1
		end
	end
	return count
end

-- Marca quem o inimigo está perseguindo (nil: ninguém)
local function setChasing(npc, player)
	for other, set in chasers do
		if other ~= player then
			set[npc] = nil
		end
	end
	if player then
		chasers[player] = chasers[player] or {}
		chasers[player][npc] = true
	end
end

Players.PlayerRemoving:Connect(function(player)
	chasers[player] = nil
end)

-- Jogador vivo mais perto dentro de maxRange. Com limitFor (o inimigo que está procurando), pula quem já tem
-- DETECTION_LIMIT inimigos atrás dele.
local function findClosestPlayer(position, maxRange, limitFor)
	local closestHrp, closestHum, closestDist, closestPlayer = nil, nil, maxRange, nil
	for _, player in Players:GetPlayers() do
		local hrp, hum = aliveCharacter(player)
		if hrp and (not limitFor or chaserCount(player, limitFor) < DETECTION_LIMIT) then
			local dist = (hrp.Position - position).Magnitude
			if dist <= closestDist then
				closestHrp, closestHum, closestDist, closestPlayer = hrp, hum, dist, player
			end
		end
	end
	return closestHrp, closestHum, closestDist, closestPlayer
end

-- Distância só no plano (ignora a altura): a casa de um chefe pode ficar em cima do trono
local function flatDistance(a, b)
	return Vector3.new(a.X - b.X, 0, a.Z - b.Z).Magnitude
end

-- Avisa os inimigos perto de position que player atacou alguém do grupo
local function alertNearby(source, player, position)
	for npc, handler in alertHandlers do
		if npc ~= source then
			local root = npc:FindFirstChild("HumanoidRootPart")
			if root and (root.Position - position).Magnitude <= ALERT_RANGE then
				handler(player)
			end
		end
	end
end

local function loadTrack(animator, folder, name, looped)
	local anim = folder and folder:FindFirstChild(name)
	if not anim then return nil end
	local track = animator:LoadAnimation(anim)
	track.Looped = looped
	return track
end

-- Animação por ID (número > 0), ou nil
local function loadKitTrack(animator, id, looped, priority)
	if type(id) ~= "number" or id <= 0 then return nil end
	local animation = Instance.new("Animation")
	animation.AnimationId = "rbxassetid://" .. id
	local ok, track = pcall(function()
		return animator:LoadAnimation(animation)
	end)
	if not ok or not track then
		warn(`[EnemyModule] Não foi possível carregar a animação {id}: {track}`)
		return nil
	end
	track.Looped = looped
	track.Priority = priority
	return track
end
EnemyModule.LoadAnimation = loadKitTrack

-- Reação de quem apanha (animação "Hit" dos Punhos), tocada pelo servidor como no CombatService
local function playReaction(humanoid)
	local id = CombatStyles.Animation(PUNHOS, "Hit", rng:NextInteger(1, 2))
	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not id or not animator then return end
	local animation = Instance.new("Animation")
	animation.AnimationId = "rbxassetid://" .. id
	local ok, track = pcall(function()
		return animator:LoadAnimation(animation)
	end)
	animation:Destroy()
	if not ok or not track then return end
	track.Priority = Enum.AnimationPriority.Action2
	track.Looped = false
	track:Play(0.05)
	Debris:AddItem(track, 4)
end
EnemyModule.PlayReaction = playReaction

-- Golpe de inimigo que acertou um jogador (result "Hit" do CombatRules): efeito, reação, atordoamento e,
-- no último golpe do combo, empurrão. Guarda, parry e quebra de guarda já têm efeito próprio no CombatState.
local function onTargetHit(npc, root, targetHum, kit, finisher)
	local victim = targetHum.Parent
	if not victim then return end
	CombatState.FX("Hit", { Character = victim, Attacker = npc, Strong = finisher })
	if targetHum.Health <= 0 then return end
	playReaction(targetHum)

	local clock = os.clock()
	local stun = if finisher then kit.FinisherStun else kit.HitStun
	if type(stun) == "number" and stun > 0 and (npcStunUntil[targetHum] or 0) <= clock then
		CombatRules.Stun(targetHum, stun, "Hit")
		local expires = clock + stun + NPC_STUN_GAP
		npcStunUntil[targetHum] = expires
		task.delay(stun + NPC_STUN_GAP, function()
			-- Uma limpeza antiga não pode apagar o intervalo de um golpe mais recente.
			if npcStunUntil[targetHum] == expires then
				npcStunUntil[targetHum] = nil
			end
		end)
	end

	local knockback = kit.FinisherKnockback
	local player = Players:GetPlayerFromCharacter(victim)
	local victimRoot = victim:FindFirstChild("HumanoidRootPart")
	if finisher and player and victimRoot and type(knockback) == "number" and knockback > 0 then
		local offset = victimRoot.Position - root.Position
		local flat = Vector3.new(offset.X, 0, offset.Z)
		flat = if flat.Magnitude > 0.1 then flat.Unit else root.CFrame.LookVector
		Remotes.CombatImpulse:FireClient(player, flat * knockback + Vector3.new(0, 12, 0), 0.2)
	end
end

-- Peças com o atributo KeepColor (a arma) e o que está dentro delas não recebem o Tint
local function keepsColor(instance)
	return instance:GetAttribute("KeepColor") == true
		or (instance.Parent ~= nil and instance.Parent:GetAttribute("KeepColor") == true)
end

-- Mistura a cor Tint nas partes, nas texturas de SpecialMesh e no BodyColors (que recolore o corpo)
local function applyTint(npc, tint, strength)
	local vertexColor = Vector3.new(1, 1, 1):Lerp(Vector3.new(tint.R, tint.G, tint.B), strength)
	for _, descendant in npc:GetDescendants() do
		if keepsColor(descendant) then continue end
		if descendant:IsA("BasePart") then
			if descendant.Name ~= "HumanoidRootPart" then
				descendant.Color = descendant.Color:Lerp(tint, strength)
			end
		elseif descendant:IsA("DataModelMesh") then
			descendant.VertexColor = vertexColor
		elseif descendant:IsA("BodyColors") then
			for _, property in BODY_COLOR_PROPS do
				descendant[property] = descendant[property]:Lerp(tint, strength)
			end
		end
	end
end

-- Distância vertical entre o pivô do modelo e o ponto mais baixo dele
local function pivotHeight(model)
	local boxCFrame, boxSize = model:GetBoundingBox()
	return model:GetPivot().Position.Y - (boxCFrame.Position.Y - boxSize.Y / 2)
end

-- Aplica Tint e Scale do EnemyData. Devolve quanto o modelo precisa subir para não nascer enterrado
-- (o Spawner calcula a altura do spawn para um inimigo de tamanho normal).
local function applyLook(npc, stats)
	if typeof(stats.Tint) == "Color3" then
		local strength = if type(stats.TintStrength) == "number" then math.clamp(stats.TintStrength, 0, 1) else TINT_STRENGTH
		applyTint(npc, stats.Tint, strength)
	end

	if stats.Scale == 1 then
		return 0
	end
	local ok, lift = pcall(function()
		local before = pivotHeight(npc)
		npc:ScaleTo(npc:GetScale() * stats.Scale)
		return pivotHeight(npc) - before
	end)
	if not ok then
		warn(`[EnemyModule] Não foi possível mudar o tamanho de {npc.Name}: {lift}`)
		return 0
	end
	return math.max(0, lift)
end

-- Acessório sem solda no modelo (ex.: colocado à mão no Studio) cairia do corpo: o Humanoid prende de novo
local function attachLooseAccessories(npc, humanoid)
	for _, accessory in npc:GetChildren() do
		if accessory:IsA("Accessory") then
			local handle = accessory:FindFirstChild("Handle")
			if handle and not handle:FindFirstChildWhichIsA("JointInstance") and not handle:FindFirstChildWhichIsA("WeldConstraint") then
				accessory.Parent = nil
				humanoid:AddAccessory(accessory)
			end
		end
	end
end

-- Modelo importado sem as juntas do corpo (comum em modelo pego pronto): ao tirar o Anchored, ele desmontava. Aqui,
-- antes de soltar: as juntas R6 que faltam viram Motor6D na pose em que o modelo está (as animações precisam dos nomes
-- padrão), e qualquer peça que ainda não esteja presa ao HumanoidRootPart é soldada na peça presa mais perto.
-- Avisa uma vez por modelo o que foi consertado (o certo é arrumar o modelo no Studio).
local R6_JOINTS = {
	-- nome, onde fica, Part0, Part1, ponto da junta na Part0 (em metades do tamanho dela), virada da junta
	{ "RootJoint", "HumanoidRootPart", "HumanoidRootPart", "Torso", Vector3.zero, CFrame.Angles(math.rad(90), math.pi, 0) },
	{ "Neck", "Torso", "Torso", "Head", Vector3.new(0, 1, 0), CFrame.Angles(math.rad(90), math.pi, 0) },
	{ "Right Shoulder", "Torso", "Torso", "Right Arm", Vector3.new(1, 0.5, 0), CFrame.Angles(0, math.rad(90), 0) },
	{ "Left Shoulder", "Torso", "Torso", "Left Arm", Vector3.new(-1, 0.5, 0), CFrame.Angles(0, math.rad(-90), 0) },
	{ "Right Hip", "Torso", "Torso", "Right Leg", Vector3.new(1, -1, 0), CFrame.Angles(0, math.rad(90), 0) },
	{ "Left Hip", "Torso", "Torso", "Left Leg", Vector3.new(-1, -1, 0), CFrame.Angles(0, math.rad(-90), 0) },
}

local function jointBetween(a, b)
	for _, part in { a, b } do
		for _, child in part:GetChildren() do
			if child:IsA("JointInstance") and ((child.Part0 == a and child.Part1 == b) or (child.Part0 == b and child.Part1 == a)) then
				return child
			end
			if child:IsA("WeldConstraint") and ((child.Part0 == a and child.Part1 == b) or (child.Part0 == b and child.Part1 == a)) then
				return child
			end
		end
	end
	return nil
end

local repairedTemplates = {}

local function repairRig(npc, humanoid, root, templateName)
	local fixed = {}
	for _, joint in R6_JOINTS do
		local name, holderName, name0, name1, point, turn = table.unpack(joint)
		local part0, part1 = npc:FindFirstChild(name0), npc:FindFirstChild(name1)
		local holder = npc:FindFirstChild(holderName)
		if part0 and part1 and holder and part0:IsA("BasePart") and part1:IsA("BasePart") and not jointBetween(part0, part1) then
			-- Junta com o nome certo mas solta (Part0/Part1 vazios): some e entra a nova
			local broken = holder:FindFirstChild(name)
			if broken and broken:IsA("JointInstance") then
				broken:Destroy()
			end
			local half = part0.Size / 2
			local jointWorld = part0.CFrame * CFrame.new(point * half) * turn
			local motor = Instance.new("Motor6D")
			motor.Name = name
			motor.Part0 = part0
			motor.Part1 = part1
			motor.C0 = part0.CFrame:ToObjectSpace(jointWorld)
			motor.C1 = part1.CFrame:ToObjectSpace(jointWorld)
			motor.Parent = holder
			table.insert(fixed, name)
		end
	end
	if not npc:FindFirstChild("Head") then
		humanoid.RequiresNeck = false -- sem cabeça, o Humanoid morreria (e desmontaria) na hora
	end

	local connected = {}
	for _, part in root:GetConnectedParts(true) do
		connected[part] = true
	end
	connected[root] = true
	local anchors = {}
	for part in connected do
		table.insert(anchors, part)
	end
	local welded = 0
	for _, part in npc:GetDescendants() do
		if part:IsA("BasePart") and not connected[part] then
			-- A peça presa cuja caixa está mais perto do centro desta (a motosserra do braço vai no braço, não no
			-- tronco); dentro de duas caixas, a de centro mais perto. A raiz só se não houver outra.
			local best, bestDistance = root, math.huge
			for _, anchor in anchors do
				if anchor ~= root then
					local offset = anchor.CFrame:PointToObjectSpace(part.Position)
					local half = anchor.Size / 2
					local outside = Vector3.new(
						math.max(math.abs(offset.X) - half.X, 0),
						math.max(math.abs(offset.Y) - half.Y, 0),
						math.max(math.abs(offset.Z) - half.Z, 0)
					).Magnitude
					local distance = outside * 1000 + offset.Magnitude
					if distance < bestDistance then
						best, bestDistance = anchor, distance
					end
				end
			end
			local weld = Instance.new("WeldConstraint")
			weld.Name = "RepairWeld"
			weld.Part0 = best
			weld.Part1 = part
			weld.Parent = part
			part.Massless = true
			connected[part] = true
			welded += 1
		end
	end

	if (#fixed > 0 or welded > 0) and not repairedTemplates[templateName] then
		repairedTemplates[templateName] = true
		warn(`[EnemyModule] O modelo {templateName} veio sem juntas e foi consertado na hora: `
			.. (if #fixed > 0 then `juntas criadas ({table.concat(fixed, ", ")})` else "")
			.. (if #fixed > 0 and welded > 0 then " e " else "")
			.. (if welded > 0 then `{welded} peças soltas soldadas` else "")
			.. ". Para não depender disso, arrume o modelo no Studio (rig R6 com Motor6D).")
	end
end

-- Peça dentro do ReplicatedStorage por caminho (ex.: { "VFX", "EnemyModels", "Knife" })
local function findByPath(root, path)
	local current = root
	for _, name in path do
		current = current and current:FindFirstChild(name)
	end
	return current
end

local warnedWeapons = {}

-- Arma do kit: uma cópia da peça vira o "Handle", presa no braço por um Motor6D (as animações de golpe mexem
-- nesse Handle). Chamada antes do Scale, para a arma crescer junto. Devolve (Motor6D, Handle) ou nil.
local function attachWeapon(npc, weapon)
	local path = weapon.Path or {}
	local source = findByPath(ReplicatedStorage, path)
	local arm = npc:FindFirstChild(weapon.Arm or "Right Arm")
	if not (source and source:IsA("BasePart") and arm and arm:IsA("BasePart")) then
		local key = table.concat(path, ".")
		if not warnedWeapons[key] then
			warnedWeapons[key] = true
			warn(`[EnemyModule] Arma ReplicatedStorage.{key} (uma Part) ou o braço "{weapon.Arm}" não encontrados: {npc.Name} fica sem arma`)
		end
		return nil
	end
	local hold = weapon.HoldC0 or CFrame.identity
	local grip = weapon.Grip or CFrame.identity
	local handle = source:Clone()
	handle.Name = "Handle"
	handle.Anchored = false
	handle.CanCollide = false
	handle.CanTouch = false
	handle.CanQuery = false
	handle.Massless = true
	handle:SetAttribute("KeepColor", true)
	handle.CFrame = arm.CFrame * hold * grip:Inverse()
	handle.Parent = npc
	local motor = Instance.new("Motor6D")
	motor.Name = "WeaponGrip"
	motor.Part0 = arm
	motor.Part1 = handle
	motor.C0 = hold
	motor.C1 = grip
	motor.Parent = arm
	return motor, handle
end

local function createHealthBar(npc, humanoid, root, stats)
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "EnemyBar"
	billboard.Adornee = npc:FindFirstChild("Head") or root
	billboard.Size = UDim2.fromOffset(130, 32)
	billboard.StudsOffset = Vector3.new(0, 1.5 + stats.Scale, 0) -- 2.5 no tamanho normal
	billboard.MaxDistance = 80
	billboard.Parent = npc

	local nameLabel = Instance.new("TextLabel")
	nameLabel.Size = UDim2.new(1, 0, 0, 16)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Font = Enum.Font.GothamBold
	nameLabel.TextSize = 14
	nameLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	nameLabel.TextStrokeTransparency = 0.4
	nameLabel.Text = `{stats.DisplayName}  Lv. {stats.Level}`
	nameLabel.Parent = billboard

	local barBG = Instance.new("Frame")
	barBG.Position = UDim2.fromOffset(0, 20)
	barBG.Size = UDim2.new(1, 0, 0, 8)
	barBG.BackgroundColor3 = Color3.fromRGB(25, 25, 25)
	barBG.BorderSizePixel = 0
	barBG.Parent = billboard
	Instance.new("UICorner", barBG).CornerRadius = UDim.new(0, 4)

	local fill = Instance.new("Frame")
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundColor3 = Color3.fromRGB(200, 40, 40)
	fill.BorderSizePixel = 0
	fill.Parent = barBG
	Instance.new("UICorner", fill).CornerRadius = UDim.new(0, 4)

	local function update()
		local ratio = if humanoid.MaxHealth > 0 then math.clamp(humanoid.Health / humanoid.MaxHealth, 0, 1) else 0
		fill.Size = UDim2.fromScale(ratio, 1)
	end
	humanoid.HealthChanged:Connect(update)
	update()
end

local function giveRewards(humanoid, enemyType, stats)
	local attackerId = humanoid:GetAttribute("LastAttacker")
	local killer = attackerId and Players:GetPlayerByUserId(attackerId)
	if not killer then return end

	PlayerData.AddXP(killer, stats.XP)
	PlayerData.AddGold(killer, stats.Gold)
	QuestModule.OnEnemyKilled(killer, enemyType, stats.Level)
end

-- Clona o template e liga a IA. Devolve (npc, controle) ou nil.
-- options: { EnemyType = string?, Level = number?, Home = Vector3?, HomeCFrame = CFrame?, OnDied = function(npc)?,
--            GiveRewards = function(humanoid, enemyType, stats)?, IgnoreAggroLimit = boolean? }
--   EnemyType: chave do EnemyData (stats, recompensas e missões "Kill"). Padrão: o nome do template.
--   HomeCFrame: onde voltar quando precisar teleportar para casa (padrão: onde nasceu)
--   GiveRewards: troca a recompensa padrão (XP, Gold e missão para quem deu o último golpe)
--   IgnoreAggroLimit: persegue por detecção mesmo com DETECTION_LIMIT inimigos atrás do jogador (chefe e reforços)
--   OnlyTarget: Player: só persegue e ataca esse jogador (cópia do Treinador, TrainerService)
--   OnStrike: function(targetHumanoid, result): cada golpe que chegou no alvo (resultado do CombatRules). Com ele, os
--     golpes não contam no objetivo TakeHits das missões
-- (também aceita só a função OnDied, como a versão antiga)
function EnemyModule.SpawnEnemy(template, cframe, options)
	if type(options) == "function" then
		options = { OnDied = options }
	end
	options = options or {}

	local enemyType = if type(options.EnemyType) == "string" and options.EnemyType ~= ""
		then options.EnemyType
		else template.Name
	local stats = EnemyModule.GetStats(enemyType, options.Level)
	local kit = EnemyKits[template.Name] or {}

	local npc = template:Clone()
	if not npc then
		warn(`[EnemyModule] Template {template:GetFullName()} com Archivable = false não pode ser clonado`)
		return nil
	end
	local humanoid = npc:FindFirstChildOfClass("Humanoid")
	local root = npc:FindFirstChild("HumanoidRootPart")
	if not humanoid or not root then
		local missing = {}
		if not humanoid then table.insert(missing, "Humanoid") end
		if not root then table.insert(missing, "HumanoidRootPart") end
		warn(`[EnemyModule] Template {template:GetFullName()} sem {table.concat(missing, " e ")}`)
		npc:Destroy()
		return nil
	end

	npc.Name = enemyType
	npc:SetAttribute("Enemy", true)
	npc:SetAttribute("EnemyType", enemyType)
	npc:SetAttribute("Level", stats.Level)

	-- A arma entra antes do Scale (cresce junto) e fica fora do Tint (KeepColor)
	local weaponMotor, weaponHandle
	if kit.Weapon then
		weaponMotor, weaponHandle = attachWeapon(npc, kit.Weapon)
	end
	local lift = applyLook(npc, stats)
	local weaponHoldC0 = weaponMotor and weaponMotor.C0 -- já com o Scale
	local offset = Vector3.new(0, lift, 0)
	npc:PivotTo(cframe + offset)

	npc.Parent = getEnemiesFolder()
	attachLooseAccessories(npc, humanoid)
	repairRig(npc, humanoid, root, template.Name)
	humanoid.MaxHealth = stats.Health
	humanoid.Health = stats.Health
	humanoid.WalkSpeed = stats.Speed
	-- Template ancorado por engano: o inimigo precisa andar, e SetNetworkOwner dá erro em Part ancorada
	for _, part in npc:GetDescendants() do
		if part:IsA("BasePart") then
			part.Anchored = false
		end
	end
	if root:CanSetNetworkOwnership() then
		root:SetNetworkOwner(nil) -- o servidor controla o movimento do NPC
	end
	createHealthBar(npc, humanoid, root, stats)

	
	local animator = humanoid:FindFirstChildOfClass("Animator")

if not animator then
	animator = Instance.new("Animator")
	animator.Parent = humanoid
end
	local animFolder = npc:FindFirstChild("Animations")
	local kitAnimations = kit.Animations or {}
	local idleTrack = loadKitTrack(animator, kitAnimations.Idle, true, Enum.AnimationPriority.Idle)
	local runTrack = loadKitTrack(animator, kitAnimations.Run, true, Enum.AnimationPriority.Movement)
		or loadTrack(animator, animFolder, "RunAnim", true)
	if runTrack then
		runTrack.Priority = Enum.AnimationPriority.Movement -- acima do idle (a do template pode estar salva como Core)
	end
	local walkTrack = loadKitTrack(animator, kitAnimations.Walk, true, Enum.AnimationPriority.Movement)
	local dashTrack = loadKitTrack(animator, kitAnimations.Dash, false, Enum.AnimationPriority.Action)
	local attackTracks = {}
	local attackIds = kitAnimations.Attack
	if type(attackIds) == "number" then
		attackIds = { attackIds }
	end
	for _, id in (if type(attackIds) == "table" then attackIds else {}) do
		local track = loadKitTrack(animator, id, false, Enum.AnimationPriority.Action)
		if track then
			table.insert(attackTracks, track)
		end
	end
	-- Reações próprias do modelo (kit): apanhar e morrer. Com a de apanhar, o CombatService não toca a genérica dos
	-- Punhos (atributo OwnHitReaction); com a de morrer, o corpo não desmonta.
	local hitTrack = loadKitTrack(animator, kitAnimations.Hit, false, Enum.AnimationPriority.Action2)
	local deathTrack = loadKitTrack(animator, kitAnimations.Death, false, Enum.AnimationPriority.Action4)
	if hitTrack and npc:GetAttribute("OwnHitReaction") == nil then
		npc:SetAttribute("OwnHitReaction", true)
	end
	if deathTrack then
		humanoid.BreakJointsOnDeath = false
	end
	local lastHitReaction = 0

	-- Só as animações do kit mexem na arma (pose "Handle"): durante elas o Motor6D da arma fica neutro
	local weaponAnimated = weaponMotor ~= nil and #attackTracks > 0
	if #attackTracks == 0 then
		local track = loadTrack(animator, animFolder, "AttackAnim", false)
		if track then
			track.Priority = Enum.AnimationPriority.Action
			table.insert(attackTracks, track)
		end
	end
	if idleTrack then
		idleTrack:Play()
	end

	-- Andando devagar (passeio, de lado na recarga) toca o Walk do kit, se tiver; perseguindo, o Run
	local function setRunning(running, speed)
		local useWalk = running and walkTrack ~= nil and (speed or 1) < WALK_BELOW
		local wanted = if not running then nil elseif useWalk then walkTrack else runTrack
		for _, track in { runTrack, walkTrack } do
			if track and track ~= wanted and track.IsPlaying then
				track:Stop(0.2)
			end
		end
		if not wanted then return end
		if not wanted.IsPlaying then
			wanted:Play(0.2)
		end
		wanted:AdjustSpeed(if useWalk then 1 else (speed or 1))
	end

	-- Faca de volta na mão quando nenhum golpe está tocando
	local function holdWeapon()
		if not weaponAnimated or not weaponMotor.Parent then return end
		for _, track in attackTracks do
			if track.IsPlaying then return end
		end
		weaponMotor.C0 = weaponHoldC0
	end
	for _, track in attackTracks do
		track.Stopped:Connect(holdWeapon)
	end

	-- ================= Estado =================
	local home = if options.Home then options.Home + offset else root.Position
	local homeCFrame = if typeof(options.HomeCFrame) == "CFrame" then options.HomeCFrame + offset else CFrame.new(home)
	local aggroPlayer, aggroUntil = nil, 0
	local returningSince = nil
	local lastDamagedAt = 0 -- os.clock do último dano levado (recuperação fora de combate)
	local finished = false
	local attacking = false -- no meio de um combo
	local nextAttackAt = 0
	local attackIndex = 0
	local attackSerial = 0 -- muda a cada combo novo ou interrompido (o dano atrasado confere)
	local dashConfig = kit.Dash
	local lastDash = -math.huge
	local mover, moverAttachment -- empurrão do dash ou do passo do golpe
	local strafeSide, strafeUntil = 1, 0
	local wanderAt = os.clock() + rng:NextNumber(2, 6)
	local progressPos, progressTime, jumpedForStuck = root.Position, os.clock(), false
	local pathWaypoints, pathIndex, pathExpires = nil, 1, 0
	local computingPath = false
	local currentTargetHrp, currentTargetHum = nil, nil
	local path = PathfindingService:CreatePath({
		AgentRadius = 2 * stats.Scale,
		AgentHeight = 5 * stats.Scale,
		AgentCanJump = true,
		WaypointSpacing = 4,
	})

	-- Controle para outros sistemas (BossService). Os campos podem ser trocados a qualquer momento.
	local controller = {
		Npc = npc,
		Humanoid = humanoid,
		Root = root,
		Stats = stats,
		Kit = kit,
		Home = home,
		HomeCFrame = homeCFrame,
		Paused = false, -- true: a IA não faz nada (chefe no trono ou num ataque especial)
		SpeedMultiplier = 1,
		IgnoreStun = nil, -- function(): true = o Stunned atual não para este inimigo (chefes só param nos longos)
		OnIdle = nil, -- function(distFromHome): sem alvo; devolve true se cuidou do movimento
		OnReturnedHome = nil, -- function(): chegou em casa depois de se afastar demais (chefe: já com a vida cheia)
	}

	local function isBoss()
		return npc:GetAttribute("Boss") == true
	end

	-- Fora de combate há REGEN_DELAY segundos: recupera a vida aos poucos (chamada a cada tick da IA)
	local function regenerate()
		if humanoid.Health < humanoid.MaxHealth and os.clock() - lastDamagedAt >= REGEN_DELAY then
			humanoid.Health = math.min(humanoid.MaxHealth, humanoid.Health + humanoid.MaxHealth * REGEN_RATE * AI_TICK)
		end
	end

	local function isStunned()
		if npc:GetAttribute("Stunned") ~= true then return false end
		return not (controller.IgnoreStun and controller.IgnoreStun())
	end

	local function speed(multiplier)
		return stats.Speed * controller.SpeedMultiplier * (multiplier or 1)
	end

	-- Fica virado para um ponto sem depender de andar para ele (andar de lado na recarga, mirar o golpe)
	local facingAttachment = Instance.new("Attachment")
	facingAttachment.Name = "EnemyFacing"
	facingAttachment.Parent = root
	local facing = Instance.new("AlignOrientation")
	facing.Name = "EnemyFacing"
	facing.Mode = Enum.OrientationAlignmentMode.OneAttachment
	facing.Attachment0 = facingAttachment
	facing.Responsiveness = 30
	facing.MaxTorque = 1e7
	facing.Enabled = false
	facing.Parent = root

	local function face(position)
		local toTarget = position - root.Position
		local flat = Vector3.new(toTarget.X, 0, toTarget.Z)
		if flat.Magnitude < 0.1 then return end
		humanoid.AutoRotate = false
		facing.CFrame = CFrame.lookAt(Vector3.zero, flat.Unit)
		facing.Enabled = true
	end

	local function releaseFacing()
		if facing.Enabled then
			facing.Enabled = false
			humanoid.AutoRotate = true
		end
	end

	-- Vira na hora (antes do golpe e do dash), além de continuar virado pelo AlignOrientation
	local function snapFacing(position)
		local flat = Vector3.new(position.X, root.Position.Y, position.Z)
		if (flat - root.Position).Magnitude > 0.1 then
			root.CFrame = CFrame.lookAt(root.Position, flat)
		end
		face(position)
	end

	local function stopMover()
		if mover then mover:Destroy() mover = nil end
		if moverAttachment then moverAttachment:Destroy() moverAttachment = nil end
	end

	-- Velocidade horizontal por um tempo (o servidor é dono da física do NPC)
	local function startMover(velocity, duration)
		stopMover()
		moverAttachment = Instance.new("Attachment")
		moverAttachment.Name = "EnemyMover"
		moverAttachment.Parent = root
		local linear = Instance.new("LinearVelocity")
		linear.Name = "EnemyMover"
		linear.Attachment0 = moverAttachment
		linear.RelativeTo = Enum.ActuatorRelativeTo.World
		linear.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
		linear.ForceLimitsEnabled = true
		linear.ForceLimitMode = Enum.ForceLimitMode.PerAxis
		-- Força proporcional à massa: com força fixa o Humanoid de um inimigo grande segura o empurrão
		-- (o chefe, com massa 112, andava 3 studs em vez de 18)
		local force = math.max(1e5, root.AssemblyMass * 1e5)
		linear.MaxAxesForce = Vector3.new(force, 0, force)
		linear.VectorVelocity = velocity
		linear.Parent = root
		mover = linear
		task.delay(duration, function()
			if mover == linear then
				stopMover()
			end
		end)
	end

	local function cancelAttack()
		attackSerial += 1
		if attacking then
			attacking = false
			nextAttackAt = math.max(nextAttackAt, os.clock() + 0.4)
		end
		for _, track in attackTracks do
			if track.IsPlaying then
				track:Stop(0.05)
			end
		end
	end

	-- ================= Golpe e combo =================

	-- O jogador alvo começou um M1 antes deste golpe, está virado para o inimigo e no alcance: o M1 dele vai chegar
	local function playerStruckFirst(targetHum, swingStart)
		if npc:GetAttribute("Boss") == true then return false end
		local character = targetHum.Parent
		local player = character and Players:GetPlayerFromCharacter(character)
		local swingAt = player and CombatState.LastSwingAt(player)
		if not swingAt or swingAt > swingStart then return false end
		if workspace:GetServerTimeNow() - swingAt > PRIORITY_WINDOW then return false end
		local _, style = CombatStyles.FromCharacter(character)
		local playerRoot = character:FindFirstChild("HumanoidRootPart")
		if not style or not playerRoot then return false end
		local offset = root.Position - playerRoot.Position
		if offset.Magnitude > style.M1.Range + CombatStyles.HitTolerance then return false end
		local flat = Vector3.new(offset.X, 0, offset.Z)
		local look = playerRoot.CFrame.LookVector
		return flat.Magnitude < 1 or Vector3.new(look.X, 0, look.Z).Unit:Dot(flat.Unit) >= 0.2
	end

	-- Um golpe: vira para o alvo, dá um passo se ele estiver um pouco longe, toca a animação e o dano sai no
	-- momento do corte (AttackHitTime / marcador), se o alvo ainda estiver no alcance e na frente.
	-- Devolve quanto esperar até o próximo golpe do combo (ou até o fim da animação, no último).
	local function swing(targetHrp, targetHum, serial, finisher)
		snapFacing(targetHrp.Position)
		local toTarget = targetHrp.Position - root.Position
		local flat = Vector3.new(toTarget.X, 0, toTarget.Z)
		local lunge = kit.Lunge
		if type(lunge) == "number" and lunge > 0 and flat.Magnitude > 2.5 then
			startMover(flat.Unit * lunge, math.clamp((flat.Magnitude - 2) / lunge, 0.05, 0.15))
		end

		local track, hitTime = nil, 0
		local speed = kit.AttackSpeed or BALANCE.AttackSpeed
		local swingStart = workspace:GetServerTimeNow()
		if #attackTracks > 0 then
			attackIndex = attackIndex % #attackTracks + 1
			track = attackTracks[attackIndex]
			local times = kit.AttackHitTime
			hitTime = if type(times) == "table" then (times[attackIndex] or times[1] or 0)
				elseif type(times) == "number" then times
				else 0
			hitTime /= speed
			if weaponAnimated then
				weaponMotor.C0 = CFrame.identity
			end
			track:Play(0.05, 1, speed)
		end

		local done = false
		local connections = {}
		local function strike()
			if done then return end
			done = true
			for _, connection in connections do
				connection:Disconnect()
			end
			if serial ~= attackSerial or finished or humanoid.Health <= 0 or isStunned() then return end
			if not targetHrp.Parent or targetHum.Health <= 0 then return end
			if playerStruckFirst(targetHum, swingStart) then return end
			local offset = targetHrp.Position - root.Position
			if offset.Magnitude > stats.AttackRange + ATTACK_RANGE_MARGIN then return end
			-- Na frente (dá para esquivar passando por trás com o dash)
			local flatOffset = Vector3.new(offset.X, 0, offset.Z)
			local look = root.CFrame.LookVector
			if flatOffset.Magnitude > 1 and Vector3.new(look.X, 0, look.Z).Unit:Dot(flatOffset.Unit) < -0.1 then return end
			local damage = stats.Damage * (if finisher then kit.FinisherDamage or 1 else 1)
			-- Defesa, esquiva, bloqueio/parry e ForceField ficam com o CombatRules (o npc leva o stun do parry)
			local _, result = CombatRules.DamageFromNPC(targetHum, damage, npc)
			if result == "Hit" then
				onTargetHit(npc, root, targetHum, kit, finisher)
			end
			if result ~= nil then
				if options.OnStrike then
					task.spawn(options.OnStrike, targetHum, result)
				else
					local victimPlayer = Players:GetPlayerFromCharacter(targetHum.Parent)
					if victimPlayer then
						task.spawn(QuestModule.OnHitTaken, victimPlayer)
					end
				end
			end
		end
		if track and kit.HitMarker then
			connections = CombatStyles.OnMarker(track, kit.HitMarker, strike)
		end
		if hitTime > 0 then
			task.delay(hitTime, strike)
		else
			strike()
		end

		if finisher then
			return (if track and track.Length > 0 then track.Length else 0.6) / speed
		end
		return (kit.ComboInterval or 0.45) / speed
	end

	local function startCombo(targetHrp, targetHum)
		attacking = true
		attackSerial += 1
		local serial = attackSerial
		local hits = math.max(1, math.floor(stats.Combo or kit.Combo or 1))
		task.spawn(function()
			for hit = 1, hits do
				if serial ~= attackSerial or finished then return end
				if not targetHrp.Parent or targetHum.Health <= 0 then break end
				-- O alvo fugiu no meio do combo: para aqui (a recarga começa já)
				if hit > 1 and (targetHrp.Position - root.Position).Magnitude > stats.AttackRange + ATTACK_RANGE_MARGIN then break end
				task.wait(swing(targetHrp, targetHum, serial, hit == hits and hits > 1))
			end
			if serial == attackSerial then
				attacking = false
				nextAttackAt = os.clock() + stats.AttackCooldown
			end
		end)
	end

	-- ================= Movimento =================

	-- Dash até o alvo (sem dano)
	local function tryDash(targetHrp, dist)
		if not dashConfig or mover then return end
		local clock = os.clock()
		if clock - lastDash < (dashConfig.Cooldown or 5) then return end
		if dist < (dashConfig.MinRange or 8) or dist > (dashConfig.MaxRange or 20) then return end
		if humanoid.FloorMaterial == Enum.Material.Air then return end
		local toTarget = targetHrp.Position - root.Position
		local flat = Vector3.new(toTarget.X, 0, toTarget.Z)
		if flat.Magnitude < 1 then return end
		local dashSpeed = dashConfig.Speed or 70
		-- Para um pouco antes do alvo, já no alcance do golpe
		local duration = math.clamp((flat.Magnitude - stats.AttackRange * 0.7) / dashSpeed, 0.05, dashConfig.Duration or 0.3)
		lastDash = clock
		snapFacing(targetHrp.Position)
		if dashTrack then
			dashTrack:Play(0.05)
		end
		startMover(flat.Unit * dashSpeed, duration)
	end

	-- Ponto de perseguição: mais longe, mira para onde o alvo está indo
	local function chasePoint(targetHrp, dist)
		if dist <= 8 then return targetHrp.Position end
		local velocity = targetHrp.AssemblyLinearVelocity
		local lead = math.clamp(dist / math.max(speed(), 1), 0, 0.6)
		return targetHrp.Position + Vector3.new(velocity.X, 0, velocity.Z) * lead
	end

	-- Quanto tempo está perseguindo sem sair do lugar (0 quando anda ou não está perseguindo)
	local function stuckTime(chasing)
		local clock = os.clock()
		if not chasing or (root.Position - progressPos).Magnitude > 1.5 then
			progressPos, progressTime, jumpedForStuck = root.Position, clock, false
			return 0
		end
		return clock - progressTime
	end

	local function requestPath(goal)
		if computingPath then return end
		computingPath = true
		task.spawn(function()
			local ok = pcall(function()
				path:ComputeAsync(root.Position, goal)
			end)
			computingPath = false
			if finished then return end
			if ok and path.Status == Enum.PathStatus.Success then
				pathWaypoints = path:GetWaypoints()
				pathIndex = 2
				pathExpires = os.clock() + PATH_DURATION
			else
				pathWaypoints = nil
			end
		end)
	end

	-- Segue o caminho calculado. Devolve false quando não há caminho (acabou, expirou ou nunca teve).
	local function followPath()
		while pathWaypoints do
			if os.clock() > pathExpires or pathIndex > #pathWaypoints then
				pathWaypoints = nil
				break
			end
			local waypoint = pathWaypoints[pathIndex]
			local toWaypoint = waypoint.Position - root.Position
			if Vector3.new(toWaypoint.X, 0, toWaypoint.Z).Magnitude < 2.5 then
				pathIndex += 1
			else
				if waypoint.Action == Enum.PathWaypointAction.Jump then
					humanoid.Jump = true
				end
				humanoid:MoveTo(waypoint.Position)
				return true
			end
		end
		return false
	end

	-- Na recarga, perto do alvo: anda de lado em volta dele, trocando de lado de vez em quando
	local function strafe(targetHrp)
		local clock = os.clock()
		if clock >= strafeUntil then
			strafeSide = if rng:NextNumber() < 0.5 then -1 else 1
			strafeUntil = clock + rng:NextNumber(0.6, 1.3)
		end
		local away = root.Position - targetHrp.Position
		local flat = Vector3.new(away.X, 0, away.Z)
		flat = if flat.Magnitude > 0.1 then flat.Unit else Vector3.new(1, 0, 0)
		local radius = math.max(stats.AttackRange * 0.9, 3)
		local around = CFrame.Angles(0, math.rad(35) * strafeSide, 0):VectorToWorldSpace(flat)
		humanoid.WalkSpeed = speed(STRAFE_SPEED)
		humanoid:MoveTo(targetHrp.Position + around * radius)
		setRunning(true, 0.6)
	end

	-- Alvo atual (o da última decisão da IA), se ainda estiver vivo
	local function getTarget()
		if currentTargetHrp and currentTargetHrp.Parent and currentTargetHum and currentTargetHum.Health > 0 then
			return currentTargetHrp, currentTargetHum
		end
		return nil, nil
	end

	controller.Face = face
	controller.SnapFacing = snapFacing
	controller.ReleaseFacing = releaseFacing
	controller.StartMover = startMover
	controller.StopMover = stopMover
	controller.CancelAttack = cancelAttack
	controller.SetRunning = setRunning
	controller.GetTarget = getTarget
	controller.IsBusy = function()
		return attacking or mover ~= nil
	end

	local function finish()
		if finished then return end
		finished = true
		alertHandlers[npc] = nil
		setChasing(npc, nil)
		setRunning(false)
		stopMover()
		cancelAttack()
		releaseFacing()
		facing:Destroy()
		facingAttachment:Destroy()
		if options.OnDied then
			task.spawn(options.OnDied, npc)
		end
	end

	-- Atordoado: corta o combo (sem dano), o dash e o giro na hora, sem esperar o próximo tick da IA
	npc:GetAttributeChangedSignal("Stunned"):Connect(function()
		if isStunned() then
			cancelAttack()
			stopMover()
			releaseFacing()
		end
	end)

	-- Alguém do grupo apanhou: vem junto (se não estiver voltando para casa)
	alertHandlers[npc] = function(player)
		if finished or returningSince then return end
		if not aggroPlayer or os.clock() >= aggroUntil then
			aggroPlayer = player
			aggroUntil = os.clock() + AGGRO_ON_HIT_TIME
		end
	end

	-- Quem bate no inimigo vira o alvo dele por um tempo, e os inimigos em volta vêm junto
	local lastHealth = humanoid.Health
	humanoid.HealthChanged:Connect(function(health)
		if health < lastHealth then
			lastDamagedAt = os.clock()
			if hitTrack and health > 0 and os.clock() - lastHitReaction >= HIT_REACTION_GAP then
				lastHitReaction = os.clock()
				hitTrack:Play(0.05)
			end
			local attackerId = humanoid:GetAttribute("LastAttacker")
			local attacker = attackerId and Players:GetPlayerByUserId(attackerId)
			if attacker and not returningSince then
				aggroPlayer = attacker
				aggroUntil = os.clock() + AGGRO_ON_HIT_TIME
				alertNearby(npc, attacker, root.Position)
			end
		end
		lastHealth = health
	end)

	-- ================= IA =================
	task.spawn(function()
		while not finished and humanoid.Health > 0 and npc.Parent do
			task.wait(AI_TICK)
			if finished or humanoid.Health <= 0 then break end

			-- Caiu do mapa: a parte principal foi destruída
			if not root.Parent then
				npc:Destroy()
				finish()
				break
			end

			-- Outro sistema no comando (chefe sentado no trono ou num ataque especial)
			if controller.Paused then
				setChasing(npc, nil)
				continue
			end

			if isStunned() then
				humanoid:MoveTo(root.Position)
				setRunning(false)
				continue
			end

			-- No meio do dash ou do combo: deixa terminar (o combo continua virado para o alvo)
			if mover and not attacking then
				continue
			end

			local distFromHome = flatDistance(root.Position, home)

			-- Voltando para casa (passou do limite): ignora jogadores até chegar. Só o chefe chega com a vida cheia (a
			-- luta dele recomeça do zero); os outros recuperam devagar, fora de combate.
			if returningSince then
				releaseFacing()
				humanoid.WalkSpeed = speed()
				if not isBoss() then
					regenerate()
				end
				local arrived = distFromHome < 5
				if not arrived and os.clock() - returningSince > RETURN_TIMEOUT then
					npc:PivotTo(homeCFrame)
					arrived = true
				end
				if arrived then
					returningSince = nil
					if isBoss() then
						humanoid.Health = humanoid.MaxHealth
					end
					humanoid:MoveTo(root.Position)
					setRunning(false)
					if controller.OnReturnedHome then
						controller.OnReturnedHome()
					end
				else
					humanoid:MoveTo(home)
					setRunning(true)
				end
				continue
			end

			-- Alvo: quem bateu nele (por um tempo, enquanto não sumir de vista) ou o jogador mais próximo no alcance.
			-- Por detecção, só se o jogador ainda tiver menos de DETECTION_LIMIT inimigos atrás (ele mesmo não conta).
			local targetHrp, targetHum, dist, targetPlayer
			if options.OnlyTarget then
				-- Cópia do Treinador: só o jogador do treino, a qualquer distância
				aggroPlayer, aggroUntil = options.OnlyTarget, math.huge
			end
			if aggroPlayer and os.clock() < aggroUntil then
				targetHrp, targetHum = aliveCharacter(aggroPlayer)
				if targetHrp then
					dist = (targetHrp.Position - root.Position).Magnitude
					targetPlayer = aggroPlayer
					if dist > LOSE_RANGE then
						targetHrp, targetHum, dist, targetPlayer = nil, nil, nil, nil
					end
				end
			end
			if not targetHrp and not options.OnlyTarget then
				aggroPlayer = nil
				local limitFor = if options.IgnoreAggroLimit then nil else npc
				targetHrp, targetHum, dist, targetPlayer = findClosestPlayer(root.Position, stats.AggroRange, limitFor)
			end

			-- Longe demais de casa: volta. Perseguindo alguém o limite é bem maior (não larga a luta no meio); o chefe
			-- fica sempre perto da arena (LeashRange).
			local leash = if targetHrp and not isBoss() then stats.LeashRange * CHASE_LEASH_MULTIPLIER else stats.LeashRange
			if distFromHome > leash and not attacking then
				returningSince = os.clock()
				aggroPlayer = nil
				currentTargetHrp, currentTargetHum = nil, nil
				setChasing(npc, nil)
				pathWaypoints = nil
				humanoid:MoveTo(home)
				setRunning(true)
				continue
			end
			currentTargetHrp, currentTargetHum = targetHrp, targetHum
			setChasing(npc, targetPlayer)

			if attacking then
				-- Combo em andamento: parado, virado para o alvo
				humanoid:MoveTo(root.Position)
				setRunning(false)
				if targetHrp then
					face(targetHrp.Position)
				end
				continue
			end

			if not targetHrp then
				-- Sem alvo: quem comanda decide (chefe volta para o trono) ou volta para perto de casa e passeia
				if not isBoss() then
					regenerate()
				end
				releaseFacing()
				stuckTime(false)
				pathWaypoints = nil
				if controller.OnIdle and controller.OnIdle(distFromHome) then
					continue
				end
				if distFromHome > 12 then
					humanoid.WalkSpeed = speed()
					humanoid:MoveTo(home)
					setRunning(true)
				elseif os.clock() >= wanderAt then
					wanderAt = os.clock() + rng:NextNumber(4, 8)
					local angle = rng:NextNumber(0, math.pi * 2)
					local radius = rng:NextNumber(3, 9)
					humanoid.WalkSpeed = speed(WANDER_SPEED)
					humanoid:MoveTo(home + Vector3.new(math.cos(angle) * radius, 0, math.sin(angle) * radius))
					setRunning(true, 0.5)
				else
					local velocity = root.AssemblyLinearVelocity
					if Vector3.new(velocity.X, 0, velocity.Z).Magnitude < 1 then
						setRunning(false)
					end
				end
				continue
			end

			if dist > stats.AttackRange then
				-- Persegue: caminho calculado (se travou antes), dash para encurtar ou corrida direta
				releaseFacing()
				humanoid.WalkSpeed = speed()
				if dist < stats.AttackRange + 3 then
					pathWaypoints = nil
				end
				if not followPath() then
					tryDash(targetHrp, dist)
					if not mover then
						humanoid:MoveTo(chasePoint(targetHrp, dist))
						local stuck = stuckTime(true)
						if stuck > STUCK_TIME and not jumpedForStuck then
							humanoid.Jump = true
							jumpedForStuck = true
						end
						if stuck > STUCK_TIME * 2 then
							requestPath(targetHrp.Position)
							progressTime = os.clock()
						end
					end
				end
				setRunning(true)
			else
				-- Perto: combo quando a recarga acabar; enquanto isso anda de lado virado para o alvo
				stuckTime(false)
				pathWaypoints = nil
				face(targetHrp.Position)
				if os.clock() >= nextAttackAt then
					humanoid:MoveTo(root.Position)
					setRunning(false)
					startCombo(targetHrp, targetHum)
				elseif kit.Strafe then
					strafe(targetHrp)
				else
					humanoid:MoveTo(root.Position)
					setRunning(false)
				end
			end
		end
	end)

	humanoid.Died:Connect(function()
		if options.GiveRewards then
			options.GiveRewards(humanoid, enemyType, stats)
		else
			giveRewards(humanoid, enemyType, stats)
		end

		-- Devorado pelo Kon (PathSkills): sem animação de morte nem drop, o corpo some logo
		if npc:GetAttribute("Devoured") == true then
			Debris:AddItem(npc, DEVOURED_TIME)
			finish()
			return
		end

		-- A faca cai no chão junto com o corpo (sem colisão ela atravessaria o chão)
		if weaponHandle and weaponHandle.Parent then
			weaponHandle.CanCollide = true
		end

		-- Morte própria (kit Death): para o resto, prende a raiz (sem cair de física no meio) e segura a última pose
		if deathTrack then
			for _, track in animator:GetPlayingAnimationTracks() do
				if track ~= deathTrack then
					track:Stop(0.1)
				end
			end
			root.Anchored = true
			deathTrack:Play(0.1)
			local length = if deathTrack.Length > 0 then deathTrack.Length else (kit.DeathTime or 1.3)
			task.delay(math.max(0, length - 0.05), function()
				if deathTrack.IsPlaying then
					deathTrack:AdjustSpeed(0)
				end
			end)
		end

		-- Drop visual simples
		local drop = Instance.new("Part")
		drop.Size = Vector3.new(1, 1, 1)
		drop.Position = root.Position + Vector3.new(0, 2, 0)
		drop.Anchored = true
		drop.CanCollide = false
		drop.CanQuery = false
		drop.BrickColor = BrickColor.new("Bright yellow")
		drop.Parent = workspace
		Debris:AddItem(drop, 3)

		Debris:AddItem(npc, CORPSE_TIME)
		finish()
	end)
	-- Apagado por fora (sem morrer): só sai da lista de alertas, como antes (sem chamar o OnDied)
	npc.Destroying:Connect(function()
		alertHandlers[npc] = nil
		setChasing(npc, nil)
	end)

	return npc, controller
end

return EnemyModule
