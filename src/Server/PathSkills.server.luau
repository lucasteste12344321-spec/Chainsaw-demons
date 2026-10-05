-- Poderes dos caminhos (Fase 4): contratos do Caçador e habilidades do Infernal, nos slots Z e X.
-- O cliente só manda o slot por Remotes.UsePower; o servidor valida tudo (vida, stun, cooldown, custo)
-- e faz a hitbox. As definições (dano, alcance, custo...) ficam em ReplicatedStorage.PathData.
-- Escreve no player PowerZReadyAt/PowerXReadyAt (server time em que o slot fica pronto) e, na
-- Visão do Futuro, DodgeUntil no personagem (quem aplica a esquiva é o CombatRules).
-- Especificação em docs/fase4-caminhos.md.
local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
local StarterPlayer = game:GetService("StarterPlayer")
local TweenService = game:GetService("TweenService")

local Remotes = require(ReplicatedStorage:WaitForChild("Remotes"))
local PathData = require(ReplicatedStorage:WaitForChild("PathData"))
local PlayerData = require(ServerScriptService:WaitForChild("PlayerData"))
local PathModule = require(ServerScriptService:WaitForChild("PathModule"))
local CombatRules = require(ServerScriptService:WaitForChild("CombatRules"))
local CombatState = require(ServerScriptService:WaitForChild("CombatState"))
local QuestModule = require(ServerScriptService:WaitForChild("QuestModule"))
local FoxConfig = require(ReplicatedStorage:WaitForChild("FoxDevilConfig"))
local ContractData = require(ReplicatedStorage:WaitForChild("ContractData"))
local Destruction = require(ServerScriptService:WaitForChild("Destruction"))

-- Infernal do Sangue (Codex, src/Server/BloodFiendSkills.luau): dano e efeito próprios para os poderes que ele assume
-- (Handles); validação, custo e recarga continuam aqui. Sem o módulo (ou com erro nele), ou enquanto o cliente que
-- desenha os efeitos dele (StarterPlayerScripts.BloodFiendVFX) não existir, valem os tipos antigos com os efeitos neon.
local BloodFiendSkills
do
	local module = ServerScriptService:FindFirstChild("BloodFiendSkills")
	if module then
		local ok, result = pcall(require, module)
		if ok and type(result) == "table" and type(result.Handles) == "function" and type(result.Cast) == "function" then
			BloodFiendSkills = result
		else
			warn("[PathSkills] BloodFiendSkills não carregou: " .. tostring(result))
		end
	end
end

local SLOTS = { Z = true, X = true, HZ = true, HX = true } -- HZ/HX (teclas H e J): só no modo híbrido de admin
local GLOBAL_LOCK = 0.35 -- intervalo mínimo entre dois poderes quaisquer do mesmo jogador
local NOTICE_INTERVAL = 1.5 -- intervalo mínimo entre dois avisos de "não deu para usar"
local HIT_TOLERANCE = 1.5 -- o alcance conta até a borda do corpo do alvo, não só até o centro
local MARK_MIN_DOT = math.cos(math.rad(35)) -- Mark: o alvo precisa estar a até 35° da frente
local DASH_WALL_MARGIN = 2 -- Dash: para esta distância antes de uma parede
local DASH_MAX_LIFT = 4 -- Dash: quanto o destino pode subir para não entrar numa rampa
local LUNGE_BREAK_STEP = 5 -- Bote: distância entre duas quebras do mapa no caminho da cabeça
local POWER_ROOT_MAX = 1.5 -- no máximo esse tempo parado usando um poder
local rootTokens = {} -- [Player] = o uso de poder que está prendendo o jogador agora

local DEFAULT_COLOR = Color3.fromRGB(255, 255, 255)
local SKILL_COLORS = {
	MordidaRaposa = Color3.fromRGB(255, 140, 30),
	MordidaRaposa2 = Color3.fromRGB(255, 140, 30),
	BoteRaposa = Color3.fromRGB(255, 140, 30),
	BoteRaposa2 = Color3.fromRGB(255, 140, 30),
	MaosFantasma = Color3.fromRGB(205, 225, 255),
	VisaoFutura = Color3.fromRGB(70, 150, 255),
	PregoMaldito = Color3.fromRGB(200, 25, 45),
	LancaSangue = Color3.fromRGB(190, 10, 20),
	MarteloSangue = Color3.fromRGB(150, 0, 15),
	MergulhoTubarao = Color3.fromRGB(60, 150, 230),
	MordidaTubarao = Color3.fromRGB(110, 170, 215),
}
local MARK_COLOR = Color3.fromRGB(220, 20, 40) -- Highlight vermelho da marca

-- cooldowns[player][slot] = { SkillId = Id da habilidade que gerou a recarga, ReadyAt = server time em que fica pronta }
local cooldowns = {}
local busyUntil = {} -- busyUntil[player] = server time em que pode usar outro poder
local lastNotice = {} -- lastNotice[player] = os.clock() do último aviso

-- Pasta única para os efeitos visuais (cada efeito também tem Debris)
local effectsFolder = Instance.new("Folder")
effectsFolder.Name = "PowerEffects"
effectsFolder.Parent = workspace

----------------------------------------------------------------------------------------------------
-- Utilidades
----------------------------------------------------------------------------------------------------

local function notice(player, title, text)
	local now = os.clock()
	if now - (lastNotice[player] or 0) < NOTICE_INTERVAL then return end
	lastNotice[player] = now
	PlayerData.Notify(player, title, text, 2)
end

local function tween(instance, time, goals, style, direction)
	local info = TweenInfo.new(time, style or Enum.EasingStyle.Quad, direction or Enum.EasingDirection.Out)
	local playing = TweenService:Create(instance, info, goals)
	playing:Play()
	return playing
end

-- Part de efeito: ancorada, Neon, sem colisão nem consulta. Some sozinha depois de lifetime segundos.
local function newEffect(className, props, lifetime)
	local part = Instance.new(className)
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Material = Enum.Material.Neon
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	-- O formato vem antes do tamanho: trocar o Shape depois ajustaria o Size
	if props.Shape then
		part.Shape = props.Shape
	end
	for key, value in props do
		if key ~= "Shape" then
			part[key] = value
		end
	end
	part.Parent = effectsFolder
	Debris:AddItem(part, lifetime)
	return part
end

local function fadeOut(part, delayTime, time)
	task.delay(delayTime, function()
		if part.Parent then
			tween(part, time, { Transparency = 1 })
		end
	end)
end

-- Bola que cresce e some
local function burst(position, color, size, time)
	local ball = newEffect("Part", {
		Shape = Enum.PartType.Ball,
		Size = Vector3.one * math.max(0.5, size * 0.3),
		CFrame = CFrame.new(position),
		Color = color,
		Transparency = 0.1,
	}, time + 0.2)
	tween(ball, time, { Size = Vector3.one * size, Transparency = 1 })
	return ball
end

-- Disco deitado no chão que se abre e some
local function shockwave(position, color, diameter, time)
	local disc = newEffect("Part", {
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.3, 1, 1),
		-- O eixo do cilindro é o X: girando 90° em Z ele fica de pé e o disco fica deitado
		CFrame = CFrame.new(position) * CFrame.Angles(0, 0, math.rad(90)),
		Color = color,
		Transparency = 0.25,
	}, time + 0.2)
	tween(disc, time, { Size = Vector3.new(0.3, diameter, diameter), Transparency = 1 })
	return disc
end

-- Frente do personagem no plano horizontal
local function flatLook(root)
	local look = root.CFrame.LookVector
	local flat = Vector3.new(look.X, 0, look.Z)
	return if flat.Magnitude > 0.001 then flat.Unit else Vector3.new(0, 0, -1)
end

-- Distância de um ponto até o segmento a-b, e o ponto do segmento mais próximo dele
local function closestOnSegment(point, a, b)
	local ab = b - a
	local lengthSq = ab:Dot(ab)
	local t = if lengthSq > 1e-6 then math.clamp((point - a):Dot(ab) / lengthSq, 0, 1) else 0
	local closest = a + ab * t
	return (point - closest).Magnitude, closest
end

-- Raycast que só enxerga o cenário: ignora personagens, inimigos e efeitos, e respeita CanCollide
local function obstacleParams(character)
	local exclude = { character, effectsFolder }
	local enemies = workspace:FindFirstChild("Enemies")
	if enemies then
		table.insert(exclude, enemies)
	end
	for _, other in Players:GetPlayers() do
		if other.Character then
			table.insert(exclude, other.Character)
		end
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = exclude
	params.RespectCanCollide = true
	return params
end

-- true se não há parede entre os dois pontos
local function clearPath(from, to, params)
	local offset = to - from
	if offset.Magnitude < 0.05 then return true end
	return workspace:Raycast(from, offset, params) == nil
end

-- Chão logo abaixo de uma posição (RaycastResult ou nil)
local function groundBelow(position, params, depth)
	return workspace:Raycast(position + Vector3.new(0, 1, 0), Vector3.new(0, -(depth or 30), 0), params)
end

----------------------------------------------------------------------------------------------------
-- Alvos e dano
----------------------------------------------------------------------------------------------------

-- Model com Humanoid dono de uma Part (sobe pelos Models até achar um Humanoid)
local function modelOf(part)
	local model = part:FindFirstAncestorOfClass("Model")
	while model do
		if model:FindFirstChildOfClass("Humanoid") then
			return model
		end
		model = model:FindFirstAncestorOfClass("Model")
	end
	return nil
end

-- Alvos válidos (CombatRules.CanDamage) com alguma parte dentro da esfera
local function collectTargets(ctx, center, radius)
	local targets = {}
	local seen = {}
	for _, part in workspace:GetPartBoundsInRadius(center, radius, ctx.Overlap) do
		local model = modelOf(part)
		if model and not seen[model] then
			seen[model] = true
			local humanoid = model:FindFirstChildOfClass("Humanoid")
			local root = model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart
			if humanoid and humanoid.Health > 0 and root and root:IsA("BasePart")
				and CombatRules.CanDamage(ctx.Player, model) then
				table.insert(targets, { Model = model, Humanoid = humanoid, Root = root })
			end
		end
	end
	return targets
end

-- Maestria do contrato (ContractData.Mastery): acertos e abates dos poderes de um Caçador. O boneco de treino
-- do tutorial não conta.
local function contractXP(ctx, target, killed)
	if not ctx.ContractId or target.Model:GetAttribute("TrainingDummy") ~= nil then return end
	local xp = ContractData.Mastery.PowerHitXP + (if killed then ContractData.Mastery.PowerKillXP else 0)
	PlayerData.AddContractMastery(ctx.Player, ctx.ContractId, xp)
end

-- Dano + stun num alvo. Cada alvo só leva dano uma vez por uso (ctx.HitSet). Devolve o dano causado.
local function hitTarget(ctx, target)
	if ctx.HitSet[target.Model] then return 0 end
	ctx.HitSet[target.Model] = true
	if target.Humanoid.Health <= 0 then return 0 end

	local dealt, result = CombatRules.Damage(ctx.Player, target.Humanoid, ctx.Skill.Damage or 0)
	dealt = dealt or 0
	if dealt > 0 then
		table.insert(ctx.Hits, target)
		contractXP(ctx, target, target.Humanoid.Health <= 0)
		local stun = ctx.Skill.Stun
		if type(stun) == "number" and stun > 0 and target.Humanoid.Health > 0 then
			-- Só atordoa se o golpe entrou ("Hit", inclusive pelas costas de quem bloqueia)
			CombatRules.Stun(target.Humanoid, stun, result)
		end
		burst(target.Root.Position, ctx.Color, 3.5, 0.25)
	end
	return dealt
end

-- Finalização do Kon (PathData Finisher): inimigo comum, não chefe, que ficou com até Threshold da vida depois da mordida
local function canDevour(skill, target)
	local finisher = skill.Finisher
	if type(finisher) ~= "table" or not CombatRules.IsEnemyNPC(target.Model) then return false end
	if target.Model:GetAttribute("Boss") == true or target.Model:GetAttribute("TrainingDummy") ~= nil then return false end
	local humanoid = target.Humanoid
	return humanoid.MaxHealth > 0 and humanoid.Health <= humanoid.MaxHealth * (finisher.Threshold or 0.3)
end

-- Mata a presa sem desmontar o corpo: ele fica parado, sem colisão e sem barra até o EnemyModule apagar (atributo
-- Devoured). Quem mostra a presa sendo engolida são os clientes (cópia local do corpo, FoxDevilVFX).
-- O LastAttacker já foi marcado pelo dano da mordida: XP, Gold e missão saem normalmente na morte.
local function devour(target)
	local model, humanoid = target.Model, target.Humanoid
	model:SetAttribute("Devoured", true)
	humanoid.BreakJointsOnDeath = false
	target.Root.Anchored = true
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			part.CanCollide = false
			part.CanQuery = false
		end
	end
	local bar = model:FindFirstChild("EnemyBar")
	if bar then
		bar:Destroy()
	end
	if humanoid.Health > 0 then
		humanoid.Health = 0
	end
end

-- Arremessa o alvo: o jogador aplica no próprio personagem (CombatImpulse, sem tremer); o NPC, aqui (LinearVelocity)
local function launch(target, velocity, duration)
	local victimPlayer = Players:GetPlayerFromCharacter(target.Model)
	if victimPlayer then
		Remotes.CombatImpulse:FireClient(victimPlayer, velocity, duration)
		return
	end
	for _, child in target.Root:GetChildren() do
		if child.Name == "PowerKnockback" then
			child:Destroy()
		end
	end
	local attachment = Instance.new("Attachment")
	attachment.Name = "PowerKnockback"
	attachment.Parent = target.Root
	local mover = Instance.new("LinearVelocity")
	mover.Name = "PowerKnockback"
	mover.Attachment0 = attachment
	mover.RelativeTo = Enum.ActuatorRelativeTo.World
	mover.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
	mover.MaxForce = 1e6
	mover.VectorVelocity = velocity
	mover.Parent = target.Root
	Debris:AddItem(mover, duration)
	Debris:AddItem(attachment, duration)
end

----------------------------------------------------------------------------------------------------
-- Efeitos por tipo
----------------------------------------------------------------------------------------------------

-- Duas mandíbulas (WedgeParts) que se fecham à frente: mordidas em cone
local function biteEffect(ctx, range)
	local origin = ctx.Root.Position
	local hinge = CFrame.lookAt(origin, origin + ctx.Look) * CFrame.new(0, 0, -1)
	local width = math.clamp(range * 0.7, 4, 10)
	local height = math.clamp(range * 0.2, 1.5, 3)
	for _, side in { 1, -1 } do
		-- A WedgePart afina para -Z (a ponta fica na frente); a de cima fica de ponta-cabeça
		local roll = if side == 1 then CFrame.Angles(0, 0, math.pi) else CFrame.identity
		local offset = CFrame.new(0, side * height / 2, -range / 2) * roll
		local jaw = newEffect("WedgePart", {
			Size = Vector3.new(width, height, range),
			-- Começa aberta (girada na dobradiça) e fecha
			CFrame = hinge * CFrame.Angles(math.rad(40) * side, 0, 0) * offset,
			Color = ctx.Color,
			Transparency = 0.2,
		}, 0.9)
		tween(jaw, 0.18, { CFrame = hinge * offset }, Enum.EasingStyle.Back, Enum.EasingDirection.In)
		fadeOut(jaw, 0.25, 0.45)
	end
	task.delay(0.18, function()
		burst(origin + ctx.Look * (range * 0.6), ctx.Color, range * 0.6, 0.3)
	end)
end

-- Explosão em área: anel no chão, bola e um detalhe por habilidade
local function areaEffect(ctx, center, radius)
	local ground = groundBelow(center, ctx.Obstacles, 20)
	local floor = if ground then ground.Position else center - Vector3.new(0, 3, 0)
	local color = ctx.Color

	if ctx.Skill.Id == "MarteloSangue" then
		-- Cabeça de martelo de sangue caindo do alto
		local size = Vector3.new(radius * 0.5, radius * 0.35, radius * 0.35)
		local rotation = CFrame.lookAt(Vector3.zero, ctx.Look)
		local hammer = newEffect("Part", {
			Size = size,
			CFrame = CFrame.new(floor + Vector3.new(0, 14, 0)) * rotation,
			Color = color,
			Transparency = 0.1,
		}, 1)
		tween(hammer, 0.12, { CFrame = CFrame.new(floor + Vector3.new(0, size.Y / 2, 0)) * rotation }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		fadeOut(hammer, 0.2, 0.5)
	elseif ctx.Skill.Id == "MaosFantasma" then
		-- Mãos que saem do chão: uma em cada alvo atingido e algumas em volta
		local spots = {}
		for _, target in ctx.Hits do
			table.insert(spots, target.Root.Position)
		end
		for i = 1, 6 do
			local angle = (i / 6) * math.pi * 2
			local distance = radius * (0.35 + 0.5 * math.random())
			table.insert(spots, center + Vector3.new(math.cos(angle) * distance, 0, math.sin(angle) * distance))
		end
		for _, spot in spots do
			local base = Vector3.new(spot.X, floor.Y, spot.Z)
			local hand = newEffect("Part", {
				Size = Vector3.new(0.9, 4, 0.9),
				CFrame = CFrame.new(base - Vector3.new(0, 2, 0)),
				Color = color,
				Transparency = 0.35,
			}, 1.1)
			tween(hand, 0.2, { CFrame = CFrame.new(base + Vector3.new(0, 2, 0)) })
			fadeOut(hand, 0.4, 0.5)
		end
	end

	task.delay(if ctx.Skill.Id == "MarteloSangue" then 0.12 else 0, function()
		shockwave(floor + Vector3.new(0, 0.2, 0), color, radius * 2, 0.45)
		burst(Vector3.new(center.X, floor.Y + 1, center.Z), color, radius, 0.35)
	end)
end

-- Rastro no chão e uma barbatana (WedgePart) que corre pelo caminho do Dash
local function dashEffect(ctx, start, finish)
	local color = ctx.Color
	local offset = finish - start
	local length = offset.Magnitude
	local ground = groundBelow(start, ctx.Obstacles, 12)
	local low = Vector3.new(0, if ground then ground.Position.Y - start.Y else -3, 0)

	burst(start + low, color, 5, 0.35)
	if length > 0.5 then
		local trail = newEffect("Part", {
			Size = Vector3.new(2.5, 0.3, length),
			CFrame = CFrame.lookAt(start:Lerp(finish, 0.5) + low, finish + low),
			Color = color,
			Transparency = 0.3,
		}, 0.9)
		tween(trail, 0.8, { Size = Vector3.new(0.3, 0.3, length), Transparency = 1 })

		-- A WedgePart afina para -Z: com lookAt no destino, a parte baixa vai na frente, como uma barbatana
		local finHeight = low + Vector3.new(0, 1.2, 0)
		local fin = newEffect("WedgePart", {
			Size = Vector3.new(0.4, 3, 3),
			CFrame = CFrame.lookAt(start + finHeight, finish + finHeight),
			Color = color,
			Transparency = 0.1,
		}, 0.9)
		tween(fin, 0.2, { CFrame = CFrame.lookAt(finish + finHeight, finish + finHeight + offset.Unit) })
		fadeOut(fin, 0.2, 0.4)
	end
	burst(finish + low, color, 6, 0.4)
end

----------------------------------------------------------------------------------------------------
-- Tipos de habilidade (PathData: Cone, Area, Dash, Projectile, Mark, Buff)
----------------------------------------------------------------------------------------------------

local Kinds = {}

-- Golpe em cone à frente: Range, Angle (graus)
function Kinds.Cone(ctx)
	local skill = ctx.Skill
	local range = skill.Range or 10
	if skill.FoxBite then
		local position = ctx.AimPosition or (ctx.Root.Position + ctx.Look * range * 0.7)
		local direction = position - ctx.Root.Position
		local flat = Vector3.new(direction.X, 0, direction.Z)
		local look = if flat.Magnitude > 0.01 then flat.Unit else ctx.Look
		-- Área da mordida (Radius do PathData); o cliente usa o mesmo raio na cratera
		local radius = skill.Radius or math.clamp(range * 0.35, 3, 6)
		local startTime = workspace:GetServerTimeNow()
		Remotes.CombatFX:FireAllClients("FoxBite", {
			Character = ctx.Character, Position = position, Look = look, Radius = radius,
			StartTime = startTime,
		})
		CombatState.SetBusy(ctx.Player, startTime + FoxConfig.ImpactDelay + 0.1)
		task.wait(FoxConfig.ImpactDelay)
		if not ctx.Character.Parent or ctx.Humanoid.Health <= 0 or ctx.Character:GetAttribute("Stunned") then return end
		local devoured = {}
		for _, target in collectTargets(ctx, position, radius) do
			if (target.Root.Position - position).Magnitude <= radius + HIT_TOLERANCE
				and clearPath(position, target.Root.Position, ctx.Obstacles) and hitTarget(ctx, target) > 0 then
				if canDevour(skill, target) then
					-- Sem nada que possa ceder (yield) entre o dano e o atributo: o Died do EnemyModule já vê o Devoured
					devour(target)
					contractXP(ctx, target, true)
					table.insert(devoured, { Model = target.Model, Position = target.Root.Position })
				else
					-- Quem é mordido voa para longe do centro e para cima
					local away = target.Root.Position - position
					local awayFlat = Vector3.new(away.X, 0, away.Z)
					local direction = if awayFlat.Magnitude > 0.1 then awayFlat.Unit else look
					launch(target, direction * (skill.Knockback or 0) + Vector3.new(0, skill.KnockbackUp or 0, 0), 0.22)
					Destruction.Launch(target.Model, 0.22)
				end
			end
		end
		-- A mordida arranca o que estiver na área (menos o chão)
		Destruction.Blast(position, radius, { Power = 65 })
		if #devoured > 0 then
			-- StartTime igual ao do FoxBite: o cliente acha a mesma raposa
			Remotes.CombatFX:FireAllClients("FoxDevour", {
				Character = ctx.Character, StartTime = startTime, Position = position, Targets = devoured,
			})
		end
		return
	end
	local minDot = math.cos(math.rad((skill.Angle or 60) / 2))
	local origin = ctx.Root.Position
	for _, target in collectTargets(ctx, origin, range + HIT_TOLERANCE) do
		local offset = target.Root.Position - origin
		local flat = Vector3.new(offset.X, 0, offset.Z)
		local inFront = flat.Magnitude < HIT_TOLERANCE or ctx.Look:Dot(flat.Unit) >= minDot
		if offset.Magnitude <= range + HIT_TOLERANCE and inFront
			and clearPath(origin, target.Root.Position, ctx.Obstacles) then
			hitTarget(ctx, target)
		end
	end
	biteEffect(ctx, range)
end

-- Bote da Raposa (ContractData): a cabeça do Kon sai de um portal atrás do jogador e avança em linha reta até Range
-- studs (parando antes de parede), na direção mirada. Quem ela alcança (Width de largura) leva o dano na hora e é
-- arrastado junto; no fim a mordida arremessa os arrastados. O efeito é do cliente (FoxDevilVFX.Lunge).
function Kinds.FoxLunge(ctx)
	local skill = ctx.Skill
	local range = skill.Range or 30
	local width = skill.Width or 8
	local start = ctx.Root.Position
	local look = ctx.Look
	if ctx.AimPosition then
		local offset = ctx.AimPosition - start
		local flat = Vector3.new(offset.X, 0, offset.Z)
		if flat.Magnitude > 0.5 then
			look = flat.Unit
		end
	end
	local distance = range
	for _, height in { 0, 1.5 } do
		local wall = workspace:Raycast(start + Vector3.new(0, height, 0), look * range, ctx.Obstacles)
		if wall then
			distance = math.min(distance, wall.Distance - 1)
		end
	end
	distance = math.max(4, distance)
	local finish = start + look * distance
	local startTime = workspace:GetServerTimeNow()
	Remotes.CombatFX:FireAllClients("FoxLunge", {
		Character = ctx.Character, Start = start, Finish = finish, Width = width, StartTime = startTime,
	})
	-- O bloqueio cobre a abertura do portal, o avanço e a recuperação da mordida final.
	CombatState.SetBusy(ctx.Player, startTime + FoxConfig.LungeDelay + FoxConfig.LungeTime + 0.1)
	task.wait(FoxConfig.LungeDelay)

	local behind = FoxConfig.LungeBehind
	local travel = FoxConfig.LungeTime
	local speed = (distance + behind) / travel
	local caught = {}
	local began = os.clock()
	local brokenUntil = 0 -- a cabeça quebra o caminho a cada LUNGE_BREAK_STEP studs
	while ctx.Character.Parent and ctx.Humanoid.Health > 0 do
		local t = math.min(1, (os.clock() - began) / travel)
		local along = (distance + behind) * t - behind
		local head = start + look * along
		if along >= brokenUntil or t >= 1 then
			brokenUntil = along + LUNGE_BREAK_STEP
			Destruction.Blast(head + Vector3.new(0, 1, 0), width / 2, { Power = 55 })
		end
		for _, target in collectTargets(ctx, head, width / 2 + HIT_TOLERANCE) do
			if not caught[target.Model] and clearPath(head, target.Root.Position, ctx.Obstacles) and hitTarget(ctx, target) > 0 then
				caught[target.Model] = target
				Remotes.CombatFX:FireAllClients("FoxLungeCatch", { Position = target.Root.Position, Look = look })
				-- Arrastado junto com a cabeça até o fim do caminho
				launch(target, look * speed * 0.9 + Vector3.new(0, 4, 0), math.max(0.05, (1 - t) * travel))
			end
		end
		if t >= 1 then break end
		task.wait(0.03)
	end
	-- Mordida final: quem foi arrastado voa para a frente e para cima
	for _, target in caught do
		if target.Humanoid.Health > 0 and target.Root.Parent then
			launch(target, look * (skill.Knockback or 0) + Vector3.new(0, skill.KnockbackUp or 0, 0), 0.22)
			Destruction.Launch(target.Model, 0.22)
		end
	end
end

-- Explosão centrada Range studs à frente (sem passar de parede): Range, Radius
function Kinds.Area(ctx)
	local skill = ctx.Skill
	local range = skill.Range or 0
	local radius = skill.Radius or 8
	local origin = ctx.Root.Position
	local distance = range
	if range > 0 then
		local wall = workspace:Raycast(origin, ctx.Look * range, ctx.Obstacles)
		if wall then
			distance = math.max(0, wall.Distance - 1)
		end
	end
	local center = origin + ctx.Look * distance
	for _, target in collectTargets(ctx, center, radius + HIT_TOLERANCE) do
		if (target.Root.Position - center).Magnitude <= radius + HIT_TOLERANCE
			and clearPath(center, target.Root.Position, ctx.Obstacles) then
			hitTarget(ctx, target)
		end
	end
	areaEffect(ctx, center, radius)
	Destruction.Blast(center, radius, { Power = 50 })
end

-- Avança Range studs (parando antes de paredes) e acerta quem estiver no caminho: Range, Radius
function Kinds.Dash(ctx)
	local skill = ctx.Skill
	local range = skill.Range or 20
	local radius = skill.Radius or 5
	local start = ctx.Root.Position

	-- Destino calculado no servidor: raio na altura do tronco e da cabeça
	local distance = range
	for _, height in { 0, 1.5 } do
		local wall = workspace:Raycast(start + Vector3.new(0, height, 0), ctx.Look * range, ctx.Obstacles)
		if wall then
			distance = math.min(distance, wall.Distance - DASH_WALL_MARGIN)
		end
	end
	distance = math.max(0, distance)
	local finish = start + ctx.Look * distance

	-- Rampa: se o chão no destino for um pouco mais alto, sobe o destino para não entrar no chão.
	-- Subida maior que DASH_MAX_LIFT provavelmente é teto ou parede: aí o destino fica como está.
	local startGround = groundBelow(start, ctx.Obstacles, 12)
	local endGround = groundBelow(finish + Vector3.new(0, DASH_MAX_LIFT, 0), ctx.Obstacles, DASH_MAX_LIFT + 12)
	if startGround and endGround then
		local heightAboveGround = start.Y - startGround.Position.Y
		local lift = endGround.Position.Y + heightAboveGround - finish.Y
		if lift > 0 and lift <= DASH_MAX_LIFT then
			finish += Vector3.new(0, lift, 0)
		end
	end

	local move = finish - start
	if move.Magnitude > 0.1 then
		ctx.Character:PivotTo(ctx.Character:GetPivot() + move)
	end

	-- Acerta quem estiver perto do segmento início -> fim
	local searchRadius = move.Magnitude / 2 + radius + HIT_TOLERANCE
	for _, target in collectTargets(ctx, start:Lerp(finish, 0.5), searchRadius) do
		local gap, closest = closestOnSegment(target.Root.Position, start, finish)
		if gap <= radius + HIT_TOLERANCE and clearPath(closest, target.Root.Position, ctx.Obstacles) then
			hitTarget(ctx, target)
		end
	end
	dashEffect(ctx, start, finish)
end

-- Projétil reto: Part Neon ancorada que avança a cada Heartbeat até Range, parando no primeiro alvo
-- ou parede: Range, Speed (studs/s), Radius
function Kinds.Projectile(ctx)
	local skill = ctx.Skill
	local range = skill.Range or 50
	local speed = math.max(1, skill.Speed or 80)
	local radius = skill.Radius or 2
	local direction = ctx.Look
	local position = ctx.Root.Position
	local traveled = 0
	local finished = false
	local connection

	local spear = newEffect("Part", {
		Size = Vector3.new(0.5, 0.5, 5),
		CFrame = CFrame.lookAt(position, position + direction),
		Color = ctx.Color,
		Transparency = 0,
	}, range / speed + 2)

	local function finish(at)
		if finished then return end
		finished = true
		if connection then
			connection:Disconnect()
		end
		spear:Destroy()
		burst(at, ctx.Color, radius * 2.5, 0.3)
		Destruction.Blast(at, radius * 1.5, { Power = 40 })
	end

	connection = RunService.Heartbeat:Connect(function(dt)
		if finished then return end
		if not ctx.Player.Parent or not spear.Parent then
			finish(position)
			return
		end
		local step = math.min(speed * dt, range - traveled)
		if step <= 0 then
			finish(position)
			return
		end

		local nextPosition = position + direction * step
		local wall = workspace:Raycast(position, direction * step, ctx.Obstacles)
		if wall then
			nextPosition = wall.Position
		end

		-- Primeiro alvo tocado neste trecho
		local best, bestDistance = nil, math.huge
		local searchRadius = (nextPosition - position).Magnitude / 2 + radius + HIT_TOLERANCE
		for _, target in collectTargets(ctx, position:Lerp(nextPosition, 0.5), searchRadius) do
			if not ctx.HitSet[target.Model] then
				local gap, closest = closestOnSegment(target.Root.Position, position, nextPosition)
				local along = (closest - position).Magnitude
				if gap <= radius + HIT_TOLERANCE and along < bestDistance
					and clearPath(closest, target.Root.Position, ctx.Obstacles) then
					best, bestDistance = target, along
				end
			end
		end
		if best then
			hitTarget(ctx, best)
			finish(best.Root.Position)
			return
		end

		traveled += (nextPosition - position).Magnitude
		position = nextPosition
		spear.CFrame = CFrame.lookAt(position, position + direction)
		if wall or traveled >= range - 0.01 then
			finish(position)
		end
	end)
end

-- Primeiro alvo à frente (o mais perto dentro de 35° e de Range, sem parede no meio)
local function findMarkTarget(ctx)
	local range = ctx.Skill.Range or 12
	local origin = ctx.Root.Position
	local best, bestDistance = nil, math.huge
	for _, target in collectTargets(ctx, origin, range + HIT_TOLERANCE) do
		local offset = target.Root.Position - origin
		local flat = Vector3.new(offset.X, 0, offset.Z)
		local distance = offset.Magnitude
		local inFront = flat.Magnitude < HIT_TOLERANCE or ctx.Look:Dot(flat.Unit) >= MARK_MIN_DOT
		if distance <= range + HIT_TOLERANCE and distance < bestDistance and inFront
			and clearPath(origin, target.Root.Position, ctx.Obstacles) then
			best, bestDistance = target, distance
		end
	end
	return best
end

-- Marca o primeiro alvo à frente; depois de Delay segundos a marca explode com Damage se ele continuar vivo
function Kinds.Mark(ctx)
	local target = ctx.Target or findMarkTarget(ctx)
	if not target then return end
	local delayTime = math.max(0, ctx.Skill.Delay or 3)

	-- Highlight vermelho que fica mais forte até a explosão
	local highlight = Instance.new("Highlight")
	highlight.FillColor = MARK_COLOR
	highlight.OutlineColor = MARK_COLOR
	highlight.FillTransparency = 0.8
	highlight.OutlineTransparency = 0
	highlight.Adornee = target.Model
	highlight.Parent = target.Model
	Debris:AddItem(highlight, delayTime + 0.5)
	tween(highlight, delayTime, { FillTransparency = 0.15 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)

	-- Prego cravado no peito do alvo (acompanha o alvo a cada Heartbeat)
	local nail = newEffect("Part", {
		Size = Vector3.new(0.3, 0.3, 3),
		CFrame = target.Root.CFrame,
		Color = ctx.Color,
		Transparency = 0,
	}, delayTime + 0.5)
	local follow = RunService.Heartbeat:Connect(function()
		if target.Root.Parent and nail.Parent then
			nail.CFrame = target.Root.CFrame * CFrame.new(0, 0.6, -1) * CFrame.Angles(math.rad(20), 0, 0)
		end
	end)
	burst(target.Root.Position, ctx.Color, 3, 0.25)

	task.delay(delayTime, function()
		follow:Disconnect()
		if nail.Parent then nail:Destroy() end
		if highlight.Parent then highlight:Destroy() end

		-- Só explode se o alvo continuar vivo (e o atacante ainda estiver no jogo)
		if not ctx.Player.Parent or not target.Model.Parent or not target.Root.Parent then return end
		if target.Humanoid.Health <= 0 then return end
		if not CombatRules.CanDamage(ctx.Player, target.Model) then return end

		local position = target.Root.Position
		hitTarget(ctx, target)
		burst(position, ctx.Color, 12, 0.45)
		shockwave(position - Vector3.new(0, 2.5, 0), ctx.Color, 16, 0.5)
	end)
end

-- Efeito em si mesmo por Duration segundos (VisaoFutura: esquiva de todo dano)
function Kinds.Buff(ctx)
	local skill = ctx.Skill
	local duration = math.max(0, skill.Duration or 3)
	local character = ctx.Character

	if skill.Id == "VisaoFutura" then
		-- O CombatRules zera o dano enquanto GetServerTimeNow() < DodgeUntil
		local dodgeUntil = workspace:GetServerTimeNow() + duration
		local current = character:GetAttribute("DodgeUntil")
		character:SetAttribute("DodgeUntil", if type(current) == "number" then math.max(current, dodgeUntil) else dodgeUntil)
	end

	-- Highlight (azul na Visão do Futuro) durante o efeito
	local highlight = Instance.new("Highlight")
	highlight.FillColor = ctx.Color
	highlight.OutlineColor = Color3.fromRGB(190, 225, 255)
	highlight.FillTransparency = 0.6
	highlight.OutlineTransparency = 0
	highlight.DepthMode = Enum.HighlightDepthMode.Occluded
	highlight.Adornee = character
	highlight.Parent = character
	Debris:AddItem(highlight, duration)

	local ground = groundBelow(ctx.Root.Position, ctx.Obstacles, 12)
	local floor = if ground then ground.Position else ctx.Root.Position - Vector3.new(0, 3, 0)
	shockwave(floor + Vector3.new(0, 0.2, 0), ctx.Color, 14, 0.5)
	burst(ctx.Root.Position + Vector3.new(0, 2, 0), ctx.Color, 3, 0.4)
end

----------------------------------------------------------------------------------------------------
-- Remote
----------------------------------------------------------------------------------------------------

local function newContext(player, character, humanoid, root, skill)
	-- Só inimigos e outros jogadores (CombatRules.TargetOverlap): as consultas de área não passam pelas peças do mapa
	local overlap = CombatRules.TargetOverlap(character)
	return {
		Player = player,
		Character = character,
		Humanoid = humanoid,
		Root = root,
		Skill = skill,
		Look = flatLook(root),
		Color = SKILL_COLORS[skill.Id] or DEFAULT_COLOR,
		Overlap = overlap,
		Obstacles = obstacleParams(character),
		HitSet = {}, -- HitSet[model] = true: já levou dano neste uso
		Hits = {}, -- alvos que levaram dano (para os efeitos)
		Target = nil, -- Mark: alvo escolhido antes de cobrar o custo
		-- Destruição do mapa para módulos de fora (BloodFiendSkills): ctx.Destruction.Blast(posição, raio, { Power })
		Destruction = Destruction,
	}
end

-- Habilidade que está no slot agora, conforme o caminho salvo no servidor (nil se o slot estiver vazio)
-- (PathModule.Get devolve três valores; eles precisam ir separados, antes do slot)
local function currentSkill(player, slot)
	-- Modo híbrido de admin (/hibrido): os atributos são escritos só pelo servidor
	if player:GetAttribute("Hybrid") == true then
		local skill = PathData.PlayerSkill(player, slot)
		return if type(skill) == "table" then skill else nil
	end
	if slot == "HZ" or slot == "HX" then return nil end
	local path, contracts, fiendType, form = PathModule.Get(player)
	if type(path) ~= "string" then return nil end
	local skill = PathData.GetSkill(
		path,
		if type(contracts) == "table" then contracts else {},
		if type(fiendType) == "string" then fiendType else "",
		slot,
		form
	)
	return if type(skill) == "table" then skill else nil
end

-- Server time em que a habilidade do slot fica pronta. A recarga guardada só vale para a mesma
-- habilidade que a gerou: depois de trocar de caminho ou de contrato, um poder novo no slot começa pronto.
local function slotReadyAt(player, slot, skill)
	local playerCooldowns = cooldowns[player]
	local entry = playerCooldowns and playerCooldowns[slot]
	if entry and skill and entry.SkillId == skill.Id then
		return entry.ReadyAt
	end
	return 0
end

-- Depois de uma mudança de caminho ou de contratos, cada atributo Power<slot>ReadyAt passa a mostrar a
-- recarga da habilidade que está no slot agora (0 se ela mudou), para a HUD e o PowerInput não
-- mostrarem no poder novo a recarga do antigo
local function syncReadyAttributes(player)
	if not player.Parent then return end
	for slot in SLOTS do
		local readyAt = slotReadyAt(player, slot, currentSkill(player, slot))
		local attribute = "Power" .. slot .. "ReadyAt"
		if player:GetAttribute(attribute) ~= readyAt then
			player:SetAttribute(attribute, readyAt)
		end
	end
end

local function onUsePower(player, slot, aimPosition)
	if type(slot) ~= "string" or not SLOTS[slot] then return end

	-- Personagem vivo e sem stun
	local character = player.Character
	if not character or not character.Parent then return end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart")
	if not humanoid or humanoid.Health <= 0 or not root or not root:IsA("BasePart") then return end
	if character:GetAttribute("Stunned") == true then return end
	-- Com a guarda levantada, carregando o R, na Rajada ou no começo de um soco: nada de poder
	if CombatState.IsLocked(player) then return end

	-- Habilidade do slot conforme o caminho salvo no servidor
	local skill = currentSkill(player, slot)
	if not skill then return end
	local run = Kinds[skill.Kind]
	if BloodFiendSkills and BloodFiendSkills.Handles(skill.Id)
		and StarterPlayer.StarterPlayerScripts:FindFirstChild("BloodFiendVFX") then
		run = BloodFiendSkills.Cast
	end
	if not run then
		warn(`[PathSkills] Tipo de habilidade desconhecido: {tostring(skill.Kind)} ({tostring(skill.Id)})`)
		return
	end

	-- Cooldown da habilidade do slot e intervalo mínimo entre poderes (servidor)
	local now = workspace:GetServerTimeNow()
	if now < slotReadyAt(player, slot, skill) or now < (busyUntil[player] or 0) then return end

	local ctx = newContext(player, character, humanoid, root, skill)
	local path, contracts = PathModule.Get(player)
	if path == "Hunter" and type(contracts) == "table" then
		ctx.ContractId = contracts[1] -- maestria do contrato nos acertos (contractXP)
	end
	-- Mira (FoxAim): a mordida morde o ponto e o bote vai na direção dele
	if (skill.FoxBite or skill.Kind == "FoxLunge") and aimPosition ~= nil then
		if typeof(aimPosition) ~= "Vector3" then return end
		for _, value in {aimPosition.X, aimPosition.Y, aimPosition.Z} do
			if value ~= value or math.abs(value) > 1e7 then return end
		end
		local offset = aimPosition - root.Position
		if offset.Magnitude > FoxConfig.MaxAimDistance then
			aimPosition = root.Position + offset.Unit * FoxConfig.MaxAimDistance
		end
		local start = root.Position + Vector3.new(0, 1, 0)
		local wall = workspace:Raycast(start, aimPosition - start, ctx.Obstacles)
		if wall then aimPosition = wall.Position + wall.Normal * 1.5 end
		ctx.AimPosition = aimPosition
	end

	-- Checagens do tipo antes de cobrar o custo
	if skill.Kind == "Mark" then
		ctx.Target = findMarkTarget(ctx)
		if not ctx.Target then
			notice(player, skill.Name, "Nenhum alvo à frente.")
			return
		end
	elseif skill.Kind == "Dash" and humanoid.SeatPart then
		return
	end

	-- Custo em vida (Infernal): fração da vida máxima, e nunca pode matar
	local healthCost = 0
	if type(skill.HealthCost) == "number" and skill.HealthCost > 0 then
		healthCost = skill.HealthCost * humanoid.MaxHealth
		if humanoid.Health <= healthCost then
			notice(player, skill.Name, "Vida insuficiente para usar este poder.")
			return
		end
	end

	-- Custo em tempo de vida (Caçador). No modo híbrido, quem não é Caçador de verdade não tem tempo de vida: não gasta.
	local hybridFree = player:GetAttribute("Hybrid") == true and path ~= "Hunter"
	if type(skill.LifespanCost) == "number" and skill.LifespanCost > 0 and not hybridFree then
		if not PathModule.SpendLifespan(player, skill.LifespanCost) then
			notice(player, skill.Name, "Tempo de vida insuficiente para usar este poder.")
			return
		end
	end

	if healthCost > 0 then
		-- Direto na vida: não é dano de ninguém, então não marca LastAttacker
		humanoid.Health = math.max(1, humanoid.Health - healthCost)
	end

	local readyAt = now + (tonumber(skill.Cooldown) or 1)
	local playerCooldowns = cooldowns[player]
	if not playerCooldowns then
		playerCooldowns = {}
		cooldowns[player] = playerCooldowns
	end
	playerCooldowns[slot] = { SkillId = skill.Id, ReadyAt = readyAt }
	busyUntil[player] = now + GLOBAL_LOCK
	player:SetAttribute("Power" .. slot .. "ReadyAt", readyAt)

	-- Parado enquanto o poder acontece (CombatSpeed 0; o cliente já parou na hora pelo PredictedRootUntil). Solta no fim
	-- do poder ou em POWER_ROOT_MAX, o que vier primeiro (a lança voando não prende quem jogou).
	local rootToken = {}
	rootTokens[player] = rootToken
	CombatState.SetSpeed(player, "Power", 0)
	task.delay(POWER_ROOT_MAX, function()
		if rootTokens[player] == rootToken then
			rootTokens[player] = nil
			CombatState.SetSpeed(player, "Power", nil)
		end
	end)
	local ok, err = pcall(run, ctx)
	if not ok then
		warn(`[PathSkills] Erro ao usar {tostring(skill.Id)}: {err}`)
	end
	if rootTokens[player] == rootToken then
		rootTokens[player] = nil
		CombatState.SetSpeed(player, "Power", nil)
	end

	if type(QuestModule.OnPowerUsed) == "function" then
		task.spawn(QuestModule.OnPowerUsed, player, skill.Id)
	end
end

local function onPlayerAdded(player)
	-- Começa pronto (a HUD lê estes atributos)
	for slot in SLOTS do
		if player:GetAttribute("Power" .. slot .. "ReadyAt") == nil then
			player:SetAttribute("Power" .. slot .. "ReadyAt", 0)
		end
	end
end

Players.PlayerAdded:Connect(onPlayerAdded)
for _, player in Players:GetPlayers() do
	onPlayerAdded(player)
end

Players.PlayerRemoving:Connect(function(player)
	cooldowns[player] = nil
	busyUntil[player] = nil
	lastNotice[player] = nil
	rootTokens[player] = nil
end)

-- Troca de caminho ou novo contrato: a recarga de um poder não passa para o poder que entrou no slot
if PathModule.PathChanged then
	PathModule.PathChanged:Connect(syncReadyAttributes)
else
	warn("[PathSkills] PathModule.PathChanged não existe; a recarga dos slots não é atualizada ao trocar de caminho")
end

Remotes.UsePower.OnServerEvent:Connect(onUsePower)
