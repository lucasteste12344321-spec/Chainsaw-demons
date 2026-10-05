-- Autoriza dash e mantém stamina/recarga no servidor; o cliente só prevê movimento e apresentação.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local RS = game:GetService("ReplicatedStorage")
local Remotes = require(RS:WaitForChild("Remotes"))
local Config = require(RS:WaitForChild("CombatNetConfig"))
local CombatState = require(script.Parent:WaitForChild("CombatState"))
local Rewind = require(script.Parent:WaitForChild("CombatRewind"))
local History = require(script.Parent:WaitForChild("PositionHistory"))
local states = {}

local function effect(player, name)
	local value = player:GetAttribute("Tree" .. name)
	return if History.Finite(value) then value else 0
end

local function update(player, state, now)
	local stats = player:FindFirstChild("Stats")
	local energy = stats and stats:FindFirstChild("Energia")
	local maximum = if energy and History.Finite(energy.Value) then math.max(1, energy.Value) else 100
	if energy and History.Finite(energy.Value) and not state.EnergyReady then
		-- O perfil pode chegar depois do spawn. Completa a capacidade inicial, preservando eventual gasto.
		state.Stamina += maximum - state.Max
		state.EnergyReady = true
	end
	state.Max = maximum
	state.Regen = Config.StaminaRegen * math.max(0, 1 + effect(player, "StaminaRegen"))
	state.Stamina = math.clamp(state.Stamina + math.max(0, now - state.Time) * state.Regen, 0, maximum)
	state.Time = now
end

-- Folga para o atraso do ping (metade do ida e volta + um pouco, até 0,2 s). As travas do combate e a recarga do dash
-- são contadas da chegada no servidor, mas o pedido de dash chega com o atraso dele: sem a folga, um dash dado logo no
-- fim da trava do M1 (cancelar o soco) era recusado quando o ping oscilava, e o personagem voltava para trás.
local function latencyGrace(player)
	local ok, ping = pcall(function() return player:GetNetworkPing() end)
	ping = if ok and History.Finite(ping) then ping else 0
	return math.clamp(ping / 2 + 0.05, 0.05, 0.2)
end

local function publish(player, state, seq, accepted, extra)
	state.Revision += 1
	player:SetAttribute("Stamina", state.Stamina)
	player:SetAttribute("MaxStamina", state.Max)
	player:SetAttribute("StaminaRegenRate", state.Regen)
	player:SetAttribute("StaminaUpdatedAt", state.Time)
	player:SetAttribute("DashReadyAt", state.ReadyAt)
	local data = extra or {}
	data.Character, data.Revision = state.Character, state.Revision
	data.Stamina, data.Max, data.Regen = state.Stamina, state.Max, state.Regen
	data.Time, data.ReadyAt, data.Ack = state.Time, state.ReadyAt, state.LastSeq
	data.Seq, data.Accepted = seq, accepted
	Remotes.DashState:FireClient(player, data)
end

local function onCharacter(player, character)
	local now = workspace:GetServerTimeNow()
	local state = { Character = character, Stamina = 0, Max = 100, Regen = Config.StaminaRegen,
		Time = now, ReadyAt = 0, LastSeq = 0, Revision = 0, LastRequest = -math.huge }
	states[player] = state
	update(player, state, now)
	state.Stamina = state.Max
	publish(player, state)
end

local function onPlayer(player)
	player.CharacterAdded:Connect(function(character) onCharacter(player, character) end)
	player.CharacterRemoving:Connect(function(character)
		if states[player] and states[player].Character == character then states[player] = nil end
	end)
	if player.Character then onCharacter(player, player.Character) end
end
Players.PlayerAdded:Connect(onPlayer)
Players.PlayerRemoving:Connect(function(player) states[player] = nil end)
for _, player in Players:GetPlayers() do onPlayer(player) end

local function onDash(player, character, seq, direction, timestamp, origin)
	local state = states[player]
	if not state or character ~= state.Character or character ~= player.Character then return end
	if not History.Finite(seq) or seq < 1 or seq >= 2 ^ 31 or seq % 1 ~= 0 or seq <= state.LastSeq then return end
	local now = workspace:GetServerTimeNow()
	update(player, state, now)
	-- Pedido colado no anterior: responde a recusa (sem resposta, o cliente esperava 1 s e voltava para trás)
	if now - state.LastRequest < Config.DashRequestGap then
		state.LastSeq = seq
		publish(player, state, seq, false, { Reason = "Pedido repetido" })
		return
	end
	state.LastRequest, state.LastSeq = now, seq
	-- O motivo vai na resposta (o cliente mostra no Output/F9 para dar para saber por que um dash foi recusado)
	local function deny(reason) publish(player, state, seq, false, { Reason = reason }) end
	local root = character:FindFirstChild("HumanoidRootPart")
	local hum = character:FindFirstChildOfClass("Humanoid")
	local grace = latencyGrace(player)
	-- Quebra-combo (CombatStyles.PvP): atordoado depois de apanhar muito seguido, o dash sai mesmo assim
	local breaking = character:GetAttribute("Stunned") == true and CombatState.CanBreakCombo(player)
	if not root or not root:IsA("BasePart") or not hum or hum.Health <= 0 or hum.SeatPart or root.Anchored then
		deny("Personagem"); return
	end
	if not breaking then
		if character:GetAttribute("Stunned") == true then deny("Atordoado"); return end
		if CombatState.InStance(player) then deny("Guarda/carga"); return end
		if CombatState.LockRemaining(player) > grace then deny("Golpe em andamento"); return end
	end
	if now < state.ReadyAt - grace then deny("Recarga"); return end
	local slow = character:GetAttribute("CombatSpeed")
	if not breaking and type(slow) == "number" and slow < 0.6 then deny("Lento"); return end
	if typeof(direction) ~= "Vector3" or not History.Finite(direction.X) or not History.Finite(direction.Y)
		or not History.Finite(direction.Z) or math.abs(direction.Y) > 0.01
		or direction.Magnitude < 0.9 or direction.Magnitude > 1.1 then deny("Direção"); return end
	local _, sentAt = Rewind.ResolveTime(player, timestamp, now, Config.DashTimestampSlack)
	if not sentAt then deny("Horário"); return end
	-- Correndo, o personagem anda enquanto o pedido viaja: a tolerância cresce com a velocidade (até 10 studs)
	local velocity = root.AssemblyLinearVelocity
	local extraTolerance = math.min(10, Vector3.new(velocity.X, 0, velocity.Z).Magnitude * (grace + 0.1))
	if not Rewind.Origin(character, sentAt, origin, extraTolerance) then deny("Posição"); return end
	local cost = Config.DashCost * math.max(0, 1 - effect(player, "DashCost"))
	if state.Stamina < cost - 0.5 then deny("Fôlego"); return end
	direction = Vector3.new(direction.X, 0, direction.Z).Unit
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character }
	params.RespectCanCollide = true
	params.CollisionGroup = root.CollisionGroup
	local center = origin.Position - Vector3.new(0, Config.WallBoxDrop, 0)
	local wall = workspace:Blockcast(CFrame.lookAt(center, center + direction), Config.WallBox,
		direction * Config.DashDistance, params)
	local distance = Config.DashDistance
	if wall and wall.Normal.Y < Config.WallNormalY then distance = math.max(0, wall.Distance - 1.2) end
	if distance < 1.5 then deny("Parede"); return end
	-- A decisão e o desconto não cedem execução: pedidos simultâneos não gastam o mesmo saldo.
	state.Stamina = math.max(0, state.Stamina - cost)
	state.ReadyAt = now + Config.DashCooldown
	if breaking then CombatState.BreakCombo(player) end
	CombatState.InterruptForDash(player)
	CombatState.SetBusy(player, now + math.max(0, Config.DashTime - (now - sentAt)))
	publish(player, state, seq, true, { Start = origin.Position, Direction = direction, Distance = distance })
end
Remotes.DashRequest.OnServerEvent:Connect(onDash)

local elapsed = 0
RunService.Heartbeat:Connect(function(dt)
	elapsed += dt
	if elapsed < 0.2 then return end
	elapsed %= 0.2
	local now = workspace:GetServerTimeNow()
	for player, state in states do
		local old, maximum, regen = state.Stamina, state.Max, state.Regen
		update(player, state, now)
		if old ~= state.Stamina or maximum ~= state.Max or regen ~= state.Regen then publish(player, state) end
	end
end)
