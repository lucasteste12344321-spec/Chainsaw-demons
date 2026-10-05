-- Caminhos (Fase 4): Humano comum -> Caçador (contratos com demônios) ou Infernal.
-- Especificação em docs/fase4-caminhos.md. Definições (contratos, tipos, custos) em ReplicatedStorage.PathData.
-- O estado fica salvo no perfil do PlayerData (profile.Path) e é replicado em atributos do Player:
--   Path, Contracts ("Raposa"), ContractForm ("V1"/"V2"/"Ultimate", ContractData), FiendType, Lifespan, MaxLifespan,
--   AllyProtection, SpeedBonus
-- Também cuida dos Teams (Humans / Fiends) e dos remotes PathAction e SetAllyProtection.
-- Não pode dar require no QuestModule (é o QuestModule que usa este módulo).
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Teams = game:GetService("Teams")

local Remotes = require(ReplicatedStorage:WaitForChild("Remotes"))
local PathData = require(ReplicatedStorage:WaitForChild("PathData"))
local ContractData = require(ReplicatedStorage:WaitForChild("ContractData"))
local PlayerData = require(script.Parent:WaitForChild("PlayerData"))

local PathModule = {}

local NPC_TAG = "QuestGiver"
local NPC_RANGE = 20 -- distância máxima até o NPC para qualquer ação de caminho
local ACTION_COOLDOWN = 0.5 -- segundos entre duas ações do mesmo jogador
local REGEN_INTERVAL = 1 -- o loop do tempo de vida roda (e atualiza o atributo) 1x por segundo
local NOTIFY_TITLE = "Caminho"
local LOADING_TEXT = "Seus dados ainda estão carregando. Tente de novo em instantes."

-- Cores livres para times antigos que tenham a mesma cor de Humans/Fiends
local SPARE_TEAM_COLORS = { "Dark stone grey", "Medium stone grey", "Bright violet", "Bright orange", "Bright green", "Black" }

local changedEvent = Instance.new("BindableEvent")
PathModule.PathChanged = changedEvent.Event -- (player, newPath)

local lastAction = {} -- [player] = os.clock() da última PathAction aceita
local lastToggle = {} -- [player] = os.clock() do último SetAllyProtection aceito
local initialized = false

-- ================= Utilidades =================

local function getState(player)
	local profile = PlayerData.GetProfile(player)
	return profile and profile.Path
end

local function round1(value)
	return math.floor(value * 10 + 0.5) / 10
end

local function displayName(path)
	local info = PathData.Paths[path]
	return if info then info.DisplayName else tostring(path)
end

local function notify(player, text, duration)
	PlayerData.Notify(player, NOTIFY_TITLE, text, duration)
end

-- Avisa o jogador e devolve (false, motivo), o formato de retorno das funções públicas
local function fail(player, reason)
	notify(player, reason, 4)
	return false, reason
end

local function goldOf(player)
	local leaderstats = player:FindFirstChild("leaderstats")
	local gold = leaderstats and leaderstats:FindFirstChild("Gold")
	return if gold then gold.Value else 0
end

-- QuestData só é usado para nomes (do NPC e da missão). Carregado sob demanda e protegido: se falhar, usa os ids.
local questData = nil
local function getQuestData()
	if questData == nil then
		local module = script.Parent:FindFirstChild("QuestData")
		local ok, result = false, nil
		if module then
			ok, result = pcall(require, module)
		end
		questData = if ok and type(result) == "table" then result else false
	end
	return questData or nil
end

local function npcName(npcId)
	local data = getQuestData()
	local names = data and data.NPCs
	local name = type(names) == "table" and names[npcId]
	return if type(name) == "string" then name else tostring(npcId)
end

local function questName(questId)
	local data = getQuestData()
	if data and type(data.Quests) == "table" then
		for _, quest in data.Quests do
			if type(quest) == "table" and quest.Id == questId and type(quest.Name) == "string" then
				return quest.Name
			end
		end
	end
	return questId
end

-- Lê profile.Quests.Completed (o QuestModule escreve; aqui é só leitura)
local function hasCompletedQuest(player, questId)
	local profile = PlayerData.GetProfile(player)
	local quests = profile and profile.Quests
	local completed = type(quests) == "table" and quests.Completed
	if type(completed) ~= "table" then
		return false
	end
	local value = completed[questId]
	return value == true or (tonumber(value) or 0) > 0
end

-- Caminho cujo NPC é este ("Hunter" ou "Fiend"), ou nil
local function pathOfNPC(npcId)
	for _, pathId in { "Hunter", "Fiend" } do
		if PathData.Paths[pathId].NPC == npcId then
			return pathId
		end
	end
	return nil
end

-- ================= NPCs (mesma convenção do QuestModule) =================

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

-- Jogador vivo a no máximo NPC_RANGE studs de um NPC (tag QuestGiver) com esse NPCId
local function isNearNPC(player, npcId)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not humanoid or humanoid.Health <= 0 or not root or not root:IsA("BasePart") then return false end

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

-- ================= Times =================

local function colorInUse(color)
	for _, team in Teams:GetTeams() do
		if team.TeamColor == color then
			return true
		end
	end
	return false
end

-- Nome do time de caminho (Humans/Fiends) que usa a mesma cor deste time, ou nil
local function colorConflict(team)
	for name in PathData.Teams do
		local ours = Teams:FindFirstChild(name)
		if ours and ours ~= team and ours:IsA("Team") and ours.TeamColor == team.TeamColor then
			return name
		end
	end
	return nil
end

-- Cria os times que faltarem e desliga a entrada automática em todos (inclusive no "Demons" antigo)
local function ensureTeams()
	for name, info in PathData.Teams do
		local team = Teams:FindFirstChild(name)
		if not team or not team:IsA("Team") then
			team = Instance.new("Team")
			team.Name = name
			team.TeamColor = info.BrickColor
			team.AutoAssignable = false
			team.Parent = Teams
		end
	end

	for _, team in Teams:GetTeams() do
		team.AutoAssignable = false

		-- O Roblox decide o time do jogador pela TeamColor: um time antigo com a mesma cor de Humans/Fiends
		-- ganha outra cor (os SpawnLocations dessa cor continuam valendo para o time novo)
		local conflict = colorConflict(team)
		if conflict and not PathData.Teams[team.Name] then
			for _, colorName in SPARE_TEAM_COLORS do
				local color = BrickColor.new(colorName)
				if not colorInUse(color) then
					warn(`[PathModule] O time antigo "{team.Name}" tinha a mesma cor do time "{conflict}" e agora usa {colorName}`)
					team.TeamColor = color
					break
				end
			end
		elseif conflict then
			warn(`[PathModule] Os times "{team.Name}" e "{conflict}" têm a mesma TeamColor: mude uma delas no Studio`)
		end
	end
end

local function teamForPath(path)
	local info = PathData.Paths[path] or PathData.Paths.None
	local team = Teams:FindFirstChild(info.Team)
	return if team and team:IsA("Team") then team else nil
end

local function applyTeam(player, path)
	local team = teamForPath(path)
	if not team then return end
	if player.Team ~= team then
		player.Team = team
	end
	player.Neutral = false
end

-- Só vale renascer se o mapa tiver um SpawnLocation desse time
local function hasTeamSpawn(team)
	for _, spawn in workspace:GetDescendants() do
		if spawn:IsA("SpawnLocation") and spawn.Enabled and not spawn.Neutral and spawn.TeamColor == team.TeamColor then
			return true
		end
	end
	return false
end

-- ================= Estado replicado =================

local function setLifespanAttribute(player, value)
	local rounded = round1(value)
	if player:GetAttribute("Lifespan") ~= rounded then
		player:SetAttribute("Lifespan", rounded)
	end
end

-- Forma do contrato do Caçador (ContractData): a salva no perfil, ou "V1"
local function formOf(state)
	local contractId = state.Contracts[1]
	local form = contractId and type(state.Forms) == "table" and state.Forms[contractId]
	return if ContractData.IsForm(form) then form else "V1"
end

local function writeAttributes(player, state)
	local form = formOf(state)
	local passives = PathData.Passives(state.Path, state.Contracts, state.FiendType, form)
	player:SetAttribute("Path", state.Path)
	player:SetAttribute("Contracts", table.concat(state.Contracts, ","))
	player:SetAttribute("ContractForm", if state.Path == "Hunter" then form else nil)
	player:SetAttribute("FiendType", state.FiendType)
	setLifespanAttribute(player, state.Lifespan)
	player:SetAttribute("MaxLifespan", PathData.MaxLifespan)
	player:SetAttribute("AllyProtection", state.AllyProtection)
	player:SetAttribute("SpeedBonus", passives.SpeedBonus or 0)
end

-- Atributos, time e vida máxima conforme o perfil (a vida lê os atributos, então eles vêm primeiro)
local function applyState(player, state)
	writeAttributes(player, state)
	applyTeam(player, state.Path)
	PlayerData.RefreshHealth(player)
end

-- Depois de qualquer mudança de caminho ou de contratos
local function commitChange(player, state)
	applyState(player, state)
	changedEvent:Fire(player, state.Path)
end

-- Ids das opções do diálogo: contratos iniciais (Unlock = "Path") ou tipos de Infernal
local function optionsFor(path)
	local options = {}
	if path == "Hunter" then
		for contractId, contract in PathData.Contracts do
			if contract.Unlock == "Path" and ContractData.IsEnabled(contractId) then
				table.insert(options, contractId)
			end
		end
		-- Menor sacrifício primeiro
		table.sort(options, function(a, b)
			local costA, costB = PathData.Contracts[a].HPCost or 0, PathData.Contracts[b].HPCost or 0
			if costA ~= costB then
				return costA < costB
			end
			return a < b
		end)
	elseif path == "Fiend" then
		-- Enabled = false no PathData.FiendTypes: fora da escolha
		for fiendTypeId, fiend in PathData.FiendTypes do
			if fiend.Enabled ~= false then
				table.insert(options, fiendTypeId)
			end
		end
		table.sort(options)
	end
	return options
end

-- ================= API =================

-- Caminho salvo no perfil: path ("None"/"Hunter"/"Fiend"), contracts (cópia da lista), fiendType ("" se não tiver)
-- e a forma do contrato ("V1"/"V2"/"Ultimate")
function PathModule.Get(player)
	local state = getState(player)
	if not state then
		return "None", {}, "", "V1"
	end
	return state.Path, table.clone(state.Contracts), state.FiendType, formOf(state)
end

-- Forma do contrato atual: (forma, contrato) ou ("V1", nil) para quem não é Caçador
function PathModule.GetForm(player)
	local state = getState(player)
	if not state or state.Path ~= "Hunter" then
		return "V1", nil
	end
	return formOf(state), state.Contracts[1]
end

-- Muda a forma do contrato atual (quem confere os requisitos é o ContractService). Devolve true se mudou.
function PathModule.SetForm(player, form)
	local state = getState(player)
	local contractId = state and state.Path == "Hunter" and state.Contracts[1]
	if not contractId or not ContractData.HasForms(contractId) or not ContractData.IsForm(form) then
		return false
	end
	if type(state.Forms) ~= "table" then
		state.Forms = {}
	end
	state.Forms[contractId] = form
	commitChange(player, state)
	return true
end

function PathModule.CanChoose(player)
	local state = getState(player)
	if not state then
		return false, LOADING_TEXT
	end
	if state.Path ~= "None" then
		return false, `Você já é {displayName(state.Path)}. A escolha de caminho é permanente.`
	end
	if PlayerData.GetLevel(player) < PathData.MinLevel then
		return false, `Chegue ao level {PathData.MinLevel} para escolher um caminho.`
	end
	if not hasCompletedQuest(player, PathData.RequiredQuest) then
		return false, `Complete a missão "{questName(PathData.RequiredQuest)}" antes de escolher um caminho.`
	end
	return true, nil
end

function PathModule.ChooseHunter(player, contractId)
	local ok, reason = PathModule.CanChoose(player)
	if not ok then
		return fail(player, reason)
	end

	local contract = if type(contractId) == "string" then PathData.Contracts[contractId] else nil
	if not contract or contract.Unlock ~= "Path" or not ContractData.IsEnabled(contractId) then
		return fail(player, "Esse contrato não pode ser o primeiro. Escolha um dos contratos oferecidos.")
	end

	local state = getState(player)
	state.Path = "Hunter"
	state.Contracts = { contractId }
	state.FiendType = ""
	state.Lifespan = PathData.MaxLifespan
	commitChange(player, state)

	local sacrifice = if (contract.HPCost or 0) > 0
		then ` Sacrifício: -{math.floor(contract.HPCost * 100 + 0.5)}% de vida máxima.`
		else ""
	notify(player, `Você agora é um Caçador. Contrato: {contract.DisplayName} (teclas V e B).{sacrifice}`, 6)
	return true, nil
end

function PathModule.ChooseFiend(player, fiendTypeId)
	local ok, reason = PathModule.CanChoose(player)
	if not ok then
		return fail(player, reason)
	end

	local fiendType = if type(fiendTypeId) == "string" then PathData.FiendTypes[fiendTypeId] else nil
	if not fiendType or fiendType.Enabled == false then
		return fail(player, "Esse tipo de Infernal não existe.")
	end

	local state = getState(player)
	state.Path = "Fiend"
	state.Contracts = {}
	state.FiendType = fiendTypeId
	state.Lifespan = PathData.MaxLifespan
	commitChange(player, state)

	notify(player, `Você agora é um {fiendType.DisplayName}. Seus poderes (teclas V e B) custam vida.`, 6)
	return true, nil
end

-- Comando de admin (ItemCommands /cacador): vira Caçador com o contrato na hora, sem level nem missão
function PathModule.AdminHunter(player, contractId)
	local state = getState(player)
	if not state or not PathData.Contracts[contractId] or not ContractData.IsEnabled(contractId) then
		return false
	end
	state.Path = "Hunter"
	state.Contracts = { contractId }
	state.FiendType = ""
	state.Lifespan = PathData.MaxLifespan
	commitChange(player, state)
	return true
end

-- Comando de admin (ItemCommands /infernal): vira Infernal do tipo na hora, sem level nem missão
function PathModule.AdminFiend(player, fiendTypeId)
	local state = getState(player)
	local fiendType = PathData.FiendTypes[fiendTypeId]
	if not state or not fiendType or fiendType.Enabled == false then
		return false
	end
	state.Path = "Fiend"
	state.Contracts = {}
	state.FiendType = fiendTypeId
	state.Lifespan = PathData.MaxLifespan
	commitChange(player, state)
	return true
end

-- Recompensa de missão: novo contrato (Unlock = "Quest") para um Caçador, respeitando MaxContracts
function PathModule.AddContract(player, contractId)
	local contract = if type(contractId) == "string" then PathData.Contracts[contractId] else nil
	if not contract or contract.Unlock ~= "Quest" or not ContractData.IsEnabled(contractId) then
		warn(`[PathModule] AddContract com contrato inválido: {tostring(contractId)}`)
		return false, "Contrato inválido."
	end

	local state = getState(player)
	if not state then
		return fail(player, LOADING_TEXT)
	end
	if state.Path ~= "Hunter" then
		return fail(player, "Só Caçadores podem fazer contratos com demônios.")
	end
	if table.find(state.Contracts, contractId) then
		return fail(player, `Você já tem o contrato com o {contract.DisplayName}.`)
	end
	if #state.Contracts >= PathData.MaxContracts then
		return fail(player, `Você já tem {PathData.MaxContracts} contratos, o máximo permitido.`)
	end

	table.insert(state.Contracts, contractId)
	commitChange(player, state)

	local key = if #state.Contracts == 1 then "Z" else "X"
	local sacrifice = if (contract.HPCost or 0) > 0
		then ` Sacrifício: -{math.floor(contract.HPCost * 100 + 0.5)}% de vida máxima.`
		else ""
	notify(player, `Novo contrato: {contract.DisplayName} (tecla {key}).{sacrifice}`, 6)
	return true, nil
end

-- Renuncia ao caminho (volta a Humano comum) pagando PathData.ResetCost
function PathModule.Reset(player)
	local state = getState(player)
	if not state then
		return fail(player, LOADING_TEXT)
	end
	if state.Path == "None" then
		return fail(player, "Você ainda não seguiu nenhum caminho.")
	end

	local cost = PathData.ResetCost
	if not PlayerData.SpendGold(player, cost) then
		return fail(player, `Renunciar ao caminho custa {cost} Gold. Você tem {goldOf(player)}.`)
	end

	local oldName = displayName(state.Path)
	state.Path = "None"
	state.Contracts = {}
	state.FiendType = ""
	state.Lifespan = PathData.MaxLifespan
	state.PathResets = (tonumber(state.PathResets) or 0) + 1
	commitChange(player, state)

	notify(player, `Você renunciou ao caminho {oldName} por {cost} Gold e voltou a ser um Humano comum.`, 6)
	return true, nil
end

-- Gasta tempo de vida (só Caçadores). Devolve false sem gastar nada se não tiver o suficiente.
function PathModule.SpendLifespan(player, amount)
	if type(amount) ~= "number" or amount ~= amount or amount < 0 or amount == math.huge then
		return false
	end
	local state = getState(player)
	if not state or state.Path ~= "Hunter" then
		return false
	end
	if amount == 0 then
		return true
	end
	-- Tolerância do arredondamento do atributo (0.1): se a HUD mostra 8.0, 8 de custo passa
	if state.Lifespan + 0.05 < amount then
		return false
	end

	state.Lifespan = math.max(0, state.Lifespan - amount)
	setLifespanAttribute(player, state.Lifespan)
	return true
end

function PathModule.SetAllyProtection(player, enabled)
	if type(enabled) ~= "boolean" then return end
	local state = getState(player)
	if not state then return end
	state.AllyProtection = enabled
	player:SetAttribute("AllyProtection", enabled)
end

-- Resumo para o diálogo de NPC: nil se o NPC não é de caminho
function PathModule.GetOffer(player, npcId)
	local offerPath = if type(npcId) == "string" then pathOfNPC(npcId) else nil
	if not offerPath then
		return nil
	end

	local state = getState(player)
	if not state then
		return { Path = offerPath, Mode = "Locked", Reason = LOADING_TEXT }
	end
	if state.Path == offerPath then
		return { Path = offerPath, Mode = "Reset" }
	end
	if state.Path ~= "None" then
		local info = PathData.Paths[state.Path]
		local ownNPC = if info and info.NPC then npcName(info.NPC) else "o NPC do seu caminho"
		return {
			Path = offerPath,
			Mode = "Locked",
			Reason = `Você já é {displayName(state.Path)}. Para mudar, renuncie ao seu caminho com {ownNPC}.`,
		}
	end

	local ok, reason = PathModule.CanChoose(player)
	if ok then
		return { Path = offerPath, Mode = "Choose" }
	end
	return { Path = offerPath, Mode = "Locked", Reason = reason }
end

function PathModule.OpenDialog(player, npcId)
	local offer = PathModule.GetOffer(player, npcId)
	if not offer then return end

	Remotes.PathDialog:FireClient(player, {
		NPCId = npcId,
		NPCName = npcName(npcId),
		Path = offer.Path,
		Mode = offer.Mode,
		Reason = offer.Reason,
		ResetCost = PathData.ResetCost,
		Options = optionsFor(offer.Path),
	})
end

-- ================= Remotes =================

local VALID_ACTIONS = { Open = true, ChooseHunter = true, ChooseFiend = true, Reset = true }

-- Remotes.PathAction (action, id, npcId)
local function onPathAction(player, action, id, npcId)
	if type(action) ~= "string" or not VALID_ACTIONS[action] then return end
	if type(npcId) ~= "string" or #npcId > 64 then return end
	if id ~= nil and (type(id) ~= "string" or #id > 64) then return end

	local now = os.clock()
	if now - (lastAction[player] or -math.huge) < ACTION_COOLDOWN then return end
	lastAction[player] = now

	local npcPath = pathOfNPC(npcId)
	if not npcPath then return end

	if not isNearNPC(player, npcId) then
		notify(player, "Chegue mais perto do NPC para fazer isso.", 3)
		return
	end

	if action == "Open" then
		PathModule.OpenDialog(player, npcId)
	elseif action == "ChooseHunter" or action == "ChooseFiend" then
		local wanted = if action == "ChooseHunter" then "Hunter" else "Fiend"
		if npcPath ~= wanted then
			notify(player, `Para seguir o caminho {displayName(wanted)}, fale com {npcName(PathData.Paths[wanted].NPC)}.`, 4)
			return
		end
		if wanted == "Hunter" then
			PathModule.ChooseHunter(player, id)
		else
			PathModule.ChooseFiend(player, id)
		end
	elseif action == "Reset" then
		-- Só o NPC do próprio caminho desfaz a escolha
		local state = getState(player)
		local info = state and PathData.Paths[state.Path]
		if state and state.Path ~= "None" and info and info.NPC ~= npcId then
			notify(player, `Só {npcName(info.NPC)} pode desfazer o seu caminho.`, 4)
			return
		end
		PathModule.Reset(player)
	end
end

-- Remotes.SetAllyProtection (enabled)
local function onSetAllyProtection(player, enabled)
	if type(enabled) ~= "boolean" then return end

	local now = os.clock()
	if now - (lastToggle[player] or -math.huge) < ACTION_COOLDOWN then return end
	lastToggle[player] = now

	local state = getState(player)
	if not state then
		notify(player, LOADING_TEXT, 3)
		return
	end
	if state.AllyProtection == enabled then return end

	PathModule.SetAllyProtection(player, enabled)
	if enabled then
		notify(player, "Proteção de aliados ligada: você não causa nem recebe dano do seu time.", 3)
	else
		notify(player, "Proteção de aliados desligada: o dano entre aliados só acontece se os dois desligarem.", 4)
	end
end

-- ================= Jogadores =================

local function setupPlayer(player)
	-- Antes do perfil carregar, todo mundo é Humano comum (ninguém nasce sem time)
	if not PlayerData.GetProfile(player) then
		applyTeam(player, "None")
	end

	local profile = PlayerData.WaitForProfile(player)
	if not profile or not player.Parent then return end
	local state = profile.Path
	if type(state) ~= "table" then
		warn(`[PathModule] Perfil de {player.Name} sem a tabela Path`)
		return
	end

	local teamBefore = player.Team
	applyState(player, state)

	-- Quem entra como Infernal nasceu na base dos Humanos: renasce na base do próprio time, se o mapa tiver uma
	local team = player.Team
	if team and team ~= teamBefore and player.Character and hasTeamSpawn(team) then
		player:LoadCharacter()
	end
end

-- Regenera o tempo de vida dos Caçadores (loop único para todos os jogadores)
local function lifespanLoop()
	local last = os.clock()
	while true do
		task.wait(REGEN_INTERVAL)
		local now = os.clock()
		local elapsed = math.min(now - last, REGEN_INTERVAL * 5)
		last = now

		for _, player in Players:GetPlayers() do
			local state = getState(player)
			if state and state.Path == "Hunter" and state.Lifespan < PathData.MaxLifespan then
				state.Lifespan = math.min(PathData.MaxLifespan, state.Lifespan + PathData.LifespanRegen * elapsed)
				setLifespanAttribute(player, state.Lifespan)
			end
		end
	end
end

function PathModule.Init()
	if initialized then return end
	initialized = true

	ensureTeams()
	Teams.ChildAdded:Connect(function(child)
		if child:IsA("Team") then
			child.AutoAssignable = false
		end
	end)

	Players.PlayerAdded:Connect(setupPlayer)
	for _, player in Players:GetPlayers() do
		task.spawn(setupPlayer, player)
	end
	Players.PlayerRemoving:Connect(function(player)
		lastAction[player] = nil
		lastToggle[player] = nil
	end)

	Remotes.PathAction.OnServerEvent:Connect(onPathAction)
	Remotes.SetAllyProtection.OnServerEvent:Connect(onSetAllyProtection)

	task.spawn(lifespanLoop)
end

return PathModule
