-- Recompensa por derrotar jogadores de outro time (PvP livre): XP, Gold e progresso nas missões "KillPlayer".
-- Quem levou o crédito é o LastAttacker que o CombatRules (estilos de combate e poderes) marca no Humanoid da vítima.
-- Abate de alguém do mesmo time (possível com a proteção de aliados desligada) não dá recompensa nem conta
-- para missões.
local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")

local PlayerData = require(ServerScriptService:WaitForChild("PlayerData"))
local QuestModule = require(ServerScriptService:WaitForChild("QuestModule"))

local CREDIT_WINDOW = 15 -- segundos entre o último dano e a morte para o abate contar
local REPEAT_COOLDOWN = 120 -- segundos até derrotar a MESMA vítima contar de novo (evita farm combinado)
local SWEEP_INTERVAL = 60 -- segundos entre as limpezas dos pares cujo cooldown já passou
-- Além disso, nas missões PvP cada vítima só conta uma vez por missão (QuestModule.OnPlayerKilled)

-- XP de um abate ≈ dois inimigos do level da vítima (ver EnemyData: 15 + 10L cada)
local function xpFor(victimLevel)
	return 30 + 20 * victimLevel
end

local function goldFor(victimLevel)
	return 10 + 3 * victimLevel
end

local lastRewarded = {} -- [killerUserId] = { [victimUserId] = os.clock() }

-- Apaga os pares cujo cooldown já passou (eles não bloqueiam mais nada), senão a tabela cresce enquanto o
-- servidor estiver aberto. Não apaga quando o jogador sai: sair e voltar não pode zerar o cooldown.
local function sweepExpired()
	local now = os.clock()
	for killerId, history in lastRewarded do
		for victimId, last in history do
			if now - last >= REPEAT_COOLDOWN then
				history[victimId] = nil
			end
		end
		if next(history) == nil then
			lastRewarded[killerId] = nil
		end
	end
end

local function onCharacter(victim, character)
	local humanoid = character:WaitForChild("Humanoid", 10)
	if not humanoid then return end

	-- O CombatRules marca LastAttacker antes de cada golpe. Aqui a marca é lida e apagada a cada dano,
	-- então ela só existe de novo se outro golpe acontecer (dano de queda ou de inimigo não renova o crédito).
	local creditId, creditAt = nil, 0
	local function consumeAttacker()
		local attackerId = humanoid:GetAttribute("LastAttacker")
		if type(attackerId) == "number" then
			creditId, creditAt = attackerId, os.clock()
			humanoid:SetAttribute("LastAttacker", nil)
		end
	end

	local lastHealth = humanoid.Health
	humanoid.HealthChanged:Connect(function(health)
		if health < lastHealth then
			consumeAttacker()
		end
		lastHealth = health
	end)

	humanoid.Died:Connect(function()
		consumeAttacker() -- o Died pode chegar antes do HealthChanged do golpe final
		if not creditId or creditId == victim.UserId or os.clock() - creditAt > CREDIT_WINDOW then return end

		local killer = Players:GetPlayerByUserId(creditId)
		if not killer or (killer.Team ~= nil and killer.Team == victim.Team) then return end

		local history = lastRewarded[killer.UserId]
		if not history then
			history = {}
			lastRewarded[killer.UserId] = history
		end
		local now = os.clock()
		local last = history[victim.UserId]
		if last and now - last < REPEAT_COOLDOWN then
			PlayerData.Notify(killer, "Abate", `Você derrotou {victim.DisplayName} há pouco tempo. Esse abate não dá recompensa.`, 3)
			return
		end
		history[victim.UserId] = now

		local victimLevel = PlayerData.GetLevel(victim)
		PlayerData.AddXP(killer, xpFor(victimLevel))
		PlayerData.AddGold(killer, goldFor(victimLevel))
		PlayerData.Notify(killer, "Abate!", `Você derrotou {victim.DisplayName} (Lv. {victimLevel}).`, 3)
		QuestModule.OnPlayerKilled(killer, victim)
	end)
end

local function onPlayer(player)
	player.CharacterAdded:Connect(function(character)
		onCharacter(player, character)
	end)
	if player.Character then
		task.spawn(onCharacter, player, player.Character)
	end
end

Players.PlayerAdded:Connect(onPlayer)
for _, player in Players:GetPlayers() do
	onPlayer(player)
end

task.spawn(function()
	while true do
		task.wait(SWEEP_INTERVAL)
		sweepExpired()
	end
end)
