-- Entrada do combate: clique (M1; segurar repete o combo), F (bloquear, segurando) e as skills do estilo em Z/X/C
-- (Punhos: Rajada e Soco carregado, segure e solte; Katana: Avanço cortante, Agarrão e Saque). Só funciona com um
-- estilo equipado (CombatStyles).
--
-- Cliente prevê, servidor valida (ver CombatService):
--   - A animação, o efeito e o som do golpe saem na hora do clique (sem esperar o servidor).
--   - No frame do impacto (marcador "Hit" da animação, ou o Windup se não tiver animação) a hitbox roda aqui
--     (GetPartBoundsInBox) e manda quem pegou; o servidor confere alcance, cooldown e estado.
--   - O acerto já mostra hitstop, tremida, faísca e som aqui; os outros jogadores veem pelo servidor.
--   - Clique no meio de um golpe fica guardado (input buffer) e sai sozinho quando der.
--   - Depois da janela de cancelamento do M1, skill, block e dash cortam o resto do golpe.
--   - Empurrões no próprio personagem chegam pelo Remotes.CombatImpulse e são aplicados aqui (sem tremer).
-- A HUD (toque no celular) usa o BindableEvent "CombatAction": ("Block", segurando), ("Skill", slot, segurando) ou
-- ("Attack", segurando): o botão de ataque do celular, igual a segurar o clique.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ProximityPromptService = game:GetService("ProximityPromptService")
local Debris = game:GetService("Debris")

local Remotes = require(ReplicatedStorage:WaitForChild("Remotes"))
local CombatStyles = require(ReplicatedStorage:WaitForChild("CombatStyles"))
local CombatAnimations = require(script.Parent:WaitForChild("CombatAnimations"))

local player = Players.LocalPlayer

local MARKER_TIMEOUT = 0.45 -- animação sem o marcador de impacto: a hitbox sai nesse tempo (e avisa no Output)
-- Primeira vez que uma animação toca: ela ainda está carregando (Length 0) e não anda. O prazo do marcador só começa
-- depois que ela carrega, esperando no máximo isso (o servidor aceita o acerto até CombatStyles.HitDeadline).
local LOAD_TIMEOUT = 0.6
-- Limite de relógio esperando o marcador numa animação carregada (menor que o HitDeadline do servidor, 1,5 s)
local MAX_IMPACT_WAIT = 1.2
local HITBOX_WIDTH, HITBOX_HEIGHT = 5.5, 6
local MAX_TARGETS = 8

local seq = 0 -- número de cada golpe mandado ao servidor
local m1Held = false
local bufferedUntil = 0 -- clique guardado
local m1RequestAfter = 0 -- próximo M1 (os.clock)
local localLockUntil = 0 -- skills e block (os.clock), antes do servidor confirmar
local predictedCombo, lastM1 = 0, 0 -- mesma conta do servidor, para a animação do golpe sair na hora
local blockHeld = false
local lastBlockRequest = 0
local chargeSlot -- skill de segurar apertada agora
local chargeStartedAt -- os.clock em que a carga começou (servidor confirmou)
local impactPending -- golpe esperando o frame do impacto: o próximo M1 espera ele (o clique fica guardado)
local pending -- skill apertada durante outro golpe: tenta de novo por um instante { Slot, Expires }
local warnedMarkers = {}

local function now()
	return workspace:GetServerTimeNow()
end

local function lerp(a, b, t)
	return a + (b - a) * t
end

local function getHumanoid()
	local character = player.Character
	return character and character:FindFirstChildOfClass("Humanoid")
end

local function getRoot()
	local character = player.Character
	return character and character:FindFirstChild("HumanoidRootPart")
end

-- Vivo, não atordoado e com um estilo equipado
local function canAct()
	local character = player.Character
	local humanoid = getHumanoid()
	return humanoid ~= nil and humanoid.Health > 0 and character:GetAttribute("Stunned") ~= true
		and CombatStyles.FromCharacter(character) ~= nil
end

-- Guarda levantada ou soco carregando: nenhum outro golpe sai
local function inStance()
	local character = player.Character
	return character ~= nil and (character:GetAttribute("Blocking") == true or character:GetAttribute("Charging") == true)
end

-- Próximo M1 ainda não pode (golpe em andamento)
local function busy()
	return os.clock() < m1RequestAfter or now() < (player:GetAttribute("CombatBusyUntil") or 0)
end

-- Skill e block ainda não podem (antes da janela de cancelamento do M1, ou durante uma skill)
local function locked()
	return os.clock() < localLockUntil or now() < (player:GetAttribute("CombatLockUntil") or 0)
end

-- Efeito previsto: o CombatFX trata igual ao que vem do servidor
local function localFX(kind, data)
	local event = script.Parent:FindFirstChild("CombatLocalFX")
	if event then
		event:Fire(kind, data)
	end
end

-- ================= Empurrão no próprio personagem =================

local function applyImpulse(velocity, duration)
	local root = getRoot()
	if not root then return end
	for _, child in root:GetChildren() do
		if child.Name == "CombatImpulse" then
			child:Destroy()
		end
	end
	local attachment = Instance.new("Attachment")
	attachment.Name = "CombatImpulse"
	attachment.Parent = root
	local mover = Instance.new("LinearVelocity")
	mover.Name = "CombatImpulse"
	mover.Attachment0 = attachment
	mover.RelativeTo = Enum.ActuatorRelativeTo.World
	mover.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
	mover.MaxForce = 1e6
	mover.VectorVelocity = velocity
	mover.Parent = root
	Debris:AddItem(mover, duration)
	Debris:AddItem(attachment, duration)
end

Remotes.CombatImpulse.OnClientEvent:Connect(function(velocity, duration)
	if typeof(velocity) == "Vector3" and type(duration) == "number" then
		applyImpulse(velocity, math.clamp(duration, 0, 1))
	end
end)

-- ================= Hitbox do cliente =================

-- Mesmas regras do CombatRules.CanDamage (o servidor confere de novo): jogador ou inimigo, vivo, sem ForceField,
-- e sem acertar aliado quando um dos dois ligou a proteção
local function canHit(model)
	if model == player.Character or model:FindFirstChildOfClass("ForceField") then return false end
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 or not model:FindFirstChild("HumanoidRootPart") then return false end
	local other = Players:GetPlayerFromCharacter(model)
	if other then
		if workspace:GetAttribute("PvPDisabled") == true then return false end -- servidor VIP sem PvP
		if player.Team ~= nil and other.Team == player.Team
			and (player:GetAttribute("AllyProtection") ~= false or other:GetAttribute("AllyProtection") ~= false) then
			return false
		end
		return true
	end
	-- Cópia do Treinador de outro jogador (TrainerService): só o dono do treino acerta
	local trainingFor = model:GetAttribute("TrainingFor")
	if trainingFor ~= nil and trainingFor ~= player.UserId then return false end
	local enemies = workspace:FindFirstChild("Enemies")
	return enemies ~= nil and model:IsDescendantOf(enemies) and model:GetAttribute("Enemy") == true
end

-- Caixa na frente do personagem, do tamanho do alcance do golpe (width: largura, padrão HITBOX_WIDTH)
local function detectTargets(range, width)
	local character = player.Character
	local root = getRoot()
	if not root then return {} end
	-- Só quem pode levar dano: inimigos e os outros jogadores (sem passar pelas peças do mapa)
	local include = {}
	local enemies = workspace:FindFirstChild("Enemies")
	if enemies then
		table.insert(include, enemies)
	end
	for _, other in Players:GetPlayers() do
		if other.Character and other.Character ~= character then
			table.insert(include, other.Character)
		end
	end
	local overlap = OverlapParams.new()
	overlap.FilterType = Enum.RaycastFilterType.Include
	overlap.FilterDescendantsInstances = include
	local length = range + 1
	local boxCFrame = root.CFrame * CFrame.new(0, 0, -length / 2)
	local found, seen = {}, {}
	local size = Vector3.new(width or HITBOX_WIDTH, HITBOX_HEIGHT, length)
	for _, part in workspace:GetPartBoundsInBox(boxCFrame, size, overlap) do
		local model = part:FindFirstAncestorOfClass("Model")
		if model and not seen[model] then
			seen[model] = true
			if canHit(model) then
				table.insert(found, model)
				if #found >= MAX_TARGETS then break end
			end
		end
	end
	return found
end

-- A vítima está com a guarda levantada virada para mim? (só para escolher o efeito previsto)
local function guardsAgainstMe(model)
	if model:GetAttribute("Blocking") ~= true then return false end
	local victimRoot = model:FindFirstChild("HumanoidRootPart")
	local root = getRoot()
	if not victimRoot or not root then return false end
	local offset = root.Position - victimRoot.Position
	local flat = Vector3.new(offset.X, 0, offset.Z)
	if flat.Magnitude < 0.01 then return true end
	local look = victimRoot.CFrame.LookVector
	return Vector3.new(look.X, 0, look.Z).Unit:Dot(flat.Unit) >= -0.1
end

-- Espera o frame do impacto. Devolve false se o golpe foi cortado antes (dash, skill, stun).
local function warnOnce(key, message)
	if not warnedMarkers[key] then
		warnedMarkers[key] = true
		warn(message)
	end
end

-- markerNames: um nome ou uma lista (CombatStyles.MarkerNames). timeout: prazo fixo em segundos de relógio.
-- Sem timeout, com a animação carregada, o limite é o TEMPO DA ANIMAÇÃO: sem o marcador, acerta em 70% dela. Assim
-- a pausa do hitstop (um inimigo acertando no meio do soco) ou uma travada de frame atrasam o marcador e o limite
-- juntos; antes o limite era de relógio, com só 65-90 ms de folga, e estourava à toa (hitbox fora da hora e aviso).
-- MAX_IMPACT_WAIT só evita esperar para sempre uma animação parada.
-- impactAt (opcional): tempo da animação em que o golpe acerta (ex.: o soco no ponto mais longe), no lugar do marcador.
-- É tempo da animação, então segue a pausa do hitstop.
local function waitForImpact(track, markerNames, timeout, windup, attackId, impactAt)
	local start = os.clock()
	if track then
		local reached = false
		local connections = CombatStyles.OnMarker(track, markerNames, function()
			reached = true
		end)
		local loadDeadline = start + LOAD_TIMEOUT
		while track.Length <= 0 and os.clock() < loadDeadline and track.IsPlaying and CombatAnimations.AttackId() == attackId do
			task.wait()
		end
		local loaded = track.Length > 0
		if impactAt and not loaded then
			impactAt = nil -- sem a animação carregada, vale o windup
		end
		-- Sem marcador, acerta em 90% da animação (antes era 70%: o M5 da raposa tem o marcador em 75% e saía antes dele)
		local fallbackPosition = if not timeout and not impactAt and loaded then track.Length * 0.9 else nil
		local deadline = os.clock() + (if fallbackPosition or impactAt then MAX_IMPACT_WAIT else timeout or MARKER_TIMEOUT)
		local late = false -- a animação passou dos 90% sem o marcador
		while not reached and track.IsPlaying and CombatAnimations.AttackId() == attackId do
			if impactAt and track.TimePosition >= impactAt then
				reached = true
				break
			end
			if fallbackPosition and track.TimePosition >= fallbackPosition then
				late = true
				break
			end
			if os.clock() >= deadline then
				late = timeout ~= nil and loaded
				break
			end
			task.wait()
		end
		for _, connection in connections do
			connection:Disconnect()
		end
		if not reached and CombatAnimations.AttackId() == attackId then
			local id = track.Animation and track.Animation.AnimationId or "?"
			if late and track.IsPlaying then
				local names = table.concat(CombatStyles.MarkerNames(markerNames), '" ou "')
				warnOnce(id, `[Combate] A animação {id} não tem o evento "{names}": a hitbox saiu em 90% da animação. `
					.. `Coloque um Animation Event "{CombatStyles.MarkerNames(markerNames)[1]}" no frame do impacto.`)
			elseif os.clock() - start < 0.1 then
				warnOnce(id .. "play", `[Combate] A animação {id} não tocou. Ela precisa ser R6 e estar publicada `
					.. `na mesma conta ou grupo dono do jogo.`)
			end
			-- Sem marcador (ou a animação não tocou): acerta pelo menos depois do windup
			local left = windup - (os.clock() - start)
			if left > 0 then
				task.wait(left)
			end
		end
	else
		task.wait(windup)
	end
	return CombatAnimations.AttackId() == attackId and canAct()
end

-- Golpe com impacto único (M1, uppercut, soco carregado): espera o impacto, acha os alvos e avisa o servidor.
-- track: a animação do golpe já tocando (ou nil sem animação). opts: Windup, Range, Heavy, Marker, Timeout.
local function performAttack(attackSeq, styleName, style, move, combo, track, opts)
	local attackId = CombatAnimations.AttackId()
	if move ~= "ChargedPunch" then -- o soco carregado tem o efeito próprio (releaseCharge)
		localFX("Swing", { Character = player.Character, Style = styleName, Move = move, Combo = combo })
	end
	local range, heavy = opts.Range, opts.Heavy

	local marker = {}
	impactPending = marker
	task.spawn(function()
		-- Termina no impacto ou quando o golpe é cortado (dash, skill, stun): nos dois casos libera o próximo
		local impacted = waitForImpact(track, opts.Marker or style.HitMarker or "Hit", opts.Timeout, opts.Windup, attackId, opts.ImpactAt)
		if impactPending == marker then
			impactPending = nil
		end
		if not impacted then return end
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		if not root then return end
		local impactTime, originFrame = now(), root.CFrame
		local targets = detectTargets(range, opts.Width)
		if #targets == 0 then
			-- Pegou no ar: estilo com som só de golpe no ar (SwingOnMiss) avisa o servidor, que conta para os outros
			if style.SwingOnMiss then
				Remotes.CombatHit:FireServer(attackSeq, {}, impactTime, originFrame)
				localFX("Miss", { Character = player.Character, Style = styleName })
			end
			return
		end
		Remotes.CombatHit:FireServer(attackSeq, targets, impactTime, originFrame)

		-- Acerto previsto: hitstop, tremida, faísca e som já aqui
		for _, model in targets do
			localFX(if guardsAgainstMe(model) then "Blocked" else "Hit", {
				Character = model,
				Attacker = player.Character,
				Strong = heavy,
				Style = styleName,
			})
		end
		-- Uppercut: sobe junto para continuar o combo no ar
		if move == "Uppercut" then
			applyImpulse(Vector3.new(0, style.M1.Uppercut.Launch * 0.9, 0), 0.15)
		end
	end)
end

-- ================= M1 =================

local function isAirborne()
	local humanoid = getHumanoid()
	if not humanoid then return false end
	local state = humanoid:GetState()
	return humanoid.FloorMaterial == Enum.Material.Air
		or state == Enum.HumanoidStateType.Jumping
		or state == Enum.HumanoidStateType.Freefall
end

-- Técnica do golpe liberada na árvore de habilidades? (atributo Tech_<Técnica> que o servidor escreve)
local function hasTech(cfg)
	return not (cfg and cfg.Technique) or player:GetAttribute("Tech_" .. cfg.Technique) == true
end

-- Devolve true se o golpe saiu
local function tryM1()
	if not canAct() or inStance() or busy() or impactPending ~= nil then return false end
	local styleName, style = CombatStyles.FromCharacter(player.Character)
	local cfg = style.M1
	local aerial = isAirborne()
	local t = os.clock()
	local hits = cfg.Hits or 5 -- golpes do combo (o último arremessa)
	predictedCombo = if t - lastM1 > cfg.ComboReset or predictedCombo >= hits then 1 else predictedCombo + 1
	lastM1 = t
	-- Interval: um tempo só ou um por golpe (o fim de cada animação, ex.: Punhos da Raposa)
	local interval = if type(cfg.Interval) == "table" then cfg.Interval[predictedCombo] or cfg.Interval[#cfg.Interval] else cfg.Interval
	local recovery = if predictedCombo == hits then cfg.EndLag else interval
	-- Um pouco mais que o servidor (ping): o próximo pedido nunca chega antes da hora
	m1RequestAfter = t + recovery + 0.03
	localLockUntil = t + math.min(cfg.CancelWindow, recovery)
	player:SetAttribute("PredictedCombatLockUntil", now() + math.min(cfg.CancelWindow, recovery))

	seq += 1
	Remotes.CombatM1:FireServer(seq, aerial)
	-- Estilo sem uppercut (Uppercut = false, ex.: Punhos da Raposa): o 4º golpe no ar é um M1 comum
	local uppercut = predictedCombo == 4 and aerial and type(cfg.Uppercut) == "table" and hasTech(cfg.Uppercut)
	local move = if uppercut then "Uppercut" else "M1"
	local track = CombatAnimations.PlayAttack(style, move, predictedCombo)
	-- ImpactMarkers (opcional): o marcador de cada golpe (combo numa animação só: "M1", "M2"...). ImpactTime (opcional): o
	-- tempo do impacto de cada golpe na animação; com marcador, vira só a garantia (um pouco depois dele)
	local impactMarker = if move == "M1" and type(cfg.ImpactMarkers) == "table" then cfg.ImpactMarkers[predictedCombo] else nil
	local impactAt = if move ~= "M1" then nil
		elseif type(cfg.ImpactTime) == "table" then cfg.ImpactTime[predictedCombo]
		else cfg.ImpactTime
	if impactAt and impactMarker then
		impactAt += 0.15
	end
	performAttack(seq, styleName, style, move, predictedCombo, track, {
		Windup = cfg.Windup,
		Range = cfg.Range,
		Heavy = uppercut or predictedCombo == hits,
		Width = cfg.HitboxWidth,
		Marker = impactMarker,
		ImpactAt = impactAt,
	})
	return true
end

-- ================= Bloqueio =================

local function setBlock(holding)
	if holding == blockHeld then return end
	blockHeld = holding
	if holding then
		lastBlockRequest = 0 -- o loop manda na hora (e de novo se o servidor ainda não deixou)
	else
		Remotes.CombatBlock:FireServer(false)
	end
end

-- ================= Skills =================

-- Avanço cortante (Katana): quem anda é este cliente (dono do personagem), reto para a frente, parando antes de parede.
-- Personagens e inimigos não param o avanço (ele passa cortando). O servidor mede o caminho no corte.
local DASH_BOX = Vector3.new(1.8, 3.9, 0.6) -- mesma caixa do dash comum (StaminaDashRunscript)
local dashParams = RaycastParams.new()
dashParams.FilterType = Enum.RaycastFilterType.Exclude
dashParams.RespectCanCollide = true

local function dashForward(cfg, styleName, attackId)
	local character = player.Character
	local root = getRoot()
	if not root or not canAct() or CombatAnimations.AttackId() ~= attackId then return end
	local look = root.CFrame.LookVector
	local direction = Vector3.new(look.X, 0, look.Z)
	direction = if direction.Magnitude > 0.01 then direction.Unit else Vector3.new(0, 0, -1)
	local ignore = { character }
	for _, name in { "Enemies", "CombatFX", "KatanaVisuals", "PowerEffects" } do
		local folder = workspace:FindFirstChild(name)
		if folder then
			table.insert(ignore, folder)
		end
	end
	for _, other in Players:GetPlayers() do
		if other.Character then
			table.insert(ignore, other.Character)
		end
	end
	dashParams.FilterDescendantsInstances = ignore
	dashParams.CollisionGroup = root.CollisionGroup
	local center = root.Position - Vector3.new(0, 0.45, 0)
	local hit = workspace:Blockcast(CFrame.lookAt(center, center + direction), DASH_BOX, direction * cfg.Distance, dashParams)
	local distance = if hit and hit.Normal.Y < 0.6 then math.max(0, hit.Distance - 0.5) else cfg.Distance
	local start = root.Position
	-- Move o personagem direto (CFrame a cada frame), rápido a ponto de parecer um teleporte: sem física, não passa do
	-- ponto nem escorrega. O rastro e os fantasmas no caminho (DashSlashPath) mostram por onde ele passou.
	local startFrame = root.CFrame
	local goal = startFrame + direction * distance
	local began = os.clock()
	local connection
	connection = RunService.Heartbeat:Connect(function()
		local alpha = math.min(1, (os.clock() - began) / math.max(cfg.DashTime, 0.01))
		if not root.Parent then
			connection:Disconnect()
			return
		end
		root.CFrame = startFrame:Lerp(goal, alpha)
		root.AssemblyLinearVelocity = Vector3.zero
		if alpha >= 1 then
			connection:Disconnect()
			localFX("DashSlashPath", { Character = character, Style = styleName, From = start, To = root.Position })
		end
	end)
end

local ROOT_PREDICT = 0.4 -- skill ou poder: parado no cliente até o CombatSpeed do servidor chegar (StaminaDashRunscript)

local function trySkill(slot)
	if not canAct() or inStance() or locked() then return false end
	if now() < (player:GetAttribute(`Combat{slot}ReadyAt`) or 0) then return false end
	local _, style = CombatStyles.FromCharacter(player.Character)
	local cfg = style and style.Skills[slot]
	if cfg and not hasTech(cfg) then
		-- Técnica travada na árvore: sem animação; o servidor recusa e avisa o que falta
		Remotes.CombatSkill:FireServer(slot, true)
		return true
	end
	CombatAnimations.CancelAttack() -- a skill corta o fim do M1
	Remotes.CombatSkill:FireServer(slot, true)
	-- Parado já na hora (o servidor trava pelo CombatSpeed, que chega com o atraso do ping)
	player:SetAttribute("PredictedRootUntil", now() + ROOT_PREDICT)
	-- A animação da skill começa na hora (o servidor confirma pelo CombatFX / atributo Charging)
	if cfg.Kind == "Barrage" then
		CombatAnimations.StartBarrage(style)
	elseif cfg.Kind == "Charge" then
		CombatAnimations.StartCharge(style)
	elseif cfg.Kind == "FoxSnap" then
		-- Kon! (fusão com a Raposa): gesto de invocação e a cabeça na hora; a mordida sai no SnapAt (servidor)
		local styleName = CombatStyles.FromCharacter(player.Character)
		local track = CombatAnimations.PlaySkill(style, cfg.Animation, cfg.AnimationStart, cfg.AnimationSpeed)
		if track then
			task.delay(cfg.SnapAt + cfg.Recovery, function()
				if track.IsPlaying then
					track:Stop(0.2)
				end
			end)
		end
		localFX("FoxSnap", { Character = player.Character, Style = styleName, Slot = slot, StartTime = now() })
		local hold = os.clock() + cfg.SnapAt
		m1RequestAfter = math.max(m1RequestAfter, hold)
		localLockUntil = math.max(localLockUntil, hold)
		player:SetAttribute("PredictedCombatLockUntil", now() + math.max(0, localLockUntil - os.clock()))
	elseif cfg.Kind == "CounterGrab" then
		-- Contra-agarrão: a postura (animação do agarrão errando) sai na hora; se o servidor avisar que pegou
		-- (CombatFX "CounterGrab"), troca para a animação do agarrão que pegou
		CombatAnimations.PlaySkill(style, cfg.Animation)
		local hold = os.clock() + cfg.Window
		m1RequestAfter = math.max(m1RequestAfter, hold)
		localLockUntil = math.max(localLockUntil, hold)
		player:SetAttribute("PredictedCombatLockUntil", now() + math.max(0, localLockUntil - os.clock()))
	elseif cfg.Animation then
		-- Skills da Katana: animação e efeitos na hora (o CombatFX segue os marcadores ou os tempos da skill)
		local styleName = CombatStyles.FromCharacter(player.Character)
		local track = CombatAnimations.PlaySkill(style, cfg.Animation)
		local attackId = CombatAnimations.AttackId()
		localFX("KatanaSkill", { Character = player.Character, Style = styleName, Slot = slot, Track = track })
		-- Nenhum M1 ou outra skill até o golpe sair (o servidor confirma pelo CombatBusyUntil)
		local hold = os.clock() + (cfg.SlashAt or cfg.GrabAt or 0.3)
		m1RequestAfter = math.max(m1RequestAfter, hold)
		localLockUntil = math.max(localLockUntil, hold)
		player:SetAttribute("PredictedCombatLockUntil", now() + math.max(0, localLockUntil - os.clock()))
		if cfg.Kind == "DashSlash" then
			task.delay(cfg.DashAt, dashForward, cfg, styleName, attackId)
		end
	end
	return true
end

-- Soltou a tecla da carga: a animação continua do marcador de carga, a hitbox sai no marcador de impacto e o
-- servidor confere a carga dele
local function releaseCharge(slot)
	local character = player.Character
	-- Toque rápido: espera o servidor confirmar que começou a carregar
	local deadline = os.clock() + 0.4
	while character and character:GetAttribute("Charging") ~= true and os.clock() < deadline do
		task.wait()
	end
	seq += 1
	local releaseSeq = seq
	Remotes.CombatSkill:FireServer(slot, false, releaseSeq)
	if not character or character:GetAttribute("Charging") ~= true or not canAct() then
		CombatAnimations.StopCharge()
		return
	end

	local styleName, style = CombatStyles.FromCharacter(character)
	local cfg = style.Skills[slot]
	-- "Carga rápida" na árvore encurta a carga (o servidor usa a mesma conta)
	local chargeTime = player:GetAttribute("TreeChargeTime")
	local maxCharge = cfg.MaxCharge * math.max(0.2, 1 - (if type(chargeTime) == "number" then chargeTime else 0))
	local power = math.clamp((os.clock() - (chargeStartedAt or os.clock())) / maxCharge, 0, 1)
	local track = CombatAnimations.ReleaseCharge()
	-- Fecha a carga e solta o efeito do soco (os outros veem pelo servidor)
	localFX("ChargedPunch", { Character = character, Style = styleName, Power = power })
	performAttack(releaseSeq, styleName, style, "ChargedPunch", nil, track, {
		Windup = cfg.Windup,
		Range = lerp(cfg.RangeMin, cfg.RangeMax, power),
		Heavy = true,
		Marker = cfg.HitMarker,
		Timeout = cfg.MarkerTimeout,
		Width = cfg.HitboxWidth,
	})
end

local function skill(slot, holding)
	if holding then
		local _, style = CombatStyles.FromCharacter(player.Character)
		local cfg = style and style.Skills[slot]
		if not cfg then return end
		if cfg.Hold then
			if chargeSlot then return end
			chargeSlot = slot
		end
		pending = if trySkill(slot) then nil else { Slot = slot, Expires = os.clock() + 0.35 }
	elseif chargeSlot == slot then
		chargeSlot = nil
		if pending and pending.Slot == slot then
			pending = nil
		end
		task.spawn(releaseCharge, slot)
	end
end

-- ================= Teclado =================

-- Skills do estilo nas teclas Z, X e C (CombatStyles.SkillSlots). O E ficou só para falar com NPC e os poderes do
-- caminho estão em V e B (PowerInput).
-- Controle (Xbox): RT ataca (segurar repete o combo), LT segura a guarda e B / Y / RB são as skills Z / X / C. O X do
-- controle fica para falar com NPC (ProximityPrompt) e o A para pular, como no padrão do Roblox.
local SKILL_KEYS = {
	[Enum.KeyCode.Z] = "Z",
	[Enum.KeyCode.X] = "X",
	[Enum.KeyCode.C] = "C",
	[Enum.KeyCode.ButtonB] = "Z",
	[Enum.KeyCode.ButtonY] = "X",
	[Enum.KeyCode.ButtonR1] = "C",
}
local BLOCK_KEYS = { [Enum.KeyCode.F] = true, [Enum.KeyCode.ButtonL2] = true }
local ATTACK_KEY = Enum.KeyCode.ButtonR2

-- Sem estilo na mão, o ataque do controle equipa o primeiro estilo da mochila (o próximo aperto já bate)
local function equipFirstStyle()
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local backpack = player:FindFirstChildOfClass("Backpack")
	if not humanoid or not backpack then return end
	for _, tool in backpack:GetChildren() do
		if tool:IsA("Tool") and CombatStyles.Styles[tool.Name] then
			humanoid:EquipTool(tool)
			return
		end
	end
end

UserInputService.InputBegan:Connect(function(input, processed)
	if processed or player:GetAttribute("MenuOpen") then return end
	local key = input.KeyCode
	if BLOCK_KEYS[key] then
		setBlock(true)
	elseif SKILL_KEYS[key] then
		skill(SKILL_KEYS[key], true)
	elseif key == ATTACK_KEY then
		-- Igual a segurar o clique: o Heartbeat solta o golpe (o RT também ativa o Tool sozinho no Roblox)
		if CombatStyles.FromCharacter(player.Character) then
			m1Held = true
		else
			equipFirstStyle()
		end
	end
end)

UserInputService.InputEnded:Connect(function(input)
	local key = input.KeyCode
	if BLOCK_KEYS[key] then
		setBlock(false)
	elseif SKILL_KEYS[key] then
		skill(SKILL_KEYS[key], false)
	elseif key == ATTACK_KEY then
		m1Held = false
	end
end)

UserInputService.WindowFocusReleased:Connect(function()
	m1Held = false
	bufferedUntil = 0
	setBlock(false)
	if chargeSlot then
		skill(chargeSlot, false)
	end
end)

-- ================= Toque pela HUD =================

local combatAction = Instance.new("BindableEvent")
combatAction.Name = "CombatAction"
combatAction.Parent = script.Parent
combatAction.Event:Connect(function(kind, a, b)
	if kind == "Block" then
		setBlock(a == true)
	elseif kind == "Skill" and table.find(CombatStyles.SkillSlots, a) then
		skill(a, b == true)
	elseif kind == "Attack" then
		-- Botão de ataque do celular: segurando repete o combo (o mesmo m1Held do clique segurado)
		m1Held = a == true and CombatStyles.FromCharacter(player.Character) ~= nil and not player:GetAttribute("MenuOpen")
		if m1Held and not tryM1() then
			local _, style = CombatStyles.FromCharacter(player.Character)
			bufferedUntil = os.clock() + (if style then style.M1.Buffer else 0.3)
		end
	end
end)

-- ================= Tool equipado =================

local toolConnections = {}
local currentTool

local function bindTool(tool)
	for _, connection in toolConnections do
		connection:Disconnect()
	end
	table.clear(toolConnections)
	currentTool = tool
	m1Held = false
	bufferedUntil = 0
	if not tool then
		setBlock(false)
		if chargeSlot then
			skill(chargeSlot, false)
		end
		pending = nil
		return
	end
	table.insert(toolConnections, tool.Activated:Connect(function()
		if player:GetAttribute("MenuOpen") then return end
		m1Held = true
		if not tryM1() then
			-- Clique no meio de um golpe: guarda e solta assim que der
			local _, style = CombatStyles.FromCharacter(player.Character)
			bufferedUntil = os.clock() + (if style then style.M1.Buffer else 0.3)
		end
	end))
	table.insert(toolConnections, tool.Deactivated:Connect(function()
		m1Held = false
	end))
end

local function onCharacter(character)
	bindTool(nil)
	blockHeld = false
	chargeSlot = nil
	chargeStartedAt = nil
	impactPending = nil
	predictedCombo = 0
	player:SetAttribute("PredictedCombatLockUntil", 0)
	-- Ragdoll (servidor: Ragdoll.luau, atributo "Ragdoll"): a física do personagem é deste cliente, então o Humanoid
	-- vai para o estado Physics aqui e levanta quando o atributo sai
	character:GetAttributeChangedSignal("Ragdoll"):Connect(function()
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if not humanoid or humanoid.Health <= 0 then return end
		if character:GetAttribute("Ragdoll") == true then
			humanoid:SetStateEnabled(Enum.HumanoidStateType.GettingUp, false)
			humanoid:ChangeState(Enum.HumanoidStateType.Physics)
		else
			humanoid:SetStateEnabled(Enum.HumanoidStateType.GettingUp, true)
			humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
		end
	end)
	-- Atordoado (inclusive por parry): o servidor zera o combo, aqui também
	character:GetAttributeChangedSignal("Stunned"):Connect(function()
		if character:GetAttribute("Stunned") == true then
			predictedCombo = 0
			bufferedUntil = 0
		end
	end)
	-- Começou a carregar: guarda a hora e solta sozinho no tempo máximo
	character:GetAttributeChangedSignal("Charging"):Connect(function()
		if character:GetAttribute("Charging") ~= true then return end
		local started = os.clock()
		chargeStartedAt = started
		local _, style = CombatStyles.FromCharacter(character)
		local slot = chargeSlot
		local cfg = style and slot and style.Skills[slot]
		if not cfg then return end
		task.delay(cfg.MaxHold, function()
			if chargeStartedAt == started and chargeSlot == slot and character:GetAttribute("Charging") == true then
				skill(slot, false)
			end
		end)
	end)
	character.ChildAdded:Connect(function(child)
		if child:IsA("Tool") and CombatStyles.Styles[child.Name] then
			bindTool(child)
		end
	end)
	character.ChildRemoved:Connect(function(child)
		if child == currentTool then
			bindTool(nil)
		end
	end)
	local _, _, tool = CombatStyles.FromCharacter(character)
	if tool then
		bindTool(tool)
	end
end

player.CharacterAdded:Connect(onCharacter)
if player.Character then
	task.spawn(onCharacter, player.Character)
end

-- Contra-agarrão pegou (CombatService): toca o agarrão que pegou em quem contra-atacou (este jogador)
Remotes.CombatFX.OnClientEvent:Connect(function(kind, data)
	if kind ~= "CounterGrab" or type(data) ~= "table" or data.Character ~= player.Character then return end
	local _, style = CombatStyles.FromCharacter(player.Character)
	local cfg = style and style.Skills.C
	if not cfg or cfg.Kind ~= "CounterGrab" then
		for _, slot in CombatStyles.SkillSlots do
			local skillCfg = style and style.Skills[slot]
			if skillCfg and skillCfg.Kind == "CounterGrab" then
				cfg = skillCfg
			end
		end
	end
	if cfg then
		CombatAnimations.PlaySkill(style, cfg.SuccessAnimation)
	end
end)

-- ================= Repetição =================

RunService.Heartbeat:Connect(function()
	-- Segurando o clique ou com clique guardado: solta o próximo golpe assim que der
	if m1Held or os.clock() < bufferedUntil then
		if tryM1() then
			bufferedUntil = 0
		end
	end

	-- Segurando F: pede a guarda até o servidor aceitar (ex.: apertou no meio de um golpe)
	if blockHeld and os.clock() - lastBlockRequest > 0.2 and canAct() and not locked() then
		local character = player.Character
		if character:GetAttribute("Blocking") ~= true and character:GetAttribute("Charging") ~= true then
			-- Só o primeiro pedido corta o soco (se o servidor recusar, os próximos não atrapalham os golpes)
			if lastBlockRequest == 0 then
				CombatAnimations.CancelAttack()
			end
			lastBlockRequest = os.clock()
			Remotes.CombatBlock:FireServer(true)
		end
	end

	if pending and (os.clock() > pending.Expires or trySkill(pending.Slot)) then
		pending = nil
	end
end)
