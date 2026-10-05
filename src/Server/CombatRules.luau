-- Regras de dano compartilhadas pelos estilos de combate, pelos poderes dos caminhos e pelos inimigos.
-- Quem pode acertar quem (PvP livre com proteção de aliados), bônus de Força, redução por Defesa,
-- esquiva (DodgeUntil / DodgeChance), bloqueio/parry (CombatState.TryBlock), roubo de vida e a marca
-- LastAttacker que dá XP/Gold/missões.
-- Não pode dar require no PathModule nem no QuestModule (o caminho é lido dos atributos do player).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PathData = require(ReplicatedStorage:WaitForChild("PathData"))
local DodgeData = require(ReplicatedStorage:WaitForChild("DodgeData"))
local Remotes = require(ReplicatedStorage:WaitForChild("Remotes"))
local StatConfig = require(ReplicatedStorage:WaitForChild("StatConfig"))
local PlayerData = require(script.Parent:WaitForChild("PlayerData"))
local CombatState = require(script.Parent:WaitForChild("CombatState"))

local CombatRules = {}

local rng = Random.new()

local function isInstanceOf(value, className)
	return typeof(value) == "Instance" and value:IsA(className)
end

-- Número válido e positivo (rejeita NaN e infinito)
local function isPositiveNumber(value)
	return type(value) == "number" and value == value and value > 0 and value < math.huge
end

-- Inimigo controlado pelo servidor: Model dentro de workspace.Enemies com o atributo Enemy = true
function CombatRules.IsEnemyNPC(model)
	if not isInstanceOf(model, "Model") then return false end
	local enemies = workspace:FindFirstChild("Enemies")
	return enemies ~= nil and model:IsDescendantOf(enemies) and model:GetAttribute("Enemy") == true
end

-- Proteção de aliados: ligada por padrão (atributo ainda não escrito conta como ligado)
local function hasAllyProtection(player)
	return player:GetAttribute("AllyProtection") ~= false
end

function CombatRules.CanDamage(attacker, victimModel)
	if not isInstanceOf(attacker, "Player") or not isInstanceOf(victimModel, "Model") then return false end

	local humanoid = victimModel:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then return false end
	if victimModel == attacker.Character then return false end
	if victimModel:FindFirstChildOfClass("ForceField") then return false end
	-- Cópia do Treinador (TrainerService): só quem pediu o treino acerta
	local trainingFor = victimModel:GetAttribute("TrainingFor")
	if trainingFor ~= nil and trainingFor ~= attacker.UserId then return false end

	local victimPlayer = Players:GetPlayerFromCharacter(victimModel)
	if victimPlayer then
		if victimPlayer == attacker then return false end
		-- PvP livre, menos entre membros do mesmo time quando um dos dois ligou a proteção
		if attacker.Team ~= nil and victimPlayer.Team == attacker.Team
			and (hasAllyProtection(attacker) or hasAllyProtection(victimPlayer)) then
			return false
		end
		return true
	end

	-- Não é jogador: só inimigos podem levar dano (NPCs de missão, por exemplo, não)
	return CombatRules.IsEnemyNPC(victimModel)
end

-- Consulta de área (GetPartBoundsIn*) que só enxerga quem pode levar dano: os inimigos (workspace.Enemies) e os
-- personagens dos jogadores, menos o de quem ataca. Antes cada consulta passava também por todas as peças do mapa
-- dentro da área (a Rajada faz uma a cada 0,12 s).
function CombatRules.TargetOverlap(attackerCharacter)
	local include = {}
	local enemies = workspace:FindFirstChild("Enemies")
	if enemies then
		table.insert(include, enemies)
	end
	for _, player in Players:GetPlayers() do
		local character = player.Character
		if character and character ~= attackerCharacter then
			table.insert(include, character)
		end
	end
	local overlap = OverlapParams.new()
	overlap.FilterType = Enum.RaycastFilterType.Include
	overlap.FilterDescendantsInstances = include
	return overlap
end

-- Número de dano e contador de acertos de quem bateu (DamageNumbers.client): só para ele
local function notifyDamage(attacker, victimModel, dealt, result)
	if dealt <= 0 and result ~= "Blocked" then return end
	Remotes.CombatDamage:FireClient(attacker, victimModel, math.floor(dealt + 0.5), result)
end

-- Esquiva: buff DodgeUntil no personagem (avanço da Katana) ou a chance: passivos do caminho + TreeDodgeChance (clã,
-- itens e o treino do Treinador, somados pelo PlayerData), com o teto DodgeData.MaxChance. Devolve (desviou, pela chance):
-- só o desvio pela chance tem animação, passo e os bônus do nível (onDodged).
local function dodges(victimModel, victimPlayer)
	local dodgeUntil = victimModel:GetAttribute("DodgeUntil")
	if type(dodgeUntil) == "number" and workspace:GetServerTimeNow() < dodgeUntil then
		return true, false
	end
	if victimPlayer then
		-- Chance fixa de admin (/esquiva <n>%, PlayerData.SetDodgeForced): vale no lugar da soma e sem o teto
		local forced = victimPlayer:GetAttribute("DodgeForced")
		local chance
		if type(forced) == "number" then
			chance = forced
		else
			local passives = PathData.Passives(PathData.FromPlayer(victimPlayer))
			local treeChance = victimPlayer:GetAttribute("TreeDodgeChance")
			chance = (passives.DodgeChance or 0) + (if type(treeChance) == "number" then treeChance else 0)
			chance = math.min(chance, DodgeData.MaxChance)
		end
		if chance > 0 and rng:NextNumber() < chance then
			return true, true
		end
	end
	return false, false
end

-- Lado do desvio em relação a quem desvia: golpe vindo da direita vai para a esquerda e vice-versa; de frente ou de
-- trás, um lado qualquer (ou para trás)
local function dodgeSide(victimModel, attackerModel)
	local victimRoot = victimModel:FindFirstChild("HumanoidRootPart")
	local attackerRoot = attackerModel and attackerModel:FindFirstChild("HumanoidRootPart")
	if victimRoot and attackerRoot then
		local offset = attackerRoot.Position - victimRoot.Position
		local flat = Vector3.new(offset.X, 0, offset.Z)
		local right = victimRoot.CFrame.RightVector
		right = Vector3.new(right.X, 0, right.Z)
		if flat.Magnitude > 0.1 and right.Magnitude > 0.01 then
			local side = right.Unit:Dot(flat.Unit)
			if side > 0.45 then return "Left" end
			if side < -0.45 then return "Right" end
		end
	end
	-- De frente ou de trás: um lado qualquer (para trás só se tiver a animação)
	local roll = rng:NextNumber()
	if DodgeData.Animations.Back > 0 and roll < 0.3 then
		return "Back"
	end
	return if rng:NextNumber() < 0.5 then "Left" else "Right"
end

-- Desviou: efeito para todos (Side só no desvio pela chance: o cliente de quem desviou toca a animação e dá o passo) e
-- os bônus do nível de esquiva (contra-golpe e desvio rápido, atributos lidos pelo CombatService e pelo movimento)
local function onDodged(victimModel, victimPlayer, attackerModel, byChance)
	CombatState.FX("Dodge", {
		Character = victimModel,
		Attacker = attackerModel,
		Side = if byChance then dodgeSide(victimModel, attackerModel) else nil,
	})
	if not byChance or not victimPlayer then return end
	local level = DodgeData.Get(victimPlayer:GetAttribute("DodgeLevel"))
	if not level then return end
	local now = workspace:GetServerTimeNow()
	if level.Counter then
		victimPlayer:SetAttribute("DodgeCounterUntil", now + DodgeData.Counter.Window)
	end
	if level.Rush then
		victimPlayer:SetAttribute("DodgeRushUntil", now + DodgeData.Rush.Time)
	end
end

-- Contra-golpe (DodgeData.Counter): o bônus de dano se o jogador desviou há pouco (e gasta o bônus), senão 0
function CombatRules.ConsumeCounter(player)
	local untilTime = player:GetAttribute("DodgeCounterUntil")
	if type(untilTime) ~= "number" then return 0 end
	player:SetAttribute("DodgeCounterUntil", nil)
	if workspace:GetServerTimeNow() > untilTime then return 0 end
	return DodgeData.Counter.Bonus
end

-- Aplica o dano e devolve quanto de vida a vítima realmente perdeu
local function applyDamage(humanoid, damage)
	local before = humanoid.Health
	humanoid:TakeDamage(damage)
	return math.max(0, before - humanoid.Health)
end

-- Dano de um jogador (estilo de combate ou poder). Devolve (dano causado, resultado), com resultado
-- "Hit", "Blocked", "Broken" (quebrou a guarda), "Parried" ou "Dodged" (nil se o golpe não valia).
-- opts (todos opcionais):
--   ScaleWithForca: soma StatConfig.DamageBonus(Força do atacante) ao dano base, vezes ForcaScale (padrão 1)
--   GuardDamage: quanto gasta da guarda de quem bloqueia (padrão 60% do dano base)
--   GuardBreak: quebra a guarda direto; Unparryable: parry não funciona; Unblockable: atravessa a guarda;
--   FromPosition: de onde o golpe veio, para a guarda (padrão: onde quem atacou está)
function CombatRules.Damage(attacker, victimHumanoid, amount, opts)
	if not isInstanceOf(attacker, "Player") or not isInstanceOf(victimHumanoid, "Humanoid") then return 0 end
	if not isPositiveNumber(amount) then return 0 end

	local victimModel = victimHumanoid.Parent
	if not CombatRules.CanDamage(attacker, victimModel) then return 0 end

	local damage = amount
	if type(opts) == "table" and opts.ScaleWithForca then
		local scale = if type(opts.ForcaScale) == "number" then opts.ForcaScale else 1
		damage += StatConfig.DamageBonus(PlayerData.GetStat(attacker, "Forca")) * scale
	end

	local victimPlayer = Players:GetPlayerFromCharacter(victimModel)
	if victimPlayer then
		damage *= 1 - StatConfig.DamageReduction(PlayerData.GetStat(victimPlayer, "Defesa"))
	end

	local dodged, byChance = dodges(victimModel, victimPlayer)
	if dodged then
		onDodged(victimModel, victimPlayer, attacker.Character, byChance)
		return 0, "Dodged"
	end

	-- Guarda levantada: parry anula, bloqueio deixa passar só uma parte (e gasta a guarda)
	local guardDamage = if type(opts) == "table" and isPositiveNumber(opts.GuardDamage)
		then opts.GuardDamage
		else math.max(5, amount * 0.6)
	local block = CombatState.TryBlock(victimModel, attacker.Character, guardDamage, opts)
	if block == "Parried" then
		return 0, block
	elseif block ~= "None" then
		damage *= CombatState.BlockedDamage(victimModel)
	end

	-- A marca precisa existir antes de TakeDamage disparar Humanoid.Died (XP, Gold e missões)
	victimHumanoid:SetAttribute("LastAttacker", attacker.UserId)
	local dealt = applyDamage(victimHumanoid, damage)

	-- Roubo de vida do atacante (Infernal do Sangue), sem passar da vida máxima
	if dealt > 0 then
		local lifeSteal = PathData.Passives(PathData.FromPlayer(attacker)).LifeSteal or 0
		local attackerHumanoid = attacker.Character and attacker.Character:FindFirstChildOfClass("Humanoid")
		if lifeSteal > 0 and attackerHumanoid and attackerHumanoid.Health > 0 then
			attackerHumanoid.Health = math.min(attackerHumanoid.MaxHealth, attackerHumanoid.Health + dealt * lifeSteal)
		end
	end

	local result = if block == "None" then "Hit" else block
	notifyDamage(attacker, victimModel, dealt, result)
	return dealt, result
end

-- Dano de inimigo (NPC) em jogador: aplica Defesa, esquiva e bloqueio, sem marcar LastAttacker.
-- npcModel (opcional) é quem atacou: define de que lado veio o golpe e quem leva o atordoamento do parry.
function CombatRules.DamageFromNPC(victimHumanoid, amount, npcModel)
	if not isInstanceOf(victimHumanoid, "Humanoid") or victimHumanoid.Health <= 0 then return 0 end
	if not isPositiveNumber(amount) then return 0 end

	local victimModel = victimHumanoid.Parent
	if not isInstanceOf(victimModel, "Model") then return 0 end
	if victimModel:FindFirstChildOfClass("ForceField") then return 0 end

	local damage = amount
	local victimPlayer = Players:GetPlayerFromCharacter(victimModel)
	if victimPlayer then
		damage *= 1 - StatConfig.DamageReduction(PlayerData.GetStat(victimPlayer, "Defesa"))
	end

	local attackerModel = if isInstanceOf(npcModel, "Model") then npcModel else nil
	local dodged, byChance = dodges(victimModel, victimPlayer)
	if dodged then
		onDodged(victimModel, victimPlayer, attackerModel, byChance)
		return 0, "Dodged"
	end

	local block = CombatState.TryBlock(victimModel, attackerModel, math.max(8, amount * 1.5))
	if block == "Parried" then
		return 0, block
	elseif block ~= "None" then
		damage *= CombatState.BlockedDamage(victimModel)
	end

	return applyDamage(victimHumanoid, damage), if block == "None" then "Hit" else block
end

-- Stun pelo CombatState (atributo Stunned no personagem; stuns sobrepostos valem até o que acabar por último).
-- result: o 2º retorno de Damage/DamageFromNPC. Só "Hit" atordoa (golpe pelas costas atravessa a guarda e também
-- atordoa); "Blocked"/"Parried"/"Dodged" não, e "Broken" já atordoou na quebra da guarda.
-- Sem result (chamada antiga), quem está com a guarda levantada não é atordoado.
function CombatRules.Stun(humanoid, duration, result)
	if not isInstanceOf(humanoid, "Humanoid") or not isPositiveNumber(duration) then return end
	if result ~= nil then
		if result ~= "Hit" then return end
	else
		local character = humanoid.Parent
		if character and character:GetAttribute("Blocking") == true then return end
	end
	CombatState.Stun(humanoid, duration)
end

return CombatRules
