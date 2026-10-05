-- Missões: várias ativas ao mesmo tempo, cadeias com pré-requisitos, rotas por caminho e NPCs.
-- As definições ficam em QuestData. O estado de cada jogador fica no perfil do PlayerData (é salvo junto):
--   Quests.Active[questId] = { Progress = { n1, n2, ... }, Victims = { [tostring(userId)] = true }? }
--     (um número por objetivo; Victims = jogadores que já contaram nos objetivos KillPlayer desta missão)
--   Quests.Completed[questId] = quantas vezes completou
-- Fase 4 (docs/fase4-caminhos.md): o caminho do jogador ("None", "Hunter", "Fiend") é lido dos atributos que o
-- PathModule replica (PathData.FromPlayer). Missões com o campo Path só servem para esse caminho, e trocar de
-- caminho abandona as que não servem mais. A missão "Encruzilhada" libera a escolha de caminho.
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage:WaitForChild("Remotes"))
local PathData = require(ReplicatedStorage:WaitForChild("PathData"))
local CombatStyles = require(ReplicatedStorage:WaitForChild("CombatStyles"))
local PlayerData = require(script.Parent:WaitForChild("PlayerData"))
local PathModule = require(script.Parent:WaitForChild("PathModule"))
local ContractService = require(script.Parent:WaitForChild("ContractService"))
local EnemyData = require(script.Parent:WaitForChild("EnemyData"))
local QuestData = require(script.Parent:WaitForChild("QuestData"))
local WorldQuestData = require(script.Parent:WaitForChild("WorldQuestData"))
-- Register before indexing, validating or restoring saved quest progress.
WorldQuestData.Register(QuestData)

local QuestModule = {}

-- Ouvintes de progresso (missões diárias, DailyService): fn(player, kind, target). kind: "Kill" (target = tipo do
-- inimigo), "Fish" (peixe), "Power" (id do poder)
local listeners = {}
function QuestModule.Listen(callback)
	table.insert(listeners, callback)
end
local function emit(player, kind, target)
	for _, callback in listeners do
		task.spawn(callback, player, kind, target)
	end
end

local MAX_ACTIVE = 5 -- limite de missões ativas (as principais automáticas, Main = true, não ocupam vaga)
local NPC_TAG = "QuestGiver"
local NPC_RANGE = 20 -- distância máxima para falar com um NPC ou aceitar missão dele
local PATH_WAIT = 15 -- segundos esperando o PathModule publicar o atributo Path quando o jogador entra

local OBJECTIVE_TYPES = {
	Collect = true,
	Explore = true,
	Fish = true,
	WorldEvent = true,
	Kill = true,
	KillPlayer = true,
	ReachLevel = true,
	TalkTo = true,
	UsePower = true,
	TakeHits = true, -- golpes de inimigo que chegaram no jogador (pegou, bloqueou ou desviou; EnemyModule)
	Spar = true, -- golpes do treino com o Treinador (TrainerService)
	Duel = true, -- duelo contra o Treinador vencido (TrainerService)
}

local DEFAULT_GREETINGS = {
	Available = "Tenho um trabalho para você.",
	Active = "E aí, já terminou o que eu pedi?",
	Idle = "Não tenho nada para você agora. Volte mais tarde.",
}

local questsById = {}
for index, quest in QuestData.Quests do
	if questsById[quest.Id] then
		warn(`[QuestModule] Id de missão repetido no QuestData: {quest.Id}`)
	end
	quest.Order = index
	questsById[quest.Id] = quest
end
QuestModule.Quests = questsById

-- Avisa no Output sobre erros de digitação no QuestData (não impede o jogo de rodar)
local function validateData()
	local function check(ok, message)
		if not ok then
			warn(`[QuestModule] {message}`)
		end
	end

	for _, quest in QuestData.Quests do
		local id = quest.Id
		for _, requiredId in quest.Requires or {} do
			check(questsById[requiredId] ~= nil, `{id}: Requires "{requiredId}" não existe`)
		end
		for _, otherId in quest.ExclusiveWith or {} do
			check(questsById[otherId] ~= nil, `{id}: ExclusiveWith "{otherId}" não existe`)
		end
		check(quest.Path == nil or PathData.Paths[quest.Path] ~= nil, `{id}: Path "{tostring(quest.Path)}" inválido`)
		check(quest.Giver == nil or QuestData.NPCs[quest.Giver] ~= nil, `{id}: Giver "{tostring(quest.Giver)}" sem nome em QuestData.NPCs`)

		local styleName = quest.Rewards and quest.Rewards.Style
		check(styleName == nil or CombatStyles.Styles[styleName] ~= nil, `{id}: o estilo "{tostring(styleName)}" não existe no CombatStyles`)

		local contractId = quest.Rewards and quest.Rewards.Contract
		if contractId then
			local contract = PathData.Contracts[contractId]
			check(contract ~= nil, `{id}: o contrato "{contractId}" não existe no PathData`)
			check(contract == nil or contract.Unlock == "Quest", `{id}: o contrato "{contractId}" não tem Unlock = "Quest"`)
		end

		for _, objective in quest.Objectives do
			check(OBJECTIVE_TYPES[objective.Type] == true, `{id}: tipo de objetivo "{tostring(objective.Type)}" desconhecido`)
			if objective.Type == "Kill" and objective.Target ~= nil then
				check(EnemyData[objective.Target] ~= nil, `{id}: o inimigo "{objective.Target}" não existe no EnemyData`)
			end
			if objective.Type == "TalkTo" then
				for _, npcId in objective.TargetList or { objective.Target } do
					check(QuestData.NPCs[npcId] ~= nil, `{id}: o NPC "{npcId}" não existe em QuestData.NPCs`)
				end
			end
		end
	end

	check(questsById[PathData.RequiredQuest] ~= nil, `a missão "{PathData.RequiredQuest}" (PathData.RequiredQuest) não existe no QuestData`)
end
validateData()

-- Jogadores cujo setup terminou (caminho conhecido). Antes disso as missões automáticas não são mexidas,
-- para um Caçador não receber missões de Humano comum só porque o atributo Path ainda não chegou.
local ready = {}
local pendingRevalidate = {}

local function getState(player)
	local profile = PlayerData.GetProfile(player)
	return profile and profile.Quests
end

local function teamName(player)
	return player.Team and player.Team.Name or nil
end

local function npcName(npcId)
	return QuestData.NPCs[npcId] or npcId
end

-- Missões ativas que ocupam vaga no limite (as principais, Main = true, não contam)
local function countActive(state)
	local count = 0
	for questId in state.Active do
		local quest = questsById[questId]
		if not (quest and quest.Main) then
			count += 1
		end
	end
	return count
end

local function isDone(quest, entry)
	for i, objective in quest.Objectives do
		if (entry.Progress[i] or 0) < objective.Amount then
			return false
		end
	end
	return true
end

-- A missão serve para o caminho e o time atuais do jogador?
local function fitsPlayer(player, quest)
	if quest.Team and teamName(player) ~= quest.Team then return false end
	if quest.Path then
		local path = PathData.FromPlayer(player)
		if path ~= quest.Path then return false end
	end
	return true
end

-- Recompensa Contract: só para Caçador com slot livre que ainda não tem esse contrato
local function canReceiveContract(player, contractId)
	if not PathData.Contracts[contractId] then return false end
	local path, contracts = PathData.FromPlayer(player)
	if path ~= "Hunter" or #contracts >= PathData.MaxContracts then return false end
	return table.find(contracts, contractId) == nil
end

function QuestModule.IsAvailable(player, quest)
	local state = getState(player)
	if not state or state.Active[quest.Id] then return false end
	if (state.Completed[quest.Id] or 0) > 0 and not quest.Repeatable then return false end
	if not fitsPlayer(player, quest) then return false end
	if PlayerData.GetLevel(player) < (quest.MinLevel or 1) then return false end
	for _, requiredId in quest.Requires or {} do
		if (state.Completed[requiredId] or 0) == 0 then return false end
	end
	for _, otherId in quest.ExclusiveWith or {} do
		if state.Active[otherId] or (state.Completed[otherId] or 0) > 0 then return false end
	end
	local contractId = quest.Rewards and quest.Rewards.Contract
	if contractId and not canReceiveContract(player, contractId) then return false end
	-- Quem já tem o estilo (ex.: ganhou por comando de admin) não recebe a missão que ensina ele
	local styleName = quest.Rewards and quest.Rewards.Style
	if styleName and PlayerData.HasStyle(player, styleName) then return false end
	-- Esquiva: quem já está nesse nível (ex.: comando de admin) pula a missão
	local dodgeLevel = quest.Rewards and quest.Rewards.DodgeLevel
	if dodgeLevel and PlayerData.GetDodgeLevel(player) >= dodgeLevel then return false end
	return true
end

function QuestModule.IsCompleted(player, questId)
	local state = getState(player)
	return state ~= nil and (state.Completed[questId] or 0) > 0
end

local function questView(quest, entry)
	local objectives = {}
	for i, objective in quest.Objectives do
		table.insert(objectives, {
			Text = objective.Text,
			Progress = entry and entry.Progress[i] or 0,
			Amount = objective.Amount,
			-- Para o minimapa marcar onde fica (zona do inimigo, NPC para falar)
			Type = objective.Type,
			Target = objective.Target,
			TargetList = objective.TargetList,
		})
	end
	return {
		Id = quest.Id,
		Name = quest.Name,
		Description = quest.Description,
		Objectives = objectives,
		Rewards = quest.Rewards or {},
		Giver = quest.Giver,
		GiverName = if quest.Giver then npcName(quest.Giver) else nil,
	}
end

local function sendState(player)
	local state = getState(player)
	if not state then return end

	local list = {}
	for questId, entry in state.Active do
		local quest = questsById[questId]
		if quest then
			table.insert(list, questView(quest, entry))
		end
	end
	table.sort(list, function(a, b)
		return questsById[a.Id].Order < questsById[b.Id].Order
	end)

	-- NPCs com alguma missão que o jogador pode pegar agora (o minimapa mostra "!" neles)
	local givers = {}
	for _, quest in QuestData.Quests do
		if quest.Giver and not table.find(givers, quest.Giver) and QuestModule.IsAvailable(player, quest) then
			table.insert(givers, quest.Giver)
		end
	end

	Remotes.QuestEvent:FireClient(player, { Action = "State", Quests = list, Givers = givers })
end

local function rewardText(rewards)
	local parts = {}
	if rewards.XP then table.insert(parts, `+{rewards.XP} XP`) end
	if rewards.Gold then table.insert(parts, `+{rewards.Gold} Gold`) end
	if rewards.StatusPoints then table.insert(parts, `+{rewards.StatusPoints} pontos de habilidade`) end
	if rewards.Contract then
		local contract = PathData.Contracts[rewards.Contract]
		local name = if contract then contract.DisplayName else rewards.Contract
		table.insert(parts, `contrato com o {name}`)
	end
	if rewards.Style then
		local style = CombatStyles.Styles[rewards.Style]
		table.insert(parts, `estilo {if style then style.DisplayName else rewards.Style}`)
	end
	if rewards.DodgeLevel then
		table.insert(parts, `Esquiva nível {rewards.DodgeLevel}`)
	end
	return table.concat(parts, ", ")
end

-- O PathModule avisa o jogador do sucesso ou do motivo da falha
local function grantContract(player, contractId)
	local ok, added, reason = pcall(PathModule.AddContract, player, contractId)
	if not ok then
		warn(`[QuestModule] PathModule.AddContract falhou: {added}`)
	elseif not added then
		warn(`[QuestModule] Contrato {contractId} não foi dado a {player.Name}: {tostring(reason)}`)
	end
end

local function complete(player, quest)
	local state = getState(player)
	if not state or not state.Active[quest.Id] then return end

	state.Active[quest.Id] = nil
	state.Completed[quest.Id] = (state.Completed[quest.Id] or 0) + 1

	local rewards = quest.Rewards or {}
	local text = rewardText(rewards)
	PlayerData.Notify(player, "Missão completa!", if text ~= "" then `{quest.Name}: {text}` else quest.Name, 5)
	if rewards.Gold then PlayerData.AddGold(player, rewards.Gold) end
	if rewards.StatusPoints then PlayerData.AddStatusPoints(player, rewards.StatusPoints) end
	if rewards.Contract then grantContract(player, rewards.Contract) end
	if rewards.Style then PlayerData.UnlockStyle(player, rewards.Style) end
	if rewards.DodgeLevel then
		PlayerData.SetDodgeLevel(player, math.max(PlayerData.GetDodgeLevel(player), rewards.DodgeLevel))
	end
	if rewards.XP then PlayerData.AddXP(player, rewards.XP) end
end

local function accept(player, quest)
	local state = getState(player)
	if not state then return end

	local progress = {}
	for i, objective in quest.Objectives do
		progress[i] = if objective.Type == "ReachLevel"
			then math.min(PlayerData.GetLevel(player), objective.Amount)
			else 0
	end
	local entry = { Progress = progress }
	state.Active[quest.Id] = entry
	PlayerData.Notify(player, if quest.Main then "Missão principal" else "Nova missão", quest.Name, 4)

	-- Ex.: "chegar ao level 3" quando já está no level 3
	if isDone(quest, entry) then
		complete(player, quest)
	end
end

-- Aceita todas as missões automáticas disponíveis. Repete porque completar uma pode liberar outras.
local function refreshAutoQuests(player)
	local state = getState(player)
	if not state or not ready[player] then return false end

	local anyAccepted = false
	for _ = 1, 10 do
		local accepted = false
		for _, quest in QuestData.Quests do
			if not quest.Giver
				and (quest.Main or countActive(state) < MAX_ACTIVE)
				and QuestModule.IsAvailable(player, quest)
			then
				accept(player, quest)
				accepted = true
			end
		end
		if not accepted then break end
		anyAccepted = true
	end
	return anyAccepted
end

-- O objetivo vale para este alvo? (Target exato, um da TargetList, ou qualquer um sem os dois)
local function matchesTarget(objective, value)
	if objective.Target ~= nil then
		return objective.Target == value
	end
	if type(objective.TargetList) == "table" then
		return table.find(objective.TargetList, value) ~= nil
	end
	return true
end

-- update(objective, current, entry) devolve o novo progresso do objetivo, ou nil se não se aplica.
-- entry é o estado salvo da missão ativa (Progress, Victims).
-- Um objetivo "TalkTo" só anda depois que os objetivos anteriores de outros tipos estiverem completos.
local function updateObjectives(player, update)
	local state = getState(player)
	if not state then return end

	local changed = false
	local finished = {}
	for questId, entry in state.Active do
		local quest = questsById[questId]
		if quest then
			local previousDone = true
			for i, objective in quest.Objectives do
				local current = entry.Progress[i] or 0
				local waiting = objective.Type == "TalkTo" and not previousDone
				if current < objective.Amount and not waiting then
					local new = update(objective, current, entry)
					if new and new ~= current then
						current = math.min(new, objective.Amount)
						entry.Progress[i] = current
						changed = true
					end
				end
				if objective.Type ~= "TalkTo" and current < objective.Amount then
					previousDone = false
				end
			end
			if isDone(quest, entry) then
				table.insert(finished, quest)
			end
		end
	end

	for _, quest in finished do
		complete(player, quest)
	end
	if #finished > 0 then
		refreshAutoQuests(player)
	end
	if changed or #finished > 0 then
		sendState(player)
	end
end

-- Inimigo derrotado (EnemyModule). enemyLevel é usado pelos objetivos com MinEnemyLevel.
function QuestModule.OnEnemyKilled(player, enemyType, enemyLevel)
	local level = if type(enemyLevel) == "number" then enemyLevel else 1
	emit(player, "Kill", enemyType)
	updateObjectives(player, function(objective, current)
		if objective.Type ~= "Kill" or not matchesTarget(objective, enemyType) then return nil end
		if objective.MinEnemyLevel and level < objective.MinEnemyLevel then return nil end
		return current + 1
	end)
end

-- Only trusted server systems call this; clients cannot submit objective progress.
function QuestModule.OnActivity(player, kind, target, uniqueId)
	if not WorldQuestData.ObjectiveTypes[kind] or type(target) ~= "string" or type(uniqueId) ~= "string" then return end
	emit(player, kind, target)
	updateObjectives(player, function(objective, current, entry)
		if objective.Type ~= kind or not matchesTarget(objective, target) then return nil end
		entry.ActivityVisits = entry.ActivityVisits or {}
		local key = kind .. ":" .. tostring(objective.Target or "*") .. ":" .. uniqueId
		if entry.ActivityVisits[key] then return nil end
		entry.ActivityVisits[key] = true
		return current + 1
	end)
end

-- Jogador derrotado (KillRewards, que já ignora abates do mesmo time).
-- Cada vítima só conta uma vez por missão: "derrote 3 Infernais" exige 3 jogadores diferentes, senão dois
-- amigos em caminhos opostos fechariam as missões PvP repetíveis matando um ao outro.
function QuestModule.OnPlayerKilled(killer, victim)
	if killer == victim then return end
	local victimTeam = teamName(victim)
	local killerTeam = teamName(killer)
	local victimPath = PathData.FromPlayer(victim)
	local victimKey = tostring(victim.UserId) -- chave string: o perfil vai para o DataStore como JSON

	-- As missões em que esta vítima contou só são marcadas no fim, para ela poder contar em mais de um
	-- objetivo KillPlayer da mesma missão (ex.: "3 Infernais" e "5 jogadores quaisquer")
	local counted = {}
	updateObjectives(killer, function(objective, current, entry)
		if objective.Type ~= "KillPlayer" then return nil end
		if type(entry.Victims) == "table" and entry.Victims[victimKey] then return nil end
		if objective.VictimPath and objective.VictimPath ~= victimPath then return nil end
		if objective.Target == victimTeam or (objective.Target == nil and victimTeam ~= killerTeam) then
			counted[entry] = true
			return current + 1
		end
		return nil
	end)

	-- Missões que completaram com este abate já saíram de Active; marcar a entry delas não tem efeito
	for entry in counted do
		if type(entry.Victims) ~= "table" then
			entry.Victims = {}
		end
		entry.Victims[victimKey] = true
	end
end

function QuestModule.OnLevelChanged(player)
	local level = PlayerData.GetLevel(player)
	updateObjectives(player, function(objective)
		if objective.Type == "ReachLevel" then
			return level
		end
		return nil
	end)
	-- Sempre manda: missões novas podem ter liberado nos NPCs (o "!" do minimapa)
	refreshAutoQuests(player)
	sendState(player)
end

-- Jogador falou com um NPC (chamado ao abrir o diálogo, antes de montar os dados)
function QuestModule.OnTalk(player, npcId)
	if type(npcId) ~= "string" then return end
	updateObjectives(player, function(objective, current)
		if objective.Type == "TalkTo" and matchesTarget(objective, npcId) then
			return current + 1
		end
		return nil
	end)
end

-- Jogador usou um poder de caminho (PathSkills). skillId = Id da habilidade no PathData.
function QuestModule.OnPowerUsed(player, skillId)
	emit(player, "Power", skillId)
	updateObjectives(player, function(objective, current)
		if objective.Type == "UsePower" and matchesTarget(objective, skillId) then
			return current + 1
		end
		return nil
	end)
end

-- Golpe de inimigo que chegou no jogador: pegou, bloqueou ou desviou (EnemyModule; o treino do Treinador não conta)
function QuestModule.OnHitTaken(player)
	updateObjectives(player, function(objective, current)
		return if objective.Type == "TakeHits" then current + 1 else nil
	end)
end

-- Golpe da cópia do Treinador no treino (TrainerService)
function QuestModule.OnSparHit(player)
	updateObjectives(player, function(objective, current)
		return if objective.Type == "Spar" then current + 1 else nil
	end)
end

-- Duelo contra o Treinador vencido (TrainerService)
function QuestModule.OnDuelWon(player)
	updateObjectives(player, function(objective, current)
		return if objective.Type == "Duel" then current + 1 else nil
	end)
end

-- Progresso do primeiro objetivo do tipo na missão ativa: (atual, total), ou nil se a missão não está ativa
function QuestModule.ObjectiveProgress(player, questId, objectiveType)
	local state = getState(player)
	local quest = questsById[questId]
	local entry = state and state.Active[questId]
	if not quest or not entry then return nil end
	for i, objective in quest.Objectives do
		if objective.Type == objectiveType then
			return entry.Progress[i] or 0, objective.Amount
		end
	end
	return nil
end

-- Compatibilidade: dá uma missão direto (ignora Giver, respeita o limite de ativas)
function QuestModule.Assign(player, questId)
	local quest = questsById[questId]
	local state = getState(player)
	if not quest or not state or state.Active[questId] then return false end
	if countActive(state) >= MAX_ACTIVE then return false end
	accept(player, quest)
	sendState(player)
	return true
end

function QuestModule.GetActive(player)
	local state = getState(player)
	return state and state.Active
end

-- Remove do estado salvo missões que não existem mais e corrige o progresso
local function cleanState(state)
	for questId, entry in state.Active do
		local quest = questsById[questId]
		if not quest or type(entry) ~= "table" then
			state.Active[questId] = nil
		else
			if type(entry.Progress) ~= "table" then
				entry.Progress = {}
			end
			for i in quest.Objectives do
				if type(entry.Progress[i]) ~= "number" then
					entry.Progress[i] = 0
				end
			end
			if entry.Victims ~= nil and type(entry.Victims) ~= "table" then
				entry.Victims = nil
			end
		end
	end
end

-- Caminho ou time mudou: abandona missões que não servem mais e libera as novas
local function revalidate(player)
	local state = getState(player)
	if not state or not ready[player] then return end

	-- Só mexe nas missões de rota quando o caminho é conhecido (atributo Path escrito pelo PathModule)
	if player:GetAttribute("Path") ~= nil then
		local abandoned = {}
		for questId in state.Active do
			local quest = questsById[questId]
			if quest and not fitsPlayer(player, quest) then
				table.insert(abandoned, questId)
			end
		end
		for _, questId in abandoned do
			state.Active[questId] = nil
		end
		if #abandoned > 0 then
			PlayerData.Notify(player, "Missões", `{#abandoned} missão(ões) que não servem mais para o seu caminho foram abandonadas.`, 5)
		end

		-- Quem não é Caçador não tem contratos: as missões que dão contrato podem ser feitas de novo
		-- se o jogador voltar a ser Caçador depois de renunciar ao caminho
		if PathData.FromPlayer(player) ~= "Hunter" then
			for _, quest in QuestData.Quests do
				if quest.Rewards and quest.Rewards.Contract then
					state.Completed[quest.Id] = nil
				end
			end
		end
	end

	refreshAutoQuests(player)
	sendState(player)
end

-- Junta várias mudanças seguidas (PathChanged, atributo Path, Team) numa revalidação só,
-- depois que o PathModule terminou de escrever tudo
local function scheduleRevalidate(player)
	if pendingRevalidate[player] then return end
	pendingRevalidate[player] = true
	task.defer(function()
		pendingRevalidate[player] = nil
		if player.Parent then
			revalidate(player)
		end
	end)
end

local function setupPlayer(player)
	local profile = PlayerData.WaitForProfile(player)
	if not profile then return end

	cleanState(profile.Quests)

	local level = player:WaitForChild("leaderstats"):WaitForChild("Level")
	level.Changed:Connect(function()
		QuestModule.OnLevelChanged(player)
	end)
	player:GetPropertyChangedSignal("Team"):Connect(function()
		scheduleRevalidate(player)
	end)
	player:GetAttributeChangedSignal("Path"):Connect(function()
		scheduleRevalidate(player)
	end)

	-- Espera o PathModule publicar o caminho antes de aceitar ou abandonar missões de rota
	local deadline = os.clock() + PATH_WAIT
	while player.Parent and player:GetAttribute("Path") == nil and os.clock() < deadline do
		task.wait(0.2)
	end
	if not player.Parent then return end
	if player:GetAttribute("Path") == nil then
		warn(`[QuestModule] {player.Name} está sem o atributo Path (PathModule). Tratando como Humano comum.`)
	end

	ready[player] = true
	revalidate(player)
end

-- ================= NPCs =================

local function npcPart(model)
	if model:IsA("BasePart") then return model end
	local root = model:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then return root end
	if model:IsA("Model") and model.PrimaryPart then return model.PrimaryPart end
	return model:FindFirstChildWhichIsA("BasePart", true)
end

local function npcIdOf(model)
	local id = model:GetAttribute("NPCId")
	return if type(id) == "string" and id ~= "" then id else model.Name
end

local function isNearNPC(player, npcId)
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if not root then return false end
	for _, model in CollectionService:GetTagged(NPC_TAG) do
		if model:IsDescendantOf(workspace) and npcIdOf(model) == npcId then
			local part = npcPart(model)
			if part and (part.Position - root.Position).Magnitude <= NPC_RANGE then
				return true
			end
		end
	end
	return false
end

-- Oferta de caminho do NPC (nil se ele não é NPC de caminho). Protegido: um erro no PathModule
-- não impede o diálogo de missões de abrir.
local function getPathOffer(player, npcId)
	local ok, offer = pcall(PathModule.GetOffer, player, npcId)
	if not ok then
		warn(`[QuestModule] PathModule.GetOffer falhou: {offer}`)
		return nil
	end
	return offer
end

local function greetingFor(player, npcId, available, active, offer)
	local custom = QuestData.Greetings and QuestData.Greetings[npcId] or {}
	local path = PathData.FromPlayer(player)
	if custom.Rival and custom.Path and path ~= "None" and path ~= custom.Path then
		return custom.Rival
	end
	if offer and offer.Mode == "Choose" and custom.PathChoose then
		return custom.PathChoose
	end
	if #available > 0 then
		return custom.Available or DEFAULT_GREETINGS.Available
	elseif #active > 0 then
		return custom.Active or DEFAULT_GREETINGS.Active
	end
	return custom.Idle or DEFAULT_GREETINGS.Idle
end

local function openDialog(player, npcId)
	if not getState(player) then return end

	-- Primeiro conta o "TalkTo" (ex.: Encruzilhada), para o diálogo já sair com a oferta de caminho atualizada
	QuestModule.OnTalk(player, npcId)

	local state = getState(player)
	if not state then return end

	local available, active = {}, {}
	for _, quest in QuestData.Quests do
		if quest.Giver == npcId then
			local entry = state.Active[quest.Id]
			if entry then
				table.insert(active, questView(quest, entry))
			elseif QuestModule.IsAvailable(player, quest) then
				table.insert(available, questView(quest, nil))
			end
		end
	end

	local offer = getPathOffer(player, npcId)
	-- Mestre dos Pactos: cartão da evolução do contrato (ContractService)
	local okEvolution, evolution = pcall(ContractService.GetOffer, player, npcId)
	if not okEvolution then
		warn(`[QuestModule] ContractService.GetOffer falhou: {evolution}`)
		evolution = nil
	end
	Remotes.QuestDialog:FireClient(player, {
		NPCId = npcId,
		NPCName = npcName(npcId),
		Greeting = greetingFor(player, npcId, available, active, offer),
		Available = available,
		Active = active,
		PathOffer = offer,
		Evolution = evolution,
	})
end

local function setupNPC(model)
	if not model:IsDescendantOf(workspace) then return end
	local part = npcPart(model)
	if not part then
		warn(`[QuestModule] NPC {model:GetFullName()} não tem nenhuma Part para o ProximityPrompt`)
		return
	end
	if part:FindFirstChild("QuestPrompt") then return end

	local npcId = npcIdOf(model)
	if not QuestData.NPCs[npcId] then
		warn(`[QuestModule] NPC {model:GetFullName()} usa o NPCId "{npcId}", que não está em QuestData.NPCs`)
	end

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "QuestPrompt"
	prompt.ActionText = "Falar"
	prompt.ObjectText = npcName(npcId)
	prompt.KeyboardKeyCode = Enum.KeyCode.E -- F é o block; o E ficou só para falar (as skills estão em Z/X/C)
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 12
	prompt.RequiresLineOfSight = false
	prompt.Parent = part
	prompt.Triggered:Connect(function(player)
		if not isNearNPC(player, npcId) then return end
		openDialog(player, npcId)
	end)
end

-- Botão TREINAR/DUELAR do diálogo: missão ativa deste NPC com um objetivo de treino (Spar/Duel) ainda aberto
local function startTraining(player, questId, npcId)
	local quest = questsById[questId]
	local state = getState(player)
	local entry = state and state.Active[questId]
	if not quest or not entry or quest.Giver ~= npcId or not isNearNPC(player, npcId) then return end
	for i, objective in quest.Objectives do
		if (objective.Type == "Spar" or objective.Type == "Duel") and (entry.Progress[i] or 0) < objective.Amount then
			-- Carregado aqui: o TrainerService usa o EnemyModule, que usa este módulo
			local TrainerService = require(script.Parent:WaitForChild("TrainerService"))
			TrainerService.Start(player, objective.Type, npcId, questId)
			return
		end
	end
end

local function onQuestAction(player, action, questId, npcId)
	if type(questId) ~= "string" or type(npcId) ~= "string" then return end
	if action == "Train" then
		startTraining(player, questId, npcId)
		return
	end
	if action ~= "Accept" then return end

	local quest = questsById[questId]
	local state = getState(player)
	if not quest or not state or quest.Giver ~= npcId then return end
	if not isNearNPC(player, npcId) or not QuestModule.IsAvailable(player, quest) then return end

	if countActive(state) >= MAX_ACTIVE then
		PlayerData.Notify(player, "Missões", `Você já tem {MAX_ACTIVE} missões ativas (fora as principais). Termine alguma primeiro.`)
		return
	end

	accept(player, quest)
	sendState(player)
	openDialog(player, npcId) -- atualiza o diálogo aberto
end

function QuestModule.Init()
	Players.PlayerAdded:Connect(setupPlayer)
	for _, player in Players:GetPlayers() do
		task.spawn(setupPlayer, player)
	end
	Players.PlayerRemoving:Connect(function(player)
		ready[player] = nil
		pendingRevalidate[player] = nil
	end)

	-- Escolher, renunciar ou ganhar contrato: abandona missões da rota antiga e libera as da nova
	if PathModule.PathChanged then
		PathModule.PathChanged:Connect(function(player)
			if typeof(player) == "Instance" and player:IsA("Player") then
				scheduleRevalidate(player)
			end
		end)
	else
		warn("[QuestModule] PathModule.PathChanged não existe; as missões só reagem ao atributo Path")
	end

	-- O cliente pede o estado quando a GUI carrega
	Remotes.QuestEvent.OnServerEvent:Connect(sendState)
	Remotes.QuestAction.OnServerEvent:Connect(onQuestAction)

	CollectionService:GetInstanceAddedSignal(NPC_TAG):Connect(setupNPC)
	for _, model in CollectionService:GetTagged(NPC_TAG) do
		task.spawn(setupNPC, model)
	end
end

return QuestModule
