
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local CharacterAnimations = require(ReplicatedStorage:WaitForChild("CharacterAnimations"))
local Remotes = require(ReplicatedStorage:WaitForChild("Remotes"))
local NetConfig = require(ReplicatedStorage:WaitForChild("CombatNetConfig"))
local CombatAnimations = require(script.Parent:WaitForChild("CombatAnimations"))
local player = Players.LocalPlayer
local stats = player:WaitForChild("Stats")
local speedStat = stats:WaitForChild("Velocidade")
local energyStat = stats:WaitForChild("Energia")

local RUN_MULTIPLIER = 1.6 -- correndo
local DASH_COST = NetConfig.DashCost
local DASH_DISTANCE = NetConfig.DashDistance
local DASH_TIME = NetConfig.DashTime
local DASH_COOLDOWN = NetConfig.DashCooldown
local DOUBLE_JUMP_GAP = 0.12 -- o pulo duplo precisa de um novo aperto (segurar o pulo não conta)
local DASH_TRACKS = { "Dash", "DashBack", "DashLeft", "DashRight" }
-- A animação do dash é mais longa que o empurrão: depois dele ela some se o jogador andar (para não deslizar na
-- pose do dash), mas toca pelo menos isso. Parado, toca até o fim.
local DASH_ANIM_MIN = 0.45
-- Caixa que procura parede no caminho do dash: do joelho à cabeça (degrau baixo e rampa não contam) e mais fina
-- que o tronco (encostado na parede, ela ainda não encosta e acha a parede)
local WALL_BOX = NetConfig.WallBox
local WALL_BOX_DROP = NetConfig.WallBoxDrop
local WALL_NORMAL_Y = NetConfig.WallNormalY
-- Animações padrão (Animate) que precisam de loop: o Animate do R6 usa o que está salvo na animação
local LOOPED_DEFAULTS = { Idle = true, Walk = true, Climb = true }

local baseSpeed = speedStat.Value
-- Bônus de velocidade dos passivos do caminho (atributo SpeedBonus, escrito pelo servidor)
local function readSpeedBonus()
	local value = player:GetAttribute("SpeedBonus")
	return if type(value) == "number" then value else 0
end
local speedBonus = readSpeedBonus()

-- Desvio rápido da esquiva (DodgeData, nível 5): velocidade a mais por um tempo depois de desviar (atributo
-- DodgeRushUntil, escrito pelo servidor)
local DodgeData = require(ReplicatedStorage:WaitForChild("DodgeData"))
local function dodgeRush()
	local untilTime = player:GetAttribute("DodgeRushUntil")
	return if type(untilTime) == "number" and workspace:GetServerTimeNow() < untilTime then DodgeData.Rush.Speed else 0
end

-- Efeitos da árvore de habilidades (atributos Tree<Efeito> que o servidor escreve no player)
local function treeEffect(key)
	local value = player:GetAttribute("Tree" .. key)
	return if type(value) == "number" then value else 0
end

local function dashCost()
	return DASH_COST * math.max(0, 1 - treeEffect("DashCost"))
end

local maxStamina = math.max(1, energyStat.Value)
local stamina = maxStamina
local character, humanoid, rootPart
local tracks = {}
local characterConnections = {}
local generation = 0
local running = false
local ctrlHeld = false
local dashVelocity, dashAttachment
local dashEnds = 0
local breakerDash = false -- o dash atual é um quebra-combo (sai atordoado; o stun não corta ele)
local nextDashAt = 0
local dashSeq = 0
local pendingDash, dashLimit, staminaSnapshot
local dashTrack, dashStarted -- animação do último dash (para sumir quando o jogador anda)
local jumpWasEnabled
local usedDoubleJump, lastJumpRequest = false, 0 -- pulo duplo: já usou neste pulo / último aperto de pular
-- Corrida automática: vem do perfil (atributo SettingAutoRun, escrito pelo servidor ao carregar); até lá, ligada
local autoRun = player:GetAttribute("SettingAutoRun") ~= false

local wallParams = RaycastParams.new()
wallParams.FilterType = Enum.RaycastFilterType.Exclude
wallParams.RespectCanCollide = true

-- A stamina real vem do servidor. A HUD mostra uma previsão separada, sem reescrever os atributos autoritativos.
local lastPublished
local function publishStamina()
	local now = workspace:GetServerTimeNow()
	local snapshot = staminaSnapshot
	if snapshot and snapshot.Character == player.Character then
		maxStamina = snapshot.Max
		stamina = math.min(maxStamina, snapshot.Stamina + math.max(0, now - snapshot.Time) * snapshot.Regen)
		if pendingDash and pendingDash.Seq > snapshot.Ack then stamina = math.max(0, stamina - pendingDash.Cost) end
	else
		maxStamina = player:GetAttribute("MaxStamina") or math.max(1, energyStat.Value)
		stamina = player:GetAttribute("Stamina") or maxStamina
		if pendingDash then stamina = math.max(0, stamina - pendingDash.Cost) end
	end
	local rounded = math.floor(stamina * 10 + 0.5) / 10
	if rounded ~= lastPublished then
		lastPublished = rounded
		player:SetAttribute("PredictedStamina", rounded)
	end
end

-- Liga/desliga a corrida automática; save = true guarda no perfil (quando o jogador mexe no interruptor da HUD)
local function setAutoRun(value, save)
	autoRun = value == true
	player:SetAttribute("AutoRun", autoRun)
	if save then
		Remotes.SaveSetting:FireServer("AutoRun", autoRun)
	end
end

-- Quer correr agora? Com a corrida automática, sim (segurar Ctrl anda); sem ela, só segurando Ctrl
local function wantsToRun()
	if autoRun then
		return not ctrlHeld
	end
	return ctrlHeld
end

local function stopTrack(name, fade)
	local track = tracks[name]
	if track and track.IsPlaying then track:Stop(fade or 0.1) end
end

local function playTrack(name)
	local track = tracks[name]
	if track and not track.IsPlaying then track:Play(0.1) end
end

-- Correndo: a animação de andar com os punhos (CombatAnimations) sai enquanto isso
local function setRunning(value)
	running = value
	if player:GetAttribute("Sprinting") ~= value then
		player:SetAttribute("Sprinting", value)
	end
	if not value then
		stopTrack("Run")
	end
end

local function jumpVelocity()
	if humanoid.UseJumpPower then
		return humanoid.JumpPower
	end
	return math.sqrt(2 * workspace.Gravity * humanoid.JumpHeight)
end

-- Parede (ou outra coisa sólida) a menos de distance na direção do dash?
local function wallAhead(direction, distance)
	if not rootPart or distance <= 0 or direction.Magnitude < 0.5 then return false end
	wallParams.FilterDescendantsInstances = { character }
	wallParams.CollisionGroup = rootPart.CollisionGroup
	local center = rootPart.Position - Vector3.new(0, WALL_BOX_DROP, 0)
	local result = workspace:Blockcast(CFrame.lookAt(center, center + direction), WALL_BOX, direction * distance, wallParams)
	return result ~= nil and result.Normal.Y < WALL_NORMAL_Y
end

-- Fim do empurrão: a velocidade que sobra não passa da de correr (no ar ela levava o personagem longe) e, batendo
-- na parede, zera. Subida acima da de um pulo também sai (a física empurrando para cima na quina).
local function settleAfterDash(hitWall)
	if not rootPart or not humanoid then return end
	local velocity = rootPart.AssemblyLinearVelocity
	local flat = Vector3.new(velocity.X, 0, velocity.Z)
	local limit = if hitWall then 0 else math.max(0, baseSpeed + speedBonus) * RUN_MULTIPLIER
	if flat.Magnitude > limit then
		flat = if limit > 0 then flat.Unit * limit else Vector3.zero
	end
	rootPart.AssemblyLinearVelocity = Vector3.new(flat.X, math.min(velocity.Y, jumpVelocity()), flat.Z)
end

-- Fim do empurrão do dash. A animação continua até o fim, a não ser que o dash seja cortado (stun, morte).
-- Devolve true se havia um empurrão ativo.
local function stopDash(cutAnimation)
	local wasDashing = dashVelocity ~= nil
	dashLimit = nil
	breakerDash = false
	if dashVelocity then dashVelocity:Destroy() dashVelocity = nil end
	if dashAttachment then dashAttachment:Destroy() dashAttachment = nil end
	if cutAnimation then
		dashTrack = nil
		for _, name in DASH_TRACKS do
			stopTrack(name)
		end
	end
	return wasDashing
end

local function stopActions()
	setRunning(false)
	if stopDash(true) then
		settleAfterDash(false)
	end
end

local function alive()
	return humanoid ~= nil and humanoid.Parent ~= nil and humanoid.Health > 0 and rootPart ~= nil
end

-- Parado: morto, atordoado (menos no dash do quebra-combo) ou com o menu principal aberto (MenuOpen, do MainMenu)
local function blocked()
	return not alive() or (character:GetAttribute("Stunned") == true and not breakerDash)
		or player:GetAttribute("MenuOpen") == true
end

-- Lentidão do combate (CombatSpeed, escrito pelo servidor): socando anda um pouco mais devagar e sem correr;
-- abaixo de 0,6 (guarda, soco carregando, rajada) também não dá dash. No M1 o dash cancela o fim do golpe.
local STANCE_SPEED = 0.6
local function combatSlow()
	local value = character and character:GetAttribute("CombatSpeed")
	return if type(value) == "number" then math.clamp(value, 0, 1) else 1
end

local function inCombatStance()
	return combatSlow() < STANCE_SPEED
end

local function updateMovement()
	if not alive() then return end
	local stunned = character:GetAttribute("Stunned") == true and not breakerDash
	if stunned then stopActions() end
	local slow = combatSlow()
	if slow < 1 and running then
		setRunning(false)
	end
	if stunned and jumpWasEnabled == nil then
		jumpWasEnabled = humanoid:GetStateEnabled(Enum.HumanoidStateType.Jumping)
		humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, false)
		humanoid.Jump = false
	elseif not stunned and jumpWasEnabled ~= nil then
		humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, jumpWasEnabled)
		jumpWasEnabled = nil
	end
	-- Este é o único ponto que escreve WalkSpeed do jogador.
	local speed = character:GetAttribute("AdminWalkSpeed") or math.max(0, baseSpeed + speedBonus + dodgeRush()) * slow
	humanoid.WalkSpeed = if stunned then 0 elseif running then speed * RUN_MULTIPLIER else speed
end

local function cleanupCharacter()
	generation += 1
	pendingDash = nil
	player:SetAttribute("PredictedDashReadyAt", 0)
	stopActions()
	if humanoid and humanoid.Parent and jumpWasEnabled ~= nil then
		humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, jumpWasEnabled)
	end
	jumpWasEnabled = nil
	for _, connection in characterConnections do connection:Disconnect() end
	table.clear(characterConnections)
	for _, track in tracks do track:Stop() track:Destroy() end
	table.clear(tracks)
	character, humanoid, rootPart = nil, nil, nil
end

local function setupCharacter(newCharacter)
	cleanupCharacter()
	local version = generation
	local newHumanoid = newCharacter:WaitForChild("Humanoid", 10)
	local newRoot = newCharacter:WaitForChild("HumanoidRootPart", 10)
	if version ~= generation or player.Character ~= newCharacter or not newHumanoid or not newRoot then return end
	local animator = newHumanoid:WaitForChild("Animator", 10)
	if version ~= generation or player.Character ~= newCharacter then return end
	character, humanoid, rootPart = newCharacter, newHumanoid, newRoot
	stamina = maxStamina
	dashEnds = 0
	nextDashAt = 0
	player:SetAttribute("PredictedDashReadyAt", 0)
	if animator then
		-- IDs em ReplicatedStorage.CharacterAnimations (Movement); 0 = não toca nada
		local movement = CharacterAnimations.Movement
		local ids = {
			Run = CharacterAnimations.Id(movement.Sprint),
			Dash = CharacterAnimations.Id(movement.Dash),
			DashBack = CharacterAnimations.Id(movement.DashBack),
			DashLeft = CharacterAnimations.Id(movement.DashLeft),
			DashRight = CharacterAnimations.Id(movement.DashRight),
		}
		for name, id in ids do
			local animation = Instance.new("Animation")
			animation.AnimationId = "rbxassetid://" .. id
			local ok, track = pcall(function() return animator:LoadAnimation(animation) end)
			animation:Destroy()
			if ok then
				track.Looped = name == "Run"
				-- Camadas (ver CombatAnimations): correr em Movement, dash em Action (abaixo de reação e golpe)
				track.Priority = if name == "Run" then Enum.AnimationPriority.Movement else Enum.AnimationPriority.Action
				tracks[name] = track
			end
		end
		-- Animações padrão trocadas pelo CharacterAnimations.server (andar, pulo...): o Animate do R6 usa a prioridade
		-- e o loop salvos na animação. Ficam em Core (abaixo do combate e da corrida) e o andar/parado em loop.
		local defaults = {}
		for key, value in CharacterAnimations.Default do
			local id = CharacterAnimations.Id(value)
			if id then
				defaults["rbxassetid://" .. id] = key
			end
		end
		table.insert(characterConnections, animator.AnimationPlayed:Connect(function(track)
			local key = track.Animation and defaults[track.Animation.AnimationId]
			if not key then return end
			track.Priority = Enum.AnimationPriority.Core
			if LOOPED_DEFAULTS[key] then
				track.Looped = true
			end
		end))
	end
	table.insert(characterConnections, character:GetAttributeChangedSignal("Stunned"):Connect(updateMovement))
	table.insert(characterConnections, character:GetAttributeChangedSignal("AdminWalkSpeed"):Connect(updateMovement))
	table.insert(characterConnections, character:GetAttributeChangedSignal("CombatSpeed"):Connect(updateMovement))
	table.insert(characterConnections, humanoid.Died:Connect(stopActions))
	-- Encostou no chão: o pulo duplo volta a valer
	usedDoubleJump = false
	table.insert(characterConnections, humanoid.StateChanged:Connect(function(_, new)
		if new == Enum.HumanoidStateType.Landed or new == Enum.HumanoidStateType.Running then
			usedDoubleJump = false
		end
	end))
	updateMovement()
end

-- Direção do dash e a animação dela: para onde o jogador está andando, comparado com a frente do personagem
local function dashDirection()
	local look = rootPart.CFrame.LookVector
	local forward = Vector3.new(look.X, 0, look.Z)
	forward = if forward.Magnitude > 0.001 then forward.Unit else Vector3.new(0, 0, -1)
	local move = humanoid.MoveDirection
	local flatMove = Vector3.new(move.X, 0, move.Z)
	if flatMove.Magnitude < 0.1 then
		return forward, "Dash"
	end
	flatMove = flatMove.Unit
	local rightVector = rootPart.CFrame.RightVector
	local right = Vector3.new(rightVector.X, 0, rightVector.Z)
	right = if right.Magnitude > 0.001 then right.Unit else Vector3.new(1, 0, 0)
	local ahead, side = flatMove:Dot(forward), flatMove:Dot(right)
	local name
	if math.abs(ahead) >= math.abs(side) then
		name = if ahead >= 0 then "Dash" else "DashBack"
	else
		name = if side >= 0 then "DashRight" else "DashLeft"
	end
	return flatMove, name
end

local function dash()
	publishStamina()
	local cost = dashCost()
	local now = workspace:GetServerTimeNow()
	local readyAt = if staminaSnapshot and staminaSnapshot.Character == character then staminaSnapshot.ReadyAt
		else player:GetAttribute("DashReadyAt") or 0
	-- Quebra-combo (servidor: ComboBreakerReady): atordoado, o dash sai mesmo assim e ignora as travas do combate
	local breaking = alive() and character:GetAttribute("Stunned") == true
		and player:GetAttribute("ComboBreakerReady") == true and player:GetAttribute("MenuOpen") ~= true
	if (not breaking and (blocked() or inCombatStance() or now < (player:GetAttribute("CombatLockUntil") or 0)
		or now < (player:GetAttribute("PredictedCombatLockUntil") or 0)))
		or dashVelocity or pendingDash or stamina < cost or os.clock() < nextDashAt or now < readyAt then return end
	local direction, animationName = dashDirection()
	-- Colado numa parede nessa direção: nem sai (não gasta stamina nem a recarga)
	if wallAhead(direction, 1.5) then return end
	dashSeq += 1
	pendingDash = { Seq = dashSeq, Character = character, Cost = cost, Time = now, Start = rootPart.CFrame, Breaker = breaking }
	dashLimit = { Start = rootPart.Position, Direction = direction, Distance = DASH_DISTANCE }
	Remotes.DashRequest:FireServer(character, dashSeq, direction, now, rootPart.CFrame)
	CombatAnimations.CancelAttack() -- dash cancela o fim do soco
	nextDashAt = os.clock() + DASH_COOLDOWN
	player:SetAttribute("PredictedDashReadyAt", now + DASH_COOLDOWN)
	publishStamina()
	setRunning(false)
	for _, name in DASH_TRACKS do
		if name ~= animationName then
			stopTrack(name, 0.05)
		end
	end
	local track = tracks[animationName]
	if track then
		if track.IsPlaying then track:Stop(0) end
		track:Play(0.05)
	end
	dashTrack, dashStarted = track, os.clock()
	dashAttachment = Instance.new("Attachment")
	dashAttachment.Parent = rootPart
	dashVelocity = Instance.new("LinearVelocity")
	dashVelocity.Attachment0 = dashAttachment
	dashVelocity.RelativeTo = Enum.ActuatorRelativeTo.World
	dashVelocity.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
	dashVelocity.ForceLimitsEnabled = true
	dashVelocity.ForceLimitMode = Enum.ForceLimitMode.PerAxis
	dashVelocity.MaxAxesForce = Vector3.new(1e5, 0, 1e5)
	dashVelocity.VectorVelocity = direction * (DASH_DISTANCE / DASH_TIME)
	dashVelocity.Parent = rootPart
	dashEnds = os.clock() + DASH_TIME
	breakerDash = breaking
end

local function rejectDash(request)
	if request.Character ~= character or not alive() then return end
	stopDash(true)
	-- Só desfaz o deslocamento previsto desse dash; não puxa um personagem morto/atordoado por outro golpe
	-- (o quebra-combo recusado volta: ele saiu já atordoado).
	if (character:GetAttribute("Stunned") ~= true or request.Breaker)
		and (rootPart.Position - request.Start.Position).Magnitude <= DASH_DISTANCE + NetConfig.OriginTolerance then
		rootPart.CFrame = request.Start
		settleAfterDash(true)
	end
end

Remotes.DashState.OnClientEvent:Connect(function(data)
	if type(data) ~= "table" or data.Character ~= player.Character then return end
	if staminaSnapshot and staminaSnapshot.Character == data.Character and data.Revision <= staminaSnapshot.Revision then return end
	staminaSnapshot = data
	local request = pendingDash
	if request and request.Character == data.Character and request.Seq == data.Seq then
		pendingDash = nil
		nextDashAt = os.clock() + math.max(0, data.ReadyAt - workspace:GetServerTimeNow())
		player:SetAttribute("PredictedDashReadyAt", 0)
		if not data.Accepted then
			rejectDash(request)
		elseif request.Character == character and alive() then
			if dashVelocity then
				dashLimit = { Start = data.Start, Direction = data.Direction, Distance = data.Distance }
			end
			-- Resposta atrasada com parede mais próxima: corrige o excesso mesmo se o empurrão já terminou.
			local offset = rootPart.Position - data.Start
			local excess = offset:Dot(data.Direction) - data.Distance
			if data.Distance < DASH_DISTANCE and excess > 0 and character:GetAttribute("Stunned") ~= true
				and offset.Magnitude <= DASH_DISTANCE + NetConfig.OriginTolerance then
				rootPart.CFrame -= data.Direction * excess
				stopDash(false)
				settleAfterDash(true)
			end
		end
	end
	publishStamina()
end)

-- Controle (Xbox): LB faz o dash e segurar L3 (apertar o analógico esquerdo) vale o Ctrl
local WALK_KEYS = { [Enum.KeyCode.LeftControl] = true, [Enum.KeyCode.ButtonL3] = true }
local DASH_KEYS = { [Enum.KeyCode.Q] = true, [Enum.KeyCode.ButtonL1] = true }

UserInputService.InputBegan:Connect(function(input, processed)
	-- Ctrl conta mesmo atordoado: soltando o stun, a corrida já sai certa
	if WALK_KEYS[input.KeyCode] then
		ctrlHeld = true
		return
	end
	if processed then return end
	-- O dash confere o bloqueio sozinho (o quebra-combo sai mesmo atordoado)
	if DASH_KEYS[input.KeyCode] then
		dash()
	elseif blocked() then
		return
	end
	updateMovement()
end)

-- Toques na HUD: o HUB_GUI dispara neste BindableEvent (só no cliente)
--   ("Dash"): slot Q; ("AutoRun", ligado): interruptor das configurações
local movementAction = Instance.new("BindableEvent")
movementAction.Name = "MovementAction"
movementAction.Parent = script.Parent
movementAction.Event:Connect(function(action, value)
	if action == "Dash" then
		dash()
	elseif action == "AutoRun" then
		setAutoRun(if type(value) == "boolean" then value else not autoRun, true)
	end
	updateMovement()
end)
UserInputService.InputEnded:Connect(function(input)
	if WALK_KEYS[input.KeyCode] then ctrlHeld = false end
	updateMovement()
end)

-- A configuração salva chega quando o perfil carrega (e não muda depois disso)
player:GetAttributeChangedSignal("SettingAutoRun"):Connect(function()
	local value = player:GetAttribute("SettingAutoRun")
	if type(value) == "boolean" then
		setAutoRun(value, false)
	end
end)
setAutoRun(autoRun, false)

-- Pulo duplo (nó "Pulo duplo" da árvore: atributo TreeDoubleJump): pular de novo no ar, uma vez até encostar
-- no chão. Precisa de um aperto novo (o JumpRequest repete enquanto o pulo está pressionado).
UserInputService.JumpRequest:Connect(function()
	local clock = os.clock()
	local fresh = clock - lastJumpRequest > DOUBLE_JUMP_GAP
	lastJumpRequest = clock
	if not fresh or usedDoubleJump or player:GetAttribute("TreeDoubleJump") ~= true or blocked() then return end
	local state = humanoid:GetState()
	if state ~= Enum.HumanoidStateType.Freefall and state ~= Enum.HumanoidStateType.Jumping then return end
	usedDoubleJump = true
	local velocity = rootPart.AssemblyLinearVelocity
	rootPart.AssemblyLinearVelocity = Vector3.new(velocity.X, jumpVelocity(), velocity.Z)
end)
UserInputService.WindowFocusReleased:Connect(function()
	ctrlHeld = false
	stopActions()
	updateMovement()
end)
speedStat.Changed:Connect(function(value) baseSpeed = math.max(0, value) updateMovement() end)
player:GetAttributeChangedSignal("SpeedBonus"):Connect(function() speedBonus = readSpeedBonus() updateMovement() end)
player:GetAttributeChangedSignal("DodgeRushUntil"):Connect(function()
	updateMovement()
	local untilTime = player:GetAttribute("DodgeRushUntil")
	if type(untilTime) == "number" then
		task.delay(math.max(0, untilTime - workspace:GetServerTimeNow()) + 0.05, updateMovement)
	end
end)
energyStat.Changed:Connect(function(value) maxStamina = math.max(1, value) stamina = math.min(stamina, maxStamina) end)
player.CharacterAdded:Connect(setupCharacter)
player.CharacterRemoving:Connect(function(oldCharacter)
	if character == oldCharacter or character == nil then cleanupCharacter() end
end)
if player.Character then task.spawn(setupCharacter, player.Character) end

RunService.RenderStepped:Connect(function(dt)
	if not alive() then return end
	if blocked() then stopActions() end
	if pendingDash and workspace:GetServerTimeNow() - pendingDash.Time > NetConfig.DashReplyTimeout then
		local request = pendingDash
		pendingDash = nil
		player:SetAttribute("PredictedDashReadyAt", 0)
		rejectDash(request)
	end
	if dashVelocity then
		-- Olha um frame e pouco à frente: parede no caminho encerra o dash ali
		local velocity = dashVelocity.VectorVelocity
		local reachedLimit = dashLimit and (rootPart.Position - dashLimit.Start):Dot(dashLimit.Direction) >= dashLimit.Distance
		if reachedLimit or os.clock() >= dashEnds then
			stopDash(false)
			settleAfterDash(false)
		elseif velocity.Magnitude > 0 and wallAhead(velocity.Unit, velocity.Magnitude * dt + 1.2) then
			stopDash(false)
			settleAfterDash(true)
		end
	end
	-- Empurrão acabou e o jogador está andando: a pose do dash sai (sem deslizar nela)
	if dashTrack and not dashVelocity and os.clock() - dashStarted >= DASH_ANIM_MIN then
		if not dashTrack.IsPlaying then
			dashTrack = nil
		elseif humanoid.MoveDirection.Magnitude > 0.1 then
			dashTrack:Stop(0.25)
			dashTrack = nil
		end
	end
	-- Corre andando, sem lentidão do combate, fora do dash e do stun
	local moving = humanoid.MoveDirection.Magnitude > 0
	local shouldRun = moving and wantsToRun() and not blocked() and combatSlow() >= 1 and not dashVelocity
	if shouldRun ~= running then
		setRunning(shouldRun)
	end
	if running then
		playTrack("Run")
	else
		stopTrack("Run")
	end
	updateMovement()
	publishStamina()
end)
publishStamina()
