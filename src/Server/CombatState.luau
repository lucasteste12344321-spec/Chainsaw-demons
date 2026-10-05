-- Estado de combate no servidor: combo, recargas, guarda (block/parry/quebra), atordoamento e lentidão.
-- Quem usa: CombatService (golpes dos estilos), CombatRules (bloqueio dentro do dano) e os poderes dos caminhos.
--
-- Atributos que o cliente lê:
--   player:    CombatBusyUntil (próximo M1), CombatLockUntil (skills e block; menor que o Busy dentro da janela de
--              cancelamento do M1), Combat<Z|X|C>ReadyAt (GetServerTimeNow), Guard, MaxGuard
--   personagem: Stunned, Blocking, Charging, CombatSpeed (multiplicador de velocidade; o script de movimento aplica)
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Remotes = require(ReplicatedStorage:WaitForChild("Remotes"))
local CombatStyles = require(ReplicatedStorage:WaitForChild("CombatStyles"))

local CombatState = {}

local DEFAULT_BLOCK = CombatStyles.Styles.Punhos.Block
local PVP = CombatStyles.PvP

local states = {}
local stunned = {}
local interruptHandlers = {}
-- Jogadores que apanham de outros jogadores (CombatStyles.PvP): [humanoid] = { attackers = { [Player] = os.clock() },
-- immuneUntil, combo (dano seguido), comboAt }. Recarga do quebra-combo por jogador (sobrevive ao renascer).
local pvp = {}
local breakerReadyAt = {}

local function now()
	return workspace:GetServerTimeNow()
end

-- Efeito visual para todos os clientes (CombatFX.client.luau). except: jogador que já mostrou o efeito sozinho
-- (quem atacou prevê o próprio acerto no cliente).
function CombatState.FX(kind, data, except)
	if except then
		for _, player in Players:GetPlayers() do
			if player ~= except then
				Remotes.CombatFX:FireClient(player, kind, data)
			end
		end
	else
		Remotes.CombatFX:FireAllClients(kind, data)
	end
end

-- Efeito da árvore de habilidades do jogador (atributos Tree<Efeito> escritos pelo PlayerData), 0 se não tem
local function treeEffect(player, key)
	local value = player:GetAttribute("Tree" .. key)
	return if type(value) == "number" then value else 0
end

-- Guarda máxima do estilo com o bônus da árvore ("Guarda firme")
local function maxGuardFor(player, blockCfg)
	return math.floor(blockCfg.MaxGuard * (1 + treeEffect(player, "GuardMax")) + 0.5)
end

local function publishGuard(player, state)
	local rounded = math.floor(state.guard + 0.5)
	if player:GetAttribute("Guard") ~= rounded then
		player:SetAttribute("Guard", rounded)
	end
	if player:GetAttribute("MaxGuard") ~= state.maxGuard then
		player:SetAttribute("MaxGuard", state.maxGuard)
	end
end

-- Estado do jogador. Renascer zera ações em andamento (guarda cheia, sem bloqueio nem carga).
function CombatState.Get(player)
	local state = states[player]
	if not state then
		state = {
			busyUntil = 0,
			lockUntil = 0,
			lastM1 = 0,
			combo = 0,
			ready = {},
			speed = {},
			guard = DEFAULT_BLOCK.MaxGuard,
			maxGuard = DEFAULT_BLOCK.MaxGuard,
			blockCfg = DEFAULT_BLOCK,
			lastGuardHit = 0,
			blockAllowedAt = 0,
			actionToken = 0, -- muda a cada ação longa (rajada, carga) ou cancelamento
		}
		-- Quem já saiu (um task.delay terminando depois do PlayerRemoving) ganha um estado descartável,
		-- senão a entrada ficaria para sempre na tabela
		if player.Parent ~= Players then
			return state
		end
		states[player] = state
	end
	if state.character ~= player.Character then
		state.character = player.Character
		state.combo = 0
		state.busyUntil = 0
		state.lockUntil = 0
		state.blocking = false
		state.broken = false
		state.charging = nil
		state.actionToken += 1
		table.clear(state.speed)
		state.guard = state.maxGuard
		publishGuard(player, state)
	end
	return state
end

-- Lentidão durante ações (bloqueio, carga, rajada). Vale o menor multiplicador ativo.
function CombatState.SetSpeed(player, source, multiplier)
	local state = CombatState.Get(player)
	state.speed[source] = multiplier
	local lowest
	for _, value in state.speed do
		lowest = if lowest then math.min(lowest, value) else value
	end
	local character = player.Character
	if character then
		character:SetAttribute("CombatSpeed", lowest)
	end
end

-- Não pode dar o próximo M1 (golpe em andamento, guarda levantada ou carregando)
function CombatState.IsBusy(player)
	local state = CombatState.Get(player)
	return now() < state.busyUntil or state.blocking or state.charging ~= nil
end

-- Não pode usar skill nem levantar a guarda (passada a janela de cancelamento do M1, já pode)
function CombatState.IsLocked(player)
	local state = CombatState.Get(player)
	return now() < state.lockUntil or state.blocking or state.charging ~= nil
end

-- Para o dash (DashService): quanto falta da trava de skills/block (0 se livre) e se está numa postura que não deixa
-- sair (guarda levantada ou carregando). A trava é contada da chegada do golpe no servidor; o dash vem com o atraso do
-- ping, então o DashService dá uma folga em cima de LockRemaining.
function CombatState.LockRemaining(player)
	return math.max(0, CombatState.Get(player).lockUntil - now())
end

function CombatState.InStance(player)
	local state = CombatState.Get(player)
	return state.blocking or state.charging ~= nil
end

-- busyUntil: trava o próximo M1; lockUntil (opcional, padrão igual): trava skills e block
function CombatState.SetBusy(player, untilTime, lockUntil)
	local state = CombatState.Get(player)
	state.busyUntil = math.max(state.busyUntil, untilTime)
	state.lockUntil = math.max(state.lockUntil, lockUntil or untilTime)
	player:SetAttribute("CombatBusyUntil", state.busyUntil)
	player:SetAttribute("CombatLockUntil", state.lockUntil)
end

function CombatState.IsReady(player, slot)
	return now() >= (CombatState.Get(player).ready[slot] or 0)
end

function CombatState.SetCooldown(player, slot, seconds)
	local readyAt = now() + seconds
	CombatState.Get(player).ready[slot] = readyAt
	player:SetAttribute(`Combat{slot}ReadyAt`, readyAt)
end

-- Hora (do servidor) em que o jogador começou o último M1. Os inimigos dão prioridade a quem bateu primeiro
-- (EnemyModule): o M1 do jogador só chega no marcador de impacto + ping, e sem isso o golpe do inimigo "fechava" antes.
function CombatState.MarkSwing(player)
	CombatState.Get(player).swingAt = now()
end

function CombatState.LastSwingAt(player)
	local state = states[player]
	return state and state.swingAt or nil
end

-- Próximo golpe do combo (1 a hits; hits = M1.Hits do estilo, 5 sem ele). O combo volta ao 1º depois de ComboReset
-- sem golpe.
function CombatState.NextCombo(player, comboReset, hits)
	local state = CombatState.Get(player)
	local t = now()
	state.combo = if t - state.lastM1 > comboReset or state.combo >= (hits or 5) then 1 else state.combo + 1
	state.lastM1 = t
	return state.combo
end

-- Chamado quando o jogador é atordoado (o CombatService cancela carga e rajada)
function CombatState.OnInterrupt(callback)
	table.insert(interruptHandlers, callback)
end

-- Chamado só após o DashService autorizar: invalida impactos pendentes antes de iniciar outra ação.
function CombatState.InterruptForDash(player)
	local state = CombatState.Get(player)
	state.m1Token = (state.m1Token or 0) + 1
	CombatState.SetSpeed(player, "M1", nil)
	for _, callback in interruptHandlers do callback(player) end
end

-- ================= Bloqueio =================

-- styleName vai no efeito BlockStart: o CombatFX só mexe os braços por código se o estilo não tiver animação de guarda
function CombatState.StartBlock(player, blockCfg, styleName)
	local state = CombatState.Get(player)
	local character = player.Character
	local t = now()
	if not character or state.blocking or state.broken or state.charging then return false end
	if t < state.lockUntil or t < state.blockAllowedAt then return false end
	if character:GetAttribute("Stunned") == true then return false end

	state.blockCfg = blockCfg
	local maxGuard = maxGuardFor(player, blockCfg)
	if state.maxGuard ~= maxGuard then
		state.guard = math.min(state.guard, maxGuard)
		state.maxGuard = maxGuard
	end
	if state.guard < blockCfg.MinGuard then return false end

	state.blocking = true
	state.blockStart = t
	character:SetAttribute("Blocking", true)
	CombatState.SetSpeed(player, "Block", blockCfg.SpeedMultiplier)
	CombatState.FX("BlockStart", { Character = character, Style = styleName })
	publishGuard(player, state)
	return true
end

function CombatState.StopBlock(player)
	local state = CombatState.Get(player)
	if not state.blocking then return end
	state.blocking = false
	state.blockAllowedAt = now() + state.blockCfg.RepressCooldown
	local character = player.Character
	if character then
		character:SetAttribute("Blocking", nil)
		CombatState.FX("BlockEnd", { Character = character })
	end
	CombatState.SetSpeed(player, "Block", nil)
end

local function rootOf(model)
	return model and model:FindFirstChild("HumanoidRootPart")
end

-- A vítima está bloqueando este golpe? Devolve "None", "Blocked", "Parried" ou "Broken".
-- opts.GuardBreak: quebra a guarda direto (soco carregado no máximo). opts.Unparryable: parry não funciona.
-- opts.Unblockable: atravessa a guarda (agarrão). opts.FromPosition: de onde o golpe veio, no lugar da posição atual de
-- quem atacou (o Avanço cortante termina atrás da vítima, mas o corte veio da frente).
function CombatState.TryBlock(victimModel, attackerModel, guardDamage, opts)
	local victimPlayer = Players:GetPlayerFromCharacter(victimModel)
	if not victimPlayer then return "None" end
	local state = states[victimPlayer]
	if not state or not state.blocking or state.character ~= victimModel then return "None" end
	local cfg = state.blockCfg
	opts = opts or {}
	if opts.Unblockable then return "None" end

	-- Golpe pelas costas atravessa a guarda
	local victimRoot, attackerRoot = rootOf(victimModel), rootOf(attackerModel)
	local from = if typeof(opts.FromPosition) == "Vector3" then opts.FromPosition elseif attackerRoot then attackerRoot.Position else nil
	if victimRoot and from then
		local offset = from - victimRoot.Position
		local flat = Vector3.new(offset.X, 0, offset.Z)
		if flat.Magnitude > 0.01 then
			local look = victimRoot.CFrame.LookVector
			if Vector3.new(look.X, 0, look.Z).Unit:Dot(flat.Unit) < cfg.FrontDot then
				return "None"
			end
		end
	end

	local t = now()

	-- Parry: guarda levantada há pouco tempo
	if not opts.Unparryable and t - state.blockStart <= cfg.ParryWindow + treeEffect(victimPlayer, "ParryWindow") then
		local attackerHumanoid = attackerModel and attackerModel:FindFirstChildOfClass("Humanoid")
		if attackerHumanoid then
			CombatState.Stun(attackerHumanoid, cfg.ParryStun, true)
		end
		local attackerPlayer = attackerModel and Players:GetPlayerFromCharacter(attackerModel)
		if attackerPlayer and states[attackerPlayer] then
			states[attackerPlayer].combo = 0
		end
		CombatState.FX("Parry", { Character = victimModel, Attacker = attackerModel })
		return "Parried"
	end

	state.lastGuardHit = t
	state.guard = math.max(0, state.guard - (if opts.GuardBreak then math.huge else guardDamage))
	if state.guard <= 0 then
		-- Guarda quebrada: fica sem bloquear e atordoado; a guarda volta pela metade depois
		state.guard = 0
		state.broken = true
		state.brokenUntil = t + cfg.BreakStun
		CombatState.StopBlock(victimPlayer)
		local humanoid = victimModel:FindFirstChildOfClass("Humanoid")
		if humanoid then
			CombatState.Stun(humanoid, cfg.BreakStun, true)
		end
		CombatState.FX("GuardBreak", { Character = victimModel })
		publishGuard(victimPlayer, state)
		return "Broken"
	end

	publishGuard(victimPlayer, state)
	-- Golpe previsto: quem atacou já mostrou o efeito de guarda no próprio cliente
	local attackerPlayer = opts.Predicted and attackerModel and Players:GetPlayerFromCharacter(attackerModel) or nil
	CombatState.FX("Blocked", { Character = victimModel, Attacker = attackerModel }, attackerPlayer)
	return "Blocked"
end

-- Fração do dano que passa quando o golpe foi bloqueado
function CombatState.BlockedDamage(victimModel)
	local victimPlayer = Players:GetPlayerFromCharacter(victimModel)
	local state = victimPlayer and states[victimPlayer]
	-- "Muralha" na árvore deixa passar menos dano
	local taken = if state then state.blockCfg.DamageTaken else DEFAULT_BLOCK.DamageTaken
	return if victimPlayer then math.max(0, taken - treeEffect(victimPlayer, "BlockTaken")) else taken
end

-- ================= Atordoamento =================

-- Quanto falta do atordoamento atual (0 se não está atordoado). Usado pelos chefes, que só param nos longos.
function CombatState.StunRemaining(humanoid)
	local state = stunned[humanoid]
	return if state then math.max(0, state.expires - os.clock()) else 0
end

local function pvpRecord(humanoid)
	local record = pvp[humanoid]
	if not record then
		record = { attackers = {}, immuneUntil = 0, combo = 0, comboAt = 0 }
		pvp[humanoid] = record
	end
	return record
end

-- Quantos jogadores diferentes bateram nessa vítima dentro de PvP.TeamWindow
local function attackerCount(record, clock)
	local count = 0
	for attacker, at in record.attackers do
		if clock - at > PVP.TeamWindow or attacker.Parent ~= Players then
			record.attackers[attacker] = nil
		else
			count += 1
		end
	end
	return count
end

-- Golpe de um jogador em outro (CombatRules.Damage, antes do dano). Devolve true se a vítima está apanhando de 2+
-- jogadores ao mesmo tempo (ataque em grupo: dano e atordoamento menores).
function CombatState.NoteAttacker(victimHumanoid, attackerPlayer)
	local record = pvpRecord(victimHumanoid)
	local clock = os.clock()
	record.attackers[attackerPlayer] = clock
	return attackerCount(record, clock) >= 2
end

local function setBreakerReady(player, ready)
	if (player:GetAttribute("ComboBreakerReady") == true) ~= ready then
		player:SetAttribute("ComboBreakerReady", if ready then true else nil)
	end
end

-- Dano de jogador que a vítima (jogador) levou: soma no combo seguido e libera o quebra-combo ao passar de
-- PvP.BreakerFraction da vida máxima (se a recarga já passou)
function CombatState.NoteComboDamage(victimHumanoid, dealt)
	local player = Players:GetPlayerFromCharacter(victimHumanoid.Parent)
	if not player or dealt <= 0 then return end
	local record = pvpRecord(victimHumanoid)
	record.combo += dealt
	record.comboAt = os.clock()
	if record.combo >= victimHumanoid.MaxHealth * PVP.BreakerFraction and now() >= (breakerReadyAt[player] or 0) then
		setBreakerReady(player, true)
	end
end

-- O dash do jogador pode quebrar o combo agora? (DashService, quando ele está atordoado)
function CombatState.CanBreakCombo(player)
	return player:GetAttribute("ComboBreakerReady") == true and now() >= (breakerReadyAt[player] or 0)
end

-- Usa o quebra-combo: tira o atordoamento, dá a imunidade e começa a recarga
function CombatState.BreakCombo(player)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid then return end
	breakerReadyAt[player] = now() + PVP.BreakerCooldown
	setBreakerReady(player, false)
	local record = pvpRecord(humanoid)
	record.combo = 0
	record.immuneUntil = os.clock() + PVP.StunImmunity
	local state = stunned[humanoid]
	if state then
		state.expires = 0
		state.heavy = false
	end
	character:SetAttribute("Stunned", nil)
	CombatState.FX("ComboBreaker", { Character = character })
end

-- force: atordoa mesmo com a imunidade e sem a redução do ataque em grupo (parry e quebra de guarda: punições
-- pela ação de quem é atordoado)
function CombatState.Stun(humanoid, duration, force)
	local character = humanoid.Parent
	if not character or humanoid.Health <= 0 then return end
	local player = Players:GetPlayerFromCharacter(character)
	local clock = os.clock()
	local heavy = duration >= PVP.HeavyStun
	if player and not force then
		local record = pvp[humanoid]
		if record then
			-- Imune logo depois de um atordoamento pesado ou do quebra-combo
			if clock < record.immuneUntil then return end
			if attackerCount(record, clock) >= 2 then
				duration *= PVP.TeamStun
			end
		end
	end
	local state = stunned[humanoid]
	if not state then
		state = {
			character = character,
			expires = 0,
			isPlayer = player ~= nil,
			walkSpeed = humanoid.WalkSpeed,
			jumpPower = humanoid.JumpPower,
			jumpHeight = humanoid.JumpHeight,
		}
		stunned[humanoid] = state
	end
	state.expires = math.max(state.expires, clock + duration)
	if heavy then
		state.heavy = true
	end
	character:SetAttribute("Stunned", true)
	if not state.isPlayer then
		humanoid.WalkSpeed = 0
		humanoid.JumpPower = 0
		humanoid.JumpHeight = 0
	end

	-- Jogador atordoado perde a guarda levantada, a carga e o combo
	if player then
		local combat = states[player]
		if combat and combat.character == character then
			combat.combo = 0
			CombatState.StopBlock(player)
			for _, callback in interruptHandlers do
				task.spawn(callback, player)
			end
		end
	end
end

-- Um único relógio restaura o stun e regenera a guarda
local guardClock = 0
RunService.Heartbeat:Connect(function(dt)
	local clock = os.clock()
	for humanoid, state in stunned do
		if not humanoid.Parent or humanoid.Health <= 0 or clock >= state.expires then
			stunned[humanoid] = nil
			if state.character.Parent then state.character:SetAttribute("Stunned", nil) end
			if humanoid.Parent and not state.isPlayer then
				humanoid.WalkSpeed = state.walkSpeed
				humanoid.JumpPower = state.jumpPower
				humanoid.JumpHeight = state.jumpHeight
			end
			-- Jogador saindo de um atordoamento pesado fica um pouco imune (não recomeça o combo na hora)
			if state.isPlayer and state.heavy and humanoid.Parent and humanoid.Health > 0 then
				pvpRecord(humanoid).immuneUntil = clock + PVP.StunImmunity
			end
		end
	end
	-- Combo seguido zera depois de BreakerGap sem apanhar e sem atordoamento (e o quebra-combo some com ele)
	for humanoid, record in pvp do
		if not humanoid.Parent or humanoid.Health <= 0 then
			pvp[humanoid] = nil
			local player = humanoid.Parent and Players:GetPlayerFromCharacter(humanoid.Parent)
			if player then setBreakerReady(player, false) end
		elseif record.combo > 0 and not stunned[humanoid] and clock - record.comboAt > PVP.BreakerGap then
			record.combo = 0
			local player = Players:GetPlayerFromCharacter(humanoid.Parent)
			if player then setBreakerReady(player, false) end
		end
	end

	guardClock += dt
	if guardClock < 0.1 then return end
	local elapsed = guardClock
	guardClock = 0
	local t = now()
	for player, state in states do
		local cfg = state.blockCfg
		-- Guarda máxima acompanha a árvore (desbloqueou ou resetou "Guarda firme")
		local maxGuard = maxGuardFor(player, cfg)
		if state.maxGuard ~= maxGuard then
			state.maxGuard = maxGuard
			state.guard = math.min(state.guard, maxGuard)
			publishGuard(player, state)
		end
		if state.broken then
			if t >= state.brokenUntil then
				state.broken = false
				state.guard = state.maxGuard * cfg.RefillAfterBreak
				publishGuard(player, state)
			end
		elseif not state.blocking and state.guard < state.maxGuard and t - state.lastGuardHit >= cfg.RegenDelay then
			local regen = cfg.GuardRegen * (1 + treeEffect(player, "GuardRegen")) -- "Recuperação" na árvore
			state.guard = math.min(state.maxGuard, state.guard + regen * elapsed)
			publishGuard(player, state)
		end
	end
end)

Players.PlayerRemoving:Connect(function(player)
	states[player] = nil
	breakerReadyAt[player] = nil
end)

return CombatState
