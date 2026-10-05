-- Golpes dos estilos de combate (CombatStyles): combo de 5 M1 (o 5º arremessa; no ar o 4º vira uppercut),
-- bloqueio com parry e quebra de guarda (CombatState) e as skills das teclas Z/X/C por tipo (SkillKinds, campo Kind da
-- skill: "Barrage" = Rajada, "Charge" = Soco carregado, segurar e soltar; da Katana: "DashSlash" = Avanço cortante,
-- "Grab" = Agarrão, "DrawSlash" = Saque).
--
-- Cliente prevê, servidor valida:
--   1. O cliente toca a animação na hora e avisa o golpe (CombatM1 / soltar o R, com um número seq).
--      Aqui o servidor confere estado, recarga e combo e guarda o golpe como "pendente".
--   2. No frame do impacto (marcador da animação ou windup), a hitbox do cliente manda quem pegou (CombatHit).
--      O servidor só aceita alvos de um golpe pendente, vivos, que podem levar dano, no alcance (+ tolerância),
--      na frente e sem parede no meio. Aí aplica dano, stun e empurrão.
--   3. O empurrão de jogador é aplicado pelo cliente dele (CombatImpulse), sem tremer; o de NPC, aqui.
-- A Rajada e as skills da Katana têm hitbox no servidor, nos tempos dos marcadores das animações (CombatStyles).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Debris = game:GetService("Debris")

local Remotes = require(ReplicatedStorage:WaitForChild("Remotes"))
local CombatStyles = require(ReplicatedStorage:WaitForChild("CombatStyles"))
local CombatState = require(ServerScriptService:WaitForChild("CombatState"))
local CombatRules = require(ServerScriptService:WaitForChild("CombatRules"))
local CombatRewind = require(ServerScriptService:WaitForChild("CombatRewind"))
local CombatNetConfig = require(ReplicatedStorage:WaitForChild("CombatNetConfig"))
local PlayerData = require(ServerScriptService:WaitForChild("PlayerData"))
local StyleWeapons = require(ServerScriptService:WaitForChild("StyleWeapons"))
local SkillTreeData = require(ReplicatedStorage:WaitForChild("SkillTreeData"))
local ContractData = require(ReplicatedStorage:WaitForChild("ContractData"))

local MAX_TARGETS = 8 -- alvos aceitos por golpe
local FACING_SLACK = 0.35 -- o atacante pode ter girado um pouco entre o cliente e o servidor

local rng = Random.new()

local function now()
	return workspace:GetServerTimeNow()
end

local function lerp(a, b, t)
	return a + (b - a) * t
end

local function flatLook(root)
	local look = root.CFrame.LookVector
	local flat = Vector3.new(look.X, 0, look.Z)
	return if flat.Magnitude > 0.001 then flat.Unit else Vector3.new(0, 0, -1)
end

-- Número de golpe mandado pelo cliente: inteiro, finito, positivo
local function isSeq(value)
	return type(value) == "number" and value == value and value >= 0 and value < 2 ^ 31 and math.floor(value) == value
end

-- ================= Animação de quem apanha =================
-- As animações de quem ataca (golpes, guarda, carga, rajada) são tocadas pelo próprio cliente
-- (CombatAnimations.luau). Aqui só a reação de quem leva o golpe, quando o estilo tem o ID.

local function playHit(humanoid, id)
	if not id then return nil end
	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = humanoid
	end
	local animation = Instance.new("Animation")
	animation.AnimationId = "rbxassetid://" .. id
	local ok, track = pcall(function()
		return animator:LoadAnimation(animation)
	end)
	animation:Destroy()
	if not ok or not track then return nil end
	track.Priority = Enum.AnimationPriority.Action2 -- reação: acima de dash/movimento, abaixo de ataque
	track.Looped = false
	track:Play(0.05)
	Debris:AddItem(track, 4)
	return track
end

-- ================= Contexto do atacante =================

local function getContext(player)
	local character = player.Character
	if not character then return nil end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart")
	if not humanoid or humanoid.Health <= 0 or not root then return nil end
	if character:GetAttribute("Stunned") == true then return nil end
	local styleName, style = CombatStyles.FromCharacter(character)
	if not style then return nil end
	return {
		Player = player,
		Character = character,
		Humanoid = humanoid,
		Root = root,
		StyleName = styleName,
		Style = style,
	}
end

-- O golpe ainda vale? (mesmo personagem, vivo, não atordoado, estilo ainda equipado)
local function stillValid(ctx)
	local character = ctx.Character
	return ctx.Player.Character == character
		and character.Parent ~= nil
		and ctx.Humanoid.Health > 0
		and ctx.Root.Parent ~= nil
		and character:GetAttribute("Stunned") ~= true
		and CombatStyles.FromCharacter(character) == ctx.StyleName
end

-- ================= Alvos =================

-- Personagens, inimigos e efeitos não contam como parede no teste de linha de visão
local function losParams(character)
	local list = { character }
	local enemies = workspace:FindFirstChild("Enemies")
	if enemies then
		table.insert(list, enemies)
	end
	for _, other in Players:GetPlayers() do
		if other.Character then
			table.insert(list, other.Character)
		end
	end
	local effects = workspace:FindFirstChild("PowerEffects")
	if effects then
		table.insert(list, effects)
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = list
	params.RespectCanCollide = true -- zonas invisíveis (EnemySpawns) não são parede
	params.IgnoreWater = true -- água do Terrain também não
	return params
end

-- Confere um alvo: vivo, pode levar dano, no alcance, na frente e sem parede no meio
local function checkTarget(ctx, model, range, minDot, rayParams, record)
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	local root = model:FindFirstChild("HumanoidRootPart")
	if not humanoid or humanoid.Health <= 0 or not root or not root:IsA("BasePart") then return nil end
	if not CombatRules.CanDamage(ctx.Player, model) then return nil end
	if not CombatRewind.FrameValid(ctx.Root.CFrame) or not CombatRewind.FrameValid(root.CFrame) then return nil end
	local frame = if record then record.HitOrigin else ctx.Root.CFrame
	local targetFrame = if record then CombatRewind.Frame(model, record.RewindTime) else root.CFrame
	if not frame or not targetFrame then return nil end
	local origin = frame.Position
	local offset = targetFrame.Position - origin
	local distance = offset.Magnitude
	if distance > range then return nil end
	if distance > 2 and frame.LookVector:Dot(offset.Unit) < minDot then return nil end
	if workspace:Raycast(origin, offset, rayParams) then return nil end
	-- Cobertura atual também vence: não acerta através de uma parede que fechou desde a amostra.
	if record and workspace:Raycast(ctx.Root.Position, root.Position - ctx.Root.Position, rayParams) then return nil end
	return { Model = model, Humanoid = humanoid, Root = root }
end

-- Alvos que o cliente mandou, conferidos com a tolerância de ping
local function validateTargets(ctx, targets, range, minDot, record)
	local result = {}
	if type(targets) ~= "table" then return result end
	local rayParams = losParams(ctx.Character)
	local seen, checked = {}, 0
	for _, model in targets do
		checked += 1
		if checked > MAX_TARGETS then break end
		if typeof(model) ~= "Instance" or not model:IsA("Model") or seen[model] then continue end
		seen[model] = true
		local target = checkTarget(ctx, model, range + CombatStyles.HitTolerance, minDot - FACING_SLACK, rayParams, record)
		if target then
			table.insert(result, target)
		end
	end
	return result
end

-- Hitbox do servidor (só a Rajada usa): tudo o que está na frente
local function findTargets(ctx, range, minDot)
	local overlap = CombatRules.TargetOverlap(ctx.Character)
	local rayParams = losParams(ctx.Character)
	local targets, seen = {}, {}
	for _, part in workspace:GetPartBoundsInRadius(ctx.Root.Position, range + 2, overlap) do
		local model = part:FindFirstAncestorOfClass("Model")
		if not model or seen[model] then continue end
		seen[model] = true
		local target = checkTarget(ctx, model, range, minDot, rayParams)
		if target then
			table.insert(targets, target)
		end
	end
	return targets
end

-- Hitbox da Rajada: o volume da peça HitboxPart da skill do VFX (ReplicatedStorage.VFX.Punchs.BarragePunch), no
-- mesmo lugar em que o CombatFX desenha o efeito (CombatStyles.BarrageBaseCFrame). Sem o VFX ou com a peça
-- minúscula, usa a hitbox redonda de Range studs.
local barrageBoxes = {} -- [skill] = { Offset = CFrame da peça em relação à base, Size = Vector3 }
local warnedBarrageBox = {}
local function barrageBox(skill)
	local cached = barrageBoxes[skill]
	if cached then return cached end
	local folder = ReplicatedStorage:FindFirstChild("VFX")
	folder = folder and folder:FindFirstChild("Punchs")
	local model = folder and folder:FindFirstChild("BarragePunch")
	if not model or type(skill.HitboxPart) ~= "string" then return nil end
	local base = if model:IsA("Model") then (model.PrimaryPart or model:FindFirstChild("crash4")) else model
	local part = model:FindFirstChild(skill.HitboxPart, true)
	if not base or not part or not part:IsA("BasePart") then return nil end
	-- Peça minúscula (ponto de onde saem partículas): vale a maior peça dentro dela, que é o volume que o Studio
	-- mostra ao selecionar (ex.: Crash1 de 0,001 com o crash3 de 12 x 9 x 9 dentro)
	local function volume(p)
		return p.Size.X * p.Size.Y * p.Size.Z
	end
	if math.max(part.Size.X, part.Size.Y, part.Size.Z) < 1 then
		local biggest
		for _, inner in part:GetDescendants() do
			if inner:IsA("BasePart") and (not biggest or volume(inner) > volume(biggest)) then
				biggest = inner
			end
		end
		if biggest then
			part = biggest
		end
	end
	if math.max(part.Size.X, part.Size.Y, part.Size.Z) < 1 then
		if not warnedBarrageBox[skill] then
			warnedBarrageBox[skill] = true
			warn(`[CombatService] A peça {skill.HitboxPart} do BarragePunch é pequena demais para ser hitbox ({part.Size}). `
				.. "Aumente o tamanho dela no Studio para cobrir a área da Rajada; por enquanto a hitbox é redonda.")
		end
		return nil
	end
	local box = { Offset = base.CFrame:ToObjectSpace(part.CFrame), Size = part.Size }
	barrageBoxes[skill] = box
	return box
end

local BARRAGE_BOX_MARGIN = Vector3.new(2, 2, 2) -- 1 stud de folga para cada lado (a vítima chega atrasada no servidor)

local function barrageTargets(ctx, skill)
	local box = barrageBox(skill)
	if not box then
		return findTargets(ctx, skill.Range + 1, skill.MinDot)
	end
	local boxCFrame = CombatStyles.BarrageBaseCFrame(ctx.Root.CFrame, skill) * box.Offset
	local overlap = CombatRules.TargetOverlap(ctx.Character)
	local rayParams = losParams(ctx.Character)
	-- A caixa já limita a área: o alcance só precisa cobrir o canto mais longe, e a frente não é cobrada
	local reach = (boxCFrame.Position - ctx.Root.Position).Magnitude + box.Size.Magnitude / 2 + 2
	local targets, seen = {}, {}
	for _, part in workspace:GetPartBoundsInBox(boxCFrame, box.Size + BARRAGE_BOX_MARGIN, overlap) do
		local model = part:FindFirstAncestorOfClass("Model")
		if not model or seen[model] then continue end
		seen[model] = true
		local target = checkTarget(ctx, model, reach, -1, rayParams)
		if target then
			table.insert(targets, target)
		end
	end
	return targets
end

-- ================= Empurrão =================

-- NPC: o servidor é dono da física dele, então o empurrão é aplicado aqui
local function knockback(root, velocity, duration)
	for _, child in root:GetChildren() do
		if child.Name == "CombatKnockback" then
			child:Destroy()
		end
	end
	local attachment = Instance.new("Attachment")
	attachment.Name = "CombatKnockback"
	attachment.Parent = root
	local mover = Instance.new("LinearVelocity")
	mover.Name = "CombatKnockback"
	mover.Attachment0 = attachment
	mover.RelativeTo = Enum.ActuatorRelativeTo.World
	mover.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
	mover.MaxForce = 1e6
	mover.VectorVelocity = velocity
	mover.Parent = root
	Debris:AddItem(mover, duration)
	Debris:AddItem(attachment, duration)
end

-- Jogador: o cliente dele aplica (ele é dono da física do próprio personagem; aplicar daqui treme)
local function impulse(target, velocity, duration)
	local victimPlayer = Players:GetPlayerFromCharacter(target.Model)
	if victimPlayer then
		Remotes.CombatImpulse:FireClient(victimPlayer, velocity, duration)
	else
		knockback(target.Root, velocity, duration)
	end
end

-- ================= Árvore de habilidades e maestria =================

-- Efeito da árvore do jogador (atributos Tree<Efeito> escritos pelo PlayerData), 0 se ele não tem
local function treeEffect(player, key)
	local value = player:GetAttribute("Tree" .. key)
	return if type(value) == "number" then value else 0
end

-- Nó da árvore que libera cada técnica (para o aviso dizer a maestria pedida)
local techniqueNodes = {}
for _, entry in SkillTreeData.Nodes do
	if entry.Effects.Technique then
		techniqueNodes[entry.Effects.Technique] = entry
	end
end

local LOCKED_NOTICE_INTERVAL = 3 -- segundos entre dois avisos de técnica bloqueada
local lockedNoticeAt = {}

-- A técnica do golpe (cfg.Technique) está liberada na árvore? Sem Technique, sempre. silent: não avisa.
local function hasTechnique(player, cfg, silent)
	local technique = cfg and cfg.Technique
	if not technique or PlayerData.HasTechnique(player, technique) then return true end
	local clock = os.clock()
	if not silent and (lockedNoticeAt[player] or 0) <= clock then
		lockedNoticeAt[player] = clock + LOCKED_NOTICE_INTERVAL
		local info = SkillTreeData.Techniques[technique]
		local entry = techniqueNodes[technique]
		local need = if entry and entry.Mastery then ` (maestria {entry.Mastery.Level} + {entry.Cost} pontos)` else ""
		PlayerData.Notify(player, "Técnica bloqueada",
			`{if info then info.Name else technique}: desbloqueie na árvore de habilidades (M){need}.`, 4)
	end
	return false
end

-- Empurrão de um golpe do jogador, com o bônus de Impacto da árvore
local function knock(ctx, target, velocity, duration)
	impulse(target, velocity * (1 + treeEffect(ctx.Player, "Knockback")), duration)
end

-- Aplica o dano e o efeito do acerto. predicted = quem atacou já mostrou o efeito no cliente dele.
-- Devolve o resultado do CombatRules ("Hit", "Blocked", "Broken", "Parried", "Dodged").
-- A árvore soma dano do estilo e dano na guarda; todo golpe que conecta dá XP de maestria no estilo.
-- opts.HitFX: campos a mais no efeito "Hit" (ex.: { Cut = "Cross" }); opts.NoHitReaction: não toca a reação de quem
-- apanha (o agarrão toca a própria animação na vítima).
local function strike(ctx, target, damage, opts, heavy, predicted)
	opts.Predicted = predicted
	damage *= 1 + treeEffect(ctx.Player, "Damage_" .. ctx.StyleName)
	if opts.GuardDamage then
		opts.GuardDamage *= 1 + treeEffect(ctx.Player, "GuardDamage")
	end
	local _, result = CombatRules.Damage(ctx.Player, target.Humanoid, damage, opts)
	-- O boneco de treino do tutorial (TutorialService) não dá maestria: não dá para farmar nele.
	-- Estilo fundido com o contrato (CombatStyles.Resolve): o golpe também sobe a maestria do contrato.
	if (result == "Hit" or result == "Blocked" or result == "Broken") and target.Model:GetAttribute("TrainingDummy") == nil then
		PlayerData.AddMastery(ctx.Player, ctx.StyleName, SkillTreeData.Mastery.XPPerHit)
		if ctx.Style.Fusion then
			PlayerData.AddContractMastery(ctx.Player, ctx.Style.Fusion, ContractData.Mastery.FusionHitXP)
		end
	end
	if result == "Hit" then
		local data = { Character = target.Model, Attacker = ctx.Character, Strong = heavy == true, Style = ctx.StyleName,
			Theme = ctx.Style.Theme } -- Theme: estilo fundido (o CombatFX desenha no tema do contrato)
		for key, value in opts.HitFX or {} do
			data[key] = value
		end
		CombatState.FX("Hit", data, if predicted then ctx.Player else nil)
		-- Chefe com reações próprias (atributo OwnHitReaction) toca as dele (BossService)
		if target.Humanoid.Health > 0 and target.Model:GetAttribute("OwnHitReaction") ~= true and not opts.NoHitReaction then
			playHit(target.Humanoid, CombatStyles.Animation(ctx.Style, "Hit", rng:NextInteger(1, 2)))
		end
	end
	return result
end

-- ================= Golpes pendentes =================
-- pending[player][seq] = { Kind, Ctx, Time, Combo?, Power? }: golpe avisado, esperando o acerto do cliente

local pending = {}

local function addPending(player, seq, record)
	local list = pending[player]
	if not list then
		list = {}
		pending[player] = list
	end
	local t = now()
	for key, old in list do
		if t - old.Time > CombatStyles.HitDeadline then
			list[key] = nil
		end
	end
	record.Time = t
	list[seq] = record
end

-- ================= M1 =================

local function onM1(player, seq, aerial)
	if not isSeq(seq) then return end
	local ctx = getContext(player)
	if not ctx or CombatState.IsBusy(player) then return end
	local cfg = ctx.Style.M1
	local hits = cfg.Hits or 5 -- golpes do combo (o último arremessa)
	local combo = CombatState.NextCombo(player, cfg.ComboReset, hits)
	-- Uppercut só com a técnica da árvore (e no estilo que tem: Uppercut = false tira); sem ela o 4º golpe no ar é um
	-- soco comum
	-- O cliente pede o uppercut; o servidor confirma que começou no ar (inclui o início do pulo).
	local humanoidState = ctx.Humanoid:GetState()
	local airborne = ctx.Humanoid.FloorMaterial == Enum.Material.Air
		or humanoidState == Enum.HumanoidStateType.Jumping
		or humanoidState == Enum.HumanoidStateType.Freefall
	local uppercut = combo == 4 and aerial == true and airborne
		and type(cfg.Uppercut) == "table" and hasTechnique(player, cfg.Uppercut, true)
	-- Interval: um tempo só ou um por golpe (o fim de cada animação, ex.: Punhos da Raposa)
	local interval = if type(cfg.Interval) == "table" then cfg.Interval[combo] or cfg.Interval[#cfg.Interval] else cfg.Interval
	local recovery = if combo == hits then cfg.EndLag else interval
	local t = now()
	-- O próximo M1 espera o golpe inteiro; skill, block e dash podem cancelar depois da CancelWindow
	CombatState.SetBusy(player, t + recovery, t + math.min(cfg.CancelWindow, recovery))

	-- Socando anda mais devagar (sem travar)
	local state = CombatState.Get(player)
	state.m1Token = (state.m1Token or 0) + 1
	local token = state.m1Token
	CombatState.SetSpeed(player, "M1", cfg.SpeedMultiplier)
	task.delay(recovery, function()
		if state.m1Token == token then
			CombatState.SetSpeed(player, "M1", nil)
		end
	end)

	local move = if uppercut then "Uppercut" else "M1"
	CombatState.MarkSwing(player)
	StyleWeapons.MarkCombat(ctx.Character, ctx.StyleName)
	addPending(player, seq, { Kind = move, Combo = combo, Ctx = ctx })
	-- Quem atacou já está vendo o próprio golpe
	CombatState.FX("Swing", { Character = ctx.Character, Style = ctx.StyleName, Move = move, Combo = combo }, player)
end

local function resolveM1(ctx, record, targets)
	local cfg = ctx.Style.M1
	local combo = record.Combo
	local finisher = combo == (cfg.Hits or 5)
	local uppercut = record.Kind == "Uppercut"
	local look = flatLook(ctx.Root)
	local valid = validateTargets(ctx, targets, cfg.Range, cfg.MinDot, record)
	-- Contra-golpe da esquiva (DodgeData, nível 3+): o 1º M1 que acerta logo depois de desviar bate mais forte
	local counter = if #valid > 0 then CombatRules.ConsumeCounter(ctx.Player) else 0
	for _, target in valid do
		local damage = (if uppercut then cfg.Uppercut.Damage else cfg.Damage[combo]) * (1 + counter)
		local opts = { ScaleWithForca = true, GuardDamage = cfg.GuardDamage[combo],
			HitFX = if counter > 0 then { Counter = true } else nil }
		if strike(ctx, target, damage, opts, finisher or uppercut, true) == "Hit" then
			if uppercut then
				CombatState.Stun(target.Humanoid, cfg.Uppercut.Stun)
				knock(ctx, target, Vector3.new(0, cfg.Uppercut.Launch, 0) + look * 4, 0.15)
			elseif finisher then
				CombatState.Stun(target.Humanoid, cfg.FinalStun)
				knock(ctx, target, look * cfg.Knockback + Vector3.new(0, cfg.KnockbackUp, 0), 0.2)
			else
				CombatState.Stun(target.Humanoid, cfg.Stun)
			end
		end
	end
end

-- ================= Rajada (Kind "Barrage") =================

local function doBarrage(player, slot)
	local ctx = getContext(player)
	if not ctx or CombatState.IsLocked(player) or not CombatState.IsReady(player, slot) then return end
	local cfg = ctx.Style.Skills[slot]
	if not cfg or not hasTechnique(player, cfg) then return end

	local state = CombatState.Get(player)
	state.actionToken += 1
	local token = state.actionToken
	StyleWeapons.MarkCombat(ctx.Character, ctx.StyleName)
	local hits = cfg.Hits + math.floor(treeEffect(player, "RajadaHits")) -- "Rajada longa" na árvore
	local duration = hits * cfg.HitInterval
	CombatState.SetCooldown(player, slot, cfg.Cooldown)
	CombatState.SetBusy(player, now() + duration + 0.15)
	CombatState.SetSpeed(player, "Barrage", cfg.SpeedMultiplier)
	CombatState.FX("Barrage", { Character = ctx.Character, Style = ctx.StyleName, Duration = duration })

	task.spawn(function()
		-- Protegido: um erro num golpe não pode pular a limpeza do fim (senão o jogador fica lento e sem dash)
		local ok, err = pcall(function()
			for hit = 1, hits do
				task.wait(cfg.HitInterval)
				if state.actionToken ~= token or not stillValid(ctx) then break end
				local look = flatLook(ctx.Root)
				local last = hit == hits
				-- Hitbox no servidor: o volume da peça do VFX (ou redonda, sem ele), com folga para o atraso da vítima
				for _, target in barrageTargets(ctx, cfg) do
					local opts = { ScaleWithForca = true, ForcaScale = cfg.ForcaScale, GuardDamage = cfg.GuardDamage }
					if strike(ctx, target, cfg.Damage, opts, last, false) == "Hit" then
						CombatState.Stun(target.Humanoid, cfg.Stun)
						if last then
							knock(ctx, target, look * cfg.FinalKnockback + Vector3.new(0, 8, 0), 0.15)
						end
					end
				end
			end
		end)
		if not ok then
			warn(`[CombatService] Rajada de {player.Name}: {err}`)
		end
		CombatState.SetSpeed(player, "Barrage", nil)
		CombatState.FX("BarrageEnd", { Character = ctx.Character })
	end)
end

-- ================= Soco carregado (Kind "Charge") =================

local function clearCharge(player, state)
	state.charging = nil
	local character = player.Character
	if character then
		character:SetAttribute("Charging", nil)
	end
	CombatState.SetSpeed(player, "Charge", nil)
end

local function cancelCharge(player, state, charging)
	clearCharge(player, state)
	CombatState.SetCooldown(player, charging.Slot, charging.Ctx.Style.Skills[charging.Slot].CancelCooldown)
	CombatState.FX("ChargeCancel", { Character = charging.Ctx.Character })
end

local function startCharge(player, slot)
	local ctx = getContext(player)
	if not ctx or CombatState.IsLocked(player) or not CombatState.IsReady(player, slot) then return end
	local cfg = ctx.Style.Skills[slot]
	if not cfg or not hasTechnique(player, cfg) then return end

	local state = CombatState.Get(player)
	state.actionToken += 1
	local token = state.actionToken
	-- "Carga rápida" na árvore encurta o tempo até a carga máxima
	local maxCharge = cfg.MaxCharge * math.max(0.2, 1 - treeEffect(player, "ChargeTime"))
	StyleWeapons.MarkCombat(ctx.Character, ctx.StyleName)
	local charging = { Start = now(), Token = token, Ctx = ctx, MaxCharge = maxCharge, Slot = slot }
	state.charging = charging
	ctx.Character:SetAttribute("Charging", true)
	CombatState.SetSpeed(player, "Charge", cfg.SpeedMultiplier)
	CombatState.FX("ChargeStart", { Character = ctx.Character, Style = ctx.StyleName, MaxCharge = maxCharge })

	-- O cliente solta sozinho no MaxHold; se o aviso nunca chegar, a carga é perdida
	task.delay(cfg.MaxHold + 0.5, function()
		if state.charging == charging then
			cancelCharge(player, state, charging)
		end
	end)
end

local function releaseCharge(player, seq)
	local state = CombatState.Get(player)
	local charging = state.charging
	if not charging then return end
	local ctx = charging.Ctx
	local cfg = ctx.Style.Skills[charging.Slot]

	if not isSeq(seq) or not stillValid(ctx) then
		cancelCharge(player, state, charging)
		return
	end
	clearCharge(player, state)

	local power = math.clamp((now() - charging.Start) / (charging.MaxCharge or cfg.MaxCharge), 0, 1)
	CombatState.SetCooldown(player, charging.Slot, cfg.Cooldown)
	CombatState.SetBusy(player, now() + cfg.Windup + 0.45)
	addPending(player, seq, { Kind = "ChargedPunch", Power = power, Ctx = ctx, Slot = charging.Slot })
	CombatState.FX("ChargedPunch", { Character = ctx.Character, Style = ctx.StyleName, Power = power }, player)
end

local function resolveChargedPunch(ctx, record, targets)
	local cfg = ctx.Style.Skills[record.Slot]
	local power = record.Power
	local look = flatLook(ctx.Root)
	local range = lerp(cfg.RangeMin, cfg.RangeMax, power)
	for _, target in validateTargets(ctx, targets, range, cfg.MinDot, record) do
		local opts = {
			ScaleWithForca = true,
			ForcaScale = cfg.ForcaScale,
			GuardDamage = lerp(cfg.GuardDamageMin, cfg.GuardDamageMin * 2, power),
			GuardBreak = power >= 1,
		}
		if strike(ctx, target, lerp(cfg.DamageMin, cfg.DamageMax, power), opts, true, true) == "Hit" then
			CombatState.Stun(target.Humanoid, cfg.Stun)
			local speed = lerp(cfg.KnockbackMin, cfg.KnockbackMax, power)
			knock(ctx, target, look * speed + Vector3.new(0, 10 + 15 * power, 0), 0.2)
		end
	end
end

-- ================= Skills da Katana =================
-- Hitbox no servidor, nos tempos dos marcadores das animações (campos ...At da skill no CombatStyles). O efeito de
-- quem atacou sai no cliente dele (CombatInput/CombatFX); os outros recebem "KatanaSkill" e seguem os mesmos tempos.

local PING_SLACK = 0.12 -- espera a posição do cliente chegar antes de medir (avanço) ou procurar o alvo (agarrão)

-- Lentidão de uma skill por um tempo. Só a última chamada de cada fonte devolve a velocidade (um golpe cortado no
-- meio não prende o jogador parado).
local speedTokens = {}
local function slowFor(player, source, multiplier, duration)
	local tokens = speedTokens[player]
	if not tokens then
		tokens = {}
		speedTokens[player] = tokens
	end
	local token = (tokens[source] or 0) + 1
	tokens[source] = token
	CombatState.SetSpeed(player, source, multiplier)
	task.delay(duration, function()
		if tokens[source] == token then
			CombatState.SetSpeed(player, source, nil)
		end
	end)
end

local function skillContext(player, slot)
	local ctx = getContext(player)
	if not ctx or CombatState.IsLocked(player) or not CombatState.IsReady(player, slot) then return nil end
	local cfg = ctx.Style.Skills[slot]
	if not cfg or not hasTechnique(player, cfg) then return nil end
	local state = CombatState.Get(player)
	state.actionToken += 1
	StyleWeapons.MarkCombat(ctx.Character, ctx.StyleName)
	return ctx, cfg, state, state.actionToken
end

-- ----- Avanço cortante (Kind "DashSlash") -----
-- Quem anda é o cliente (dono do próprio personagem): sai no DashAt, anda até Distance studs em DashTime e para antes
-- de parede. O servidor guarda de onde ele saiu e, no fim do avanço (+ folga do ping), procura quem está no corredor
-- entre esse ponto e onde ele está agora (no máximo Distance + tolerância). Durante o avanço não leva dano (DodgeUntil).
-- Achou alguém: trava os alvos (stun sem dano), avisa "DashSlashConnect" (o cliente de quem avançou faz a pose do
-- corte) e, no FinishHitAt (marcador da pose), aplica o dano com a chuva de cortes (efeito "Hit" com Cut = "Flurry").

-- Alvos num corredor de from até to, com a largura dada, sem parede entre o caminho e o alvo
local function corridorTargets(ctx, from, to, width)
	local flat = Vector3.new(to.X - from.X, 0, to.Z - from.Z)
	local length = flat.Magnitude
	local direction = if length > 0.05 then flat.Unit else flatLook(ctx.Root)
	local center = (from + to) / 2
	local overlap = CombatRules.TargetOverlap(ctx.Character)
	local rayParams = losParams(ctx.Character)
	local size = Vector3.new(width + 2, 9, length + width)
	local targets, seen = {}, {}
	for _, part in workspace:GetPartBoundsInBox(CFrame.lookAt(center, center + direction), size, overlap) do
		local model = part:FindFirstAncestorOfClass("Model")
		if not model or seen[model] then continue end
		seen[model] = true
		local humanoid = model:FindFirstChildOfClass("Humanoid")
		local root = model:FindFirstChild("HumanoidRootPart")
		if not humanoid or humanoid.Health <= 0 or not root or not root:IsA("BasePart") then continue end
		if not CombatRules.CanDamage(ctx.Player, model) then continue end
		-- Ponto do caminho mais perto do alvo: dali até ele não pode ter parede
		local along = math.clamp((root.Position - from):Dot(direction), 0, length)
		local closest = from + direction * along
		if not workspace:Raycast(closest, root.Position - closest, rayParams) then
			table.insert(targets, { Model = model, Humanoid = humanoid, Root = root })
		end
	end
	return targets
end

local function doDashSlash(player, slot)
	local ctx, cfg, state, token = skillContext(player, slot)
	if not ctx then return end
	local t = now()
	local checkAt = cfg.DashAt + cfg.DashTime + PING_SLACK
	CombatState.SetCooldown(player, slot, cfg.Cooldown)
	CombatState.SetBusy(player, t + cfg.SlashAt + cfg.Recovery)
	slowFor(player, "DashSlash", cfg.SpeedMultiplier, cfg.SlashAt + cfg.Recovery)
	ctx.Character:SetAttribute("DodgeUntil", t + checkAt)
	local start = ctx.Root.Position
	CombatState.FX("KatanaSkill", { Character = ctx.Character, Style = ctx.StyleName, Slot = slot }, player)

	task.delay(checkAt, function()
		if state.actionToken ~= token or not stillValid(ctx) then return end
		local finish = ctx.Root.Position
		-- Caminho maior que o avanço (posição mentida ou empurrão no meio): corta no tamanho do avanço
		local flat = Vector3.new(finish.X - start.X, 0, finish.Z - start.Z)
		local maxLength = cfg.Distance + CombatStyles.HitTolerance * 2
		if flat.Magnitude > maxLength then
			finish = Vector3.new(start.X, finish.Y, start.Z) + flat.Unit * maxLength
		end
		local direction = if flat.Magnitude > 0.05 then flat.Unit else flatLook(ctx.Root)
		CombatState.FX("DashSlashPath", { Character = ctx.Character, Style = ctx.StyleName, From = start, To = finish }, player)
		local targets = corridorTargets(ctx, start, finish, cfg.Width)
		if #targets == 0 then return end

		-- Pegou: quem ficou no caminho trava (quem estava de guarda não; ele decide no corte, pela guarda)
		local hitAt = cfg.FinishHitAt or 0.2
		local models = {}
		for _, target in targets do
			table.insert(models, target.Model)
			if target.Model:GetAttribute("Blocking") ~= true then
				CombatState.Stun(target.Humanoid, hitAt + 0.35)
			end
		end
		CombatState.SetBusy(player, now() + hitAt + (cfg.FinishHold or 0) + 0.1)
		slowFor(player, "DashSlash", 0, hitAt + (cfg.FinishHold or 0))
		CombatState.FX("DashSlashConnect", { Character = ctx.Character, Style = ctx.StyleName, Targets = models })

		-- Os cortes saem no marcador da pose (o corte já aconteceu: vale mesmo se ele for atordoado nesse meio tempo)
		task.delay(hitAt + 0.03, function()
			if ctx.Player.Character ~= ctx.Character then return end
			for _, target in targets do
				if target.Humanoid.Health <= 0 or not target.Model.Parent then continue end
				local opts = {
					ScaleWithForca = true,
					ForcaScale = cfg.ForcaScale,
					GuardDamage = cfg.GuardDamage,
					FromPosition = start, -- o corte veio de onde ele saiu (termina atrás da vítima)
					HitFX = { Cut = "Flurry" },
				}
				if strike(ctx, target, cfg.Damage, opts, true, false) == "Hit" then
					CombatState.Stun(target.Humanoid, cfg.Stun)
					knock(ctx, target, direction * cfg.Knockback + Vector3.new(0, cfg.KnockbackUp, 0), 0.2)
				end
			end
		end)
	end)
end

-- ----- Agarrão (Kind "Grab") -----
-- No GrabAt pega o alvo mais perto na frente (atravessa a guarda; esquiva ainda vale). Pegou: a vítima fica presa na
-- frente (AlignPosition/AlignOrientation até a raiz de quem agarrou; a física do jogador é do cliente dele, que segue
-- as restrições), leva o corte do StrikeAt e é arremessada no ReleaseAt. Errou: recarga menor (WhiffCooldown).
-- Chefes (atributo Boss) levam os cortes sem ser presos nem arremessados.

local function grabTarget(ctx, cfg)
	local best, bestDistance
	for _, target in findTargets(ctx, cfg.Range, 0.3) do
		local distance = (target.Root.Position - ctx.Root.Position).Magnitude
		if not bestDistance or distance < bestDistance then
			best, bestDistance = target, distance
		end
	end
	return best
end

-- Prende a vítima na frente de quem agarrou. Devolve a função que solta.
local function holdVictim(ctx, target, distance, duration)
	local root = target.Root
	local victimAttachment = Instance.new("Attachment")
	victimAttachment.Name = "KatanaGrabbed"
	victimAttachment.Parent = root
	local holdPoint = Instance.new("Attachment")
	holdPoint.Name = "KatanaGrabPoint"
	holdPoint.CFrame = CFrame.new(0, 0, -distance) * CFrame.Angles(0, math.pi, 0) -- virada para quem agarrou
	holdPoint.Parent = ctx.Root
	local align = Instance.new("AlignPosition")
	align.Name = "KatanaGrab"
	align.Attachment0 = victimAttachment
	align.Attachment1 = holdPoint
	align.MaxForce = 1e6
	align.Responsiveness = 80
	align.Parent = root
	local orient = Instance.new("AlignOrientation")
	orient.Name = "KatanaGrab"
	orient.Attachment0 = victimAttachment
	orient.Attachment1 = holdPoint
	orient.MaxTorque = 1e6
	orient.Responsiveness = 60
	orient.Parent = root
	-- A IA do inimigo vira o corpo com o AlignOrientation "EnemyFacing": fica desligado enquanto segura
	local facing, facingWas
	for _, child in root:GetChildren() do
		if child.Name == "EnemyFacing" and child:IsA("AlignOrientation") then
			facing, facingWas = child, child.Enabled
			child.Enabled = false
		end
	end
	local parts = { victimAttachment, holdPoint, align, orient }
	for _, instance in parts do
		Debris:AddItem(instance, duration + 1)
	end
	local released = false
	return function()
		if released then return end
		released = true
		for _, instance in parts do
			instance:Destroy()
		end
		if facing and facing.Parent then
			facing.Enabled = facingWas
		end
	end
end

local function doGrab(player, slot)
	local ctx, cfg, state, token = skillContext(player, slot)
	if not ctx then return end
	local t = now()
	CombatState.SetCooldown(player, slot, cfg.WhiffCooldown)
	CombatState.SetBusy(player, t + cfg.GrabAt + 0.3)
	slowFor(player, "Grab", cfg.SpeedMultiplier, cfg.GrabAt + 0.3)
	CombatState.FX("KatanaSkill", { Character = ctx.Character, Style = ctx.StyleName, Slot = slot }, player)

	task.delay(cfg.GrabAt + PING_SLACK * 0.5, function()
		if state.actionToken ~= token or not stillValid(ctx) then return end
		local target = grabTarget(ctx, cfg)
		local grabbed = target and strike(ctx, target, cfg.GrabDamage, {
			ScaleWithForca = true,
			ForcaScale = cfg.ForcaScale,
			Unblockable = true,
			Unparryable = true,
			NoHitReaction = true,
		}, false, false) == "Hit"
		if not grabbed then
			CombatState.FX("KatanaGrabMiss", { Character = ctx.Character })
			return
		end

		local holdTime = cfg.ReleaseAt - cfg.GrabAt
		local canHold = target.Model:GetAttribute("Boss") ~= true
		CombatState.SetCooldown(player, slot, cfg.Cooldown)
		CombatState.SetBusy(player, now() + holdTime + 0.3)
		slowFor(player, "Grab", 0, holdTime + 0.3)
		local release = function() end
		if canHold then
			CombatState.Stun(target.Humanoid, holdTime + 0.25)
			release = holdVictim(ctx, target, cfg.HoldDistance, holdTime)
			local track = playHit(target.Humanoid, CombatStyles.Animation(ctx.Style, cfg.TargetAnimation))
			if track then
				pcall(function()
					track.TimePosition = cfg.GrabAt -- a animação da vítima tem o mesmo relógio da de quem agarrou
				end)
			end
		end
		CombatState.FX("KatanaGrab", { Character = ctx.Character, Target = target.Model, Style = ctx.StyleName })

		-- Continua valendo? (quem agarrou não foi interrompido e os dois estão vivos)
		local function holding()
			return state.actionToken == token and ctx.Player.Character == ctx.Character and ctx.Humanoid.Health > 0
				and target.Humanoid.Health > 0 and target.Model.Parent ~= nil
		end

		task.delay(cfg.StrikeAt - cfg.GrabAt, function()
			if not holding() then
				release()
				CombatState.FX("KatanaGrabMiss", { Character = ctx.Character })
				return
			end
			local opts = { ScaleWithForca = true, ForcaScale = cfg.ForcaScale, Unblockable = true, Unparryable = true,
				NoHitReaction = canHold, HitFX = { Cut = "Single" } }
			if strike(ctx, target, cfg.StrikeDamage, opts, false, false) == "Hit" and canHold then
				CombatState.Stun(target.Humanoid, cfg.ReleaseAt - cfg.StrikeAt + 0.25)
			end
			CombatState.FX("KatanaGrabStrike", { Character = ctx.Character, Target = target.Model, Style = ctx.StyleName })
		end)

		task.delay(holdTime, function()
			release()
			if not holding() then
				CombatState.FX("KatanaGrabMiss", { Character = ctx.Character })
				return
			end
			CombatState.FX("KatanaGrabRelease", { Character = ctx.Character, Target = target.Model, Style = ctx.StyleName })
			local opts = { ScaleWithForca = true, ForcaScale = cfg.ForcaScale, Unblockable = true, Unparryable = true,
				HitFX = { Cut = "Cross" } }
			if strike(ctx, target, cfg.FinalDamage, opts, true, false) == "Hit" then
				CombatState.Stun(target.Humanoid, cfg.FinalStun)
				if canHold then
					knock(ctx, target, flatLook(ctx.Root) * cfg.FinalKnockback + Vector3.new(0, cfg.FinalKnockbackUp, 0), 0.2)
				end
			end
		end)
	end)
end

-- ----- Saque (Kind "DrawSlash") -----
-- A lâmina volta para a bainha (na mão esquerda) no aperto e sai no corte (SlashAt): arco largo na frente, quebra a
-- guarda. No SheatheAt a lâmina volta para a bainha, se ele não atacou de novo (StyleWeapons).

local function doDrawSlash(player, slot)
	local ctx, cfg, state, token = skillContext(player, slot)
	if not ctx then return end
	local t = now()
	local pressed = os.clock()
	CombatState.SetCooldown(player, slot, cfg.Cooldown)
	CombatState.SetBusy(player, t + cfg.SlashAt + cfg.Recovery)
	slowFor(player, "DrawSlash", cfg.SpeedMultiplier, cfg.SlashAt + cfg.Recovery)
	if cfg.DrawFromSheath then
		StyleWeapons.SetDrawn(ctx.Character, ctx.StyleName, false)
	end
	if cfg.SheatheAt then
		task.delay(cfg.SheatheAt, function()
			if state.actionToken == token then
				StyleWeapons.Sheathe(ctx.Character, ctx.StyleName, pressed)
			end
		end)
	end
	CombatState.FX("KatanaSkill", { Character = ctx.Character, Style = ctx.StyleName, Slot = slot }, player)

	task.delay(cfg.SlashAt, function()
		if cfg.DrawFromSheath then
			StyleWeapons.SetDrawn(ctx.Character, ctx.StyleName, nil) -- saca (mesmo se o golpe foi cortado)
		end
		if state.actionToken ~= token or not stillValid(ctx) then return end
		local look = flatLook(ctx.Root)
		for _, target in findTargets(ctx, cfg.Range, math.cos(math.rad(cfg.Arc / 2))) do
			local opts = {
				ScaleWithForca = true,
				ForcaScale = cfg.ForcaScale,
				GuardBreak = cfg.GuardBreak,
				HitFX = { Cut = "Wide" },
			}
			if strike(ctx, target, cfg.Damage, opts, true, false) == "Hit" then
				CombatState.Stun(target.Humanoid, cfg.Stun)
				knock(ctx, target, look * cfg.Knockback + Vector3.new(0, cfg.KnockbackUp, 0), 0.2)
			end
		end
	end)
end

-- ----- Kon! (Kind "FoxSnap", estilo fundido com a Raposa; ContractData) -----
-- Dois acertos: no ClawAt uma garrada (ClawArc graus, ClawRange studs, ClawDamage); no SnapAt uma cabeça menor do Kon
-- sai de um portal na frente e abocanha (Arc graus, Range studs, Damage). Quem leva a mordida é atordoado e puxado na
-- direção de quem invocou (emenda o próximo combo). O efeito é do cliente (CombatFX "FoxSnap": garras + a mesma
-- cabeça do FoxDevilVFX, menor).

local function doFoxSnap(player, slot)
	local ctx, cfg, state, token = skillContext(player, slot)
	if not ctx then return end
	local t = now()
	CombatState.SetCooldown(player, slot, cfg.Cooldown)
	CombatState.SetBusy(player, t + cfg.SnapAt + cfg.Recovery)
	slowFor(player, "FoxSnap", cfg.SpeedMultiplier, cfg.SnapAt + cfg.Recovery)
	local look = flatLook(ctx.Root)
	CombatState.FX("FoxSnap", {
		Character = ctx.Character, Style = ctx.StyleName, Slot = slot, Look = look, StartTime = t,
	}, player)

	if cfg.ClawAt then
		task.delay(cfg.ClawAt, function()
			if state.actionToken ~= token or not stillValid(ctx) then return end
			for _, target in findTargets(ctx, cfg.ClawRange or cfg.Range, math.cos(math.rad((cfg.ClawArc or cfg.Arc) / 2))) do
				local opts = { ScaleWithForca = true, ForcaScale = cfg.ForcaScale * 0.5, GuardDamage = cfg.GuardDamage * 0.5 }
				if strike(ctx, target, cfg.ClawDamage or 0, opts, false, false) == "Hit" then
					CombatState.Stun(target.Humanoid, cfg.SnapAt - cfg.ClawAt + 0.2) -- segura até a mordida
				end
			end
		end)
	end

	task.delay(cfg.SnapAt, function()
		if state.actionToken ~= token or not stillValid(ctx) then return end
		for _, target in findTargets(ctx, cfg.Range, math.cos(math.rad(cfg.Arc / 2))) do
			local opts = { ScaleWithForca = true, ForcaScale = cfg.ForcaScale, GuardDamage = cfg.GuardDamage }
			if strike(ctx, target, cfg.Damage, opts, true, false) == "Hit" then
				CombatState.Stun(target.Humanoid, cfg.Stun)
				local toward = ctx.Root.Position - target.Root.Position
				local flat = Vector3.new(toward.X, 0, toward.Z)
				-- Puxa até perto (para a uns 3 studs na frente de quem invocou)
				local pull = math.clamp(flat.Magnitude - 3, 0, cfg.Range) / math.max(cfg.Pull, 1)
				if flat.Magnitude > 3.5 and pull > 0.02 then
					knock(ctx, target, flat.Unit * cfg.Pull + Vector3.new(0, 6, 0), pull)
				end
			end
		end
	end)
end

-- ================= Acerto mandado pelo cliente =================

local function onHit(player, seq, targets, impactTime, originFrame)
	local list = pending[player]
	local record = isSeq(seq) and list and list[seq]
	if not record then return end
	list[seq] = nil -- cada golpe acerta uma vez só
	if now() - record.Time > CombatStyles.HitDeadline then return end
	local ctx = record.Ctx
	if not stillValid(ctx) then return end -- levou parry/stun no meio do golpe
	local rewindTime, sentAt = CombatRewind.ResolveTime(player, impactTime, now())
	if not rewindTime or sentAt < record.Time - CombatNetConfig.RewindWindow then return end
	local origin = CombatRewind.Origin(ctx.Character, sentAt, originFrame)
	if not origin then return end
	record.RewindTime, record.HitOrigin = rewindTime, origin
	-- Lista vazia: o golpe pegou no ar (o cliente só manda isso com SwingOnMiss): os outros tocam o som do golpe no ar
	if type(targets) == "table" and next(targets) == nil then
		CombatState.FX("Miss", { Character = ctx.Character, Style = ctx.StyleName }, player)
		return
	end
	if record.Kind == "ChargedPunch" then
		resolveChargedPunch(ctx, record, targets)
	else
		resolveM1(ctx, record, targets)
	end
end

-- ================= Cancelamentos =================

-- Atordoado, trocou de arma ou morreu: larga a guarda, perde a carga, para a rajada e os golpes pendentes
local function cancelActions(player)
	local state = CombatState.Get(player)
	state.actionToken += 1
	CombatState.StopBlock(player)
	pending[player] = nil
	local charging = state.charging
	if charging then
		cancelCharge(player, state, charging)
	end
end

CombatState.OnInterrupt(cancelActions)

local function onCharacter(player, character)
	character.ChildRemoved:Connect(function(child)
		if child:IsA("Tool") and CombatStyles.Styles[child.Name] and player.Character == character then
			cancelActions(player)
		end
	end)
end

local function onPlayer(player)
	player.CharacterAdded:Connect(function(character)
		pending[player] = nil
		onCharacter(player, character)
	end)
	if player.Character then
		onCharacter(player, player.Character)
	end
end

Players.PlayerAdded:Connect(onPlayer)
for _, player in Players:GetPlayers() do
	onPlayer(player)
end
Players.PlayerRemoving:Connect(function(player)
	pending[player] = nil
	speedTokens[player] = nil
end)

-- ================= Remotes =================

Remotes.CombatM1.OnServerEvent:Connect(onM1)

Remotes.CombatHit.OnServerEvent:Connect(onHit)

-- Mecânica de cada tipo de skill (campo Kind da skill no CombatStyles), chamada com (player, slot, holding, seq)
local SkillKinds = {}

function SkillKinds.Barrage(player, slot, holding)
	if holding ~= false then
		doBarrage(player, slot)
	end
end

function SkillKinds.Charge(player, slot, holding, seq)
	if holding == false then
		releaseCharge(player, seq)
	else
		startCharge(player, slot)
	end
end

function SkillKinds.DashSlash(player, slot, holding)
	if holding ~= false then
		doDashSlash(player, slot)
	end
end

function SkillKinds.Grab(player, slot, holding)
	if holding ~= false then
		doGrab(player, slot)
	end
end

function SkillKinds.DrawSlash(player, slot, holding)
	if holding ~= false then
		doDrawSlash(player, slot)
	end
end

function SkillKinds.FoxSnap(player, slot, holding)
	if holding ~= false then
		doFoxSnap(player, slot)
	end
end

Remotes.CombatSkill.OnServerEvent:Connect(function(player, slot, holding, seq)
	if type(slot) ~= "string" then return end
	local _, style = CombatStyles.FromCharacter(player.Character)
	local cfg = style and style.Skills[slot]
	local handler = cfg and SkillKinds[cfg.Kind]
	if handler then
		handler(player, slot, holding, seq)
	end
end)

Remotes.CombatBlock.OnServerEvent:Connect(function(player, holding)
	if type(holding) ~= "boolean" then return end
	if holding then
		local ctx = getContext(player)
		if ctx and CombatState.StartBlock(player, ctx.Style.Block, ctx.StyleName) then
			StyleWeapons.MarkCombat(ctx.Character, ctx.StyleName)
		end
	else
		CombatState.StopBlock(player)
	end
end)
