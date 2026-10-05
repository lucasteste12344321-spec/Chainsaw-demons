-- Treino com o Treinador (missões da esquiva; NPCId "Treinador" no QuestData). O NPC posicionado no mapa fica parado;
-- quem luta é uma cópia dele (ou do StarterCharacter, se o modelo do NPC não for um R6 com Humanoid), com a IA do
-- EnemyModule, que só ataca quem pediu o treino. Só quem pediu acerta a cópia (atributo TrainingFor, CombatRules).
-- Começa pelo botão TREINAR/DUELAR do diálogo (Remotes.QuestAction "Train", QuestModule). Dois modos:
--   "Spar": golpes com dano baixo; cada golpe que chega no jogador (pegou, bloqueou ou desviou) conta no objetivo Spar.
--           A cópia não morre (a vida volta) e o treino para se a vida do jogador cair abaixo de STOP_HEALTH.
--   "Duel": duelo de verdade (mais vida e dano, EnemyData DueloTreinador); derrotar a cópia conta no objetivo Duel.
-- Os dois acabam ao completar o objetivo, morrer, se afastar do NPC (MAX_DISTANCE) ou passar do tempo (SESSION_TIME).
-- A cópia não dá XP, Gold nem conta em missão de abate.
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")
local StarterPlayer = game:GetService("StarterPlayer")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local EnemyModule = require(ServerScriptService:WaitForChild("EnemyModule"))
local PlayerData = require(ServerScriptService:WaitForChild("PlayerData"))
local StatConfig = require(ReplicatedStorage:WaitForChild("StatConfig"))

local TrainerService = {}

local NPC_TAG = "QuestGiver"
local SESSION_TIME = { Spar = 150, Duel = 180 }
local MAX_DISTANCE = 70 -- do NPC
local STOP_HEALTH = 0.25 -- treino (Spar): para com a vida do jogador abaixo dessa fração
local SPAWN_DISTANCE = 6 -- a cópia nasce entre o NPC e o jogador, a essa distância do NPC

local sessions = {} -- [player] = sessão

local function npcModel(npcId)
	for _, model in CollectionService:GetTagged(NPC_TAG) do
		if model:IsDescendantOf(workspace) and model:GetAttribute("NPCId") == npcId then
			return model
		end
	end
	return nil
end

local function npcRoot(model)
	local root = model:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then return root end
	if model:IsA("Model") and model.PrimaryPart then return model.PrimaryPart end
	return model:FindFirstChildWhichIsA("BasePart", true)
end

-- Modelo de onde sai a cópia: o próprio NPC, se for um personagem R6 (as animações de luta são R6); senão o
-- StarterCharacter (o boneco liso do jogo)
local function sourceModel(npc)
	local humanoid = npc:FindFirstChildOfClass("Humanoid")
	if humanoid and humanoid.RigType == Enum.HumanoidRigType.R6 and npc:FindFirstChild("HumanoidRootPart") then
		return npc
	end
	return StarterPlayer:FindFirstChild("StarterCharacter")
end

-- Cópia limpa para o EnemyModule clonar: sem a tag e o atributo de NPC de missão (senão viraria outro NPC com
-- ProximityPrompt), sem scripts nem prompts. O nome casa com o kit EnemyKits.TreinadorTreino.
local function buildTemplate(source)
	local archivable = source.Archivable
	source.Archivable = true
	local template = source:Clone()
	source.Archivable = archivable
	if not template then return nil end
	template.Name = "TreinadorTreino"
	for _, item in { template, table.unpack(template:GetDescendants()) } do
		for _, tag in CollectionService:GetTags(item) do
			CollectionService:RemoveTag(item, tag)
		end
		if item:IsA("LuaSourceContainer") or item:IsA("ProximityPrompt") then
			item:Destroy()
		end
	end
	template:SetAttribute("NPCId", nil)
	template:SetAttribute("IdleAnimation", nil)
	return template
end

-- Progresso do objetivo de treino da missão (atual, total), ou nil se a missão não está mais ativa
local function objectiveProgress(player, questId, objectiveType)
	local QuestModule = require(ServerScriptService:WaitForChild("QuestModule"))
	return QuestModule.ObjectiveProgress(player, questId, objectiveType)
end

local function finish(player, message)
	local session = sessions[player]
	if not session then return end
	sessions[player] = nil
	session.Ended = true
	local enemy = session.Enemy
	local humanoid = enemy and enemy:FindFirstChildOfClass("Humanoid")
	-- Morta (duelo vencido): o EnemyModule tira o corpo; viva: some agora
	if enemy and enemy.Parent and not (humanoid and humanoid.Health <= 0) then
		enemy:Destroy()
	end
	if message and player.Parent then
		PlayerData.Notify(player, "Treinador", message, 5)
	end
end

function TrainerService.IsTraining(player)
	return sessions[player] ~= nil
end

-- Começa o treino (mode "Spar") ou o duelo ("Duel") da missão questId com o NPC npcId. Sem questId (comando de admin
-- /treinador) não conta em missão nenhuma e só acaba por tempo, distância, vida baixa ou morte.
function TrainerService.Start(player, mode, npcId, questId)
	if mode ~= "Spar" and mode ~= "Duel" then return false end
	if sessions[player] then
		PlayerData.Notify(player, "Treinador", "Você já está treinando.", 3)
		return false
	end
	local npc = npcModel(npcId)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not npc or not root or not humanoid or humanoid.Health <= 0 then return false end
	local anchor = npcRoot(npc)
	local source = sourceModel(npc)
	if not anchor or not source then
		warn("[TrainerService] Sem modelo para a cópia do Treinador (nem o NPC R6 nem o StarterCharacter)")
		return false
	end
	local template = buildTemplate(source)
	if not template then return false end

	-- Entre o NPC e o jogador, no chão
	local away = root.Position - anchor.Position
	local flat = Vector3.new(away.X, 0, away.Z)
	flat = if flat.Magnitude > 0.1 then flat.Unit else anchor.CFrame.LookVector
	local spot = anchor.Position + flat * SPAWN_DISTANCE
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { npc, character }
	params.RespectCanCollide = true
	local floor = workspace:Raycast(spot + Vector3.new(0, 6, 0), Vector3.new(0, -30, 0), params)
	local position = if floor then floor.Position + Vector3.new(0, 3, 0) else Vector3.new(spot.X, root.Position.Y, spot.Z)

	local session = { Mode = mode, QuestId = questId, NPC = npc, Started = os.clock() }
	sessions[player] = session
	local level = math.clamp(PlayerData.GetLevel(player), 10, StatConfig.MaxLevel)
	local enemy = EnemyModule.SpawnEnemy(template, CFrame.lookAt(position, Vector3.new(root.Position.X, position.Y, root.Position.Z)), {
		EnemyType = if mode == "Duel" then "DueloTreinador" else "TreinoTreinador",
		Level = level,
		OnlyTarget = player,
		IgnoreAggroLimit = true,
		-- Sem XP, Gold nem missão de abate; no duelo, derrotar a cópia é o objetivo
		GiveRewards = function(enemyHumanoid)
			if mode == "Duel" and not session.Ended and enemyHumanoid:GetAttribute("LastAttacker") == player.UserId then
				if questId then
					local QuestModule = require(ServerScriptService:WaitForChild("QuestModule"))
					QuestModule.OnDuelWon(player)
				end
				finish(player, "Duelo vencido! Volte a falar comigo.")
			end
		end,
		-- Cada golpe da cópia que chega no jogador conta no treino
		OnStrike = function()
			if mode ~= "Spar" or session.Ended or not questId then return end
			local QuestModule = require(ServerScriptService:WaitForChild("QuestModule"))
			QuestModule.OnSparHit(player)
			local current, total = objectiveProgress(player, questId, "Spar")
			if not current or current >= total then
				finish(player, "Treino concluído! Bom trabalho.")
			end
		end,
	})
	template:Destroy()
	if not enemy then
		sessions[player] = nil
		return false
	end
	session.Enemy = enemy
	enemy:SetAttribute("TrainingFor", player.UserId)
	-- No treino a cópia não morre: marcada como boneco de treino, não dá maestria (senão viraria farm) e o Kon não devora
	if mode == "Spar" then
		enemy:SetAttribute("TrainingDummy", player.UserId)
	end

	-- No treino a cópia não morre (a vida volta abaixo da metade). Na primeira vez avisa, para não parecer bug.
	local enemyHumanoid = enemy:FindFirstChildOfClass("Humanoid")
	if mode == "Spar" and enemyHumanoid then
		local warned = false
		enemyHumanoid.HealthChanged:Connect(function(health)
			if health > 0 and health < enemyHumanoid.MaxHealth * 0.5 then
				enemyHumanoid.Health = enemyHumanoid.MaxHealth
				if not warned and not session.Ended then
					warned = true
					PlayerData.Notify(player, "Treinador", "No treino eu não caio: aguente meus golpes (desviar também conta).", 5)
				end
			end
		end)
	end

	PlayerData.Notify(player, "Treinador", if mode == "Duel"
		then "Duelo! Me derrote sem sair daqui."
		else "Treino! Aguente meus golpes. Desviar também conta.", 5)

	-- Fim por morte, distância, tempo, vida baixa (treino) ou missão que não está mais ativa
	task.spawn(function()
		while sessions[player] == session do
			task.wait(0.25)
			if sessions[player] ~= session then break end
			local currentCharacter = player.Character
			local currentRoot = currentCharacter and currentCharacter:FindFirstChild("HumanoidRootPart")
			local currentHumanoid = currentCharacter and currentCharacter:FindFirstChildOfClass("Humanoid")
			if not player.Parent then
				finish(player, nil)
			elseif not currentRoot or not currentHumanoid or currentHumanoid.Health <= 0 or currentCharacter ~= character then
				finish(player, if mode == "Duel" then "Você caiu no duelo. Descanse e tente de novo." else "Treino interrompido.")
			elseif not enemy.Parent then
				finish(player, nil)
			elseif (currentRoot.Position - anchor.Position).Magnitude > MAX_DISTANCE then
				finish(player, "Você se afastou demais. Treino encerrado.")
			elseif os.clock() - session.Started > SESSION_TIME[mode] then
				finish(player, "O tempo acabou. Fale comigo para tentar de novo.")
			elseif mode == "Spar" and currentHumanoid.Health < currentHumanoid.MaxHealth * STOP_HEALTH then
				finish(player, "Chega por hoje: recupere a vida e volte para continuar.")
			elseif questId and not objectiveProgress(player, questId, mode) then
				finish(player, nil)
			end
		end
	end)
	return true
end

Players.PlayerRemoving:Connect(function(player)
	finish(player, nil)
end)

return TrainerService
