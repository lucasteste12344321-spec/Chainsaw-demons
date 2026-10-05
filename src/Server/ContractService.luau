-- Evolução dos contratos (ContractData): o Mestre dos Pactos (NPC "Evolucao") mostra a próxima forma do contrato do
-- Caçador, o que ela pede e, quando dá, faz a fusão (V1 -> V2). A forma Ultimate vem da missão final (QuestData,
-- recompensa Form), não daqui.
-- O QuestModule põe GetOffer no diálogo do NPC (campo Evolution); o QuestGUI mostra o cartão e manda
-- Remotes.ContractAction("Fuse", npcId).
-- Não pode dar require no QuestModule (é o QuestModule que usa este módulo): as missões são lidas no perfil.
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage:WaitForChild("Remotes"))
local PathData = require(ReplicatedStorage:WaitForChild("PathData"))
local ContractData = require(ReplicatedStorage:WaitForChild("ContractData"))
local PlayerData = require(script.Parent:WaitForChild("PlayerData"))
local PathModule = require(script.Parent:WaitForChild("PathModule"))
local QuestData = require(script.Parent:WaitForChild("QuestData"))

local ContractService = {}

local NPC_TAG = "QuestGiver"
local NPC_RANGE = 20
local ACTION_GAP = 1
local lastAction = {}

local function npcName()
	return QuestData.NPCs[ContractData.EvolutionNPC] or "Mestre dos Pactos"
end

local function questName(questId)
	for _, quest in QuestData.Quests do
		if quest.Id == questId then
			return quest.Name
		end
	end
	return nil
end

local function questCompleted(player, questId)
	local profile = PlayerData.GetProfile(player)
	local completed = profile and profile.Quests and profile.Quests.Completed
	return type(completed) == "table" and (completed[questId] or 0) > 0
end

local function isNearNPC(player, npcId)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then return false end
	for _, model in CollectionService:GetTagged(NPC_TAG) do
		if model:GetAttribute("NPCId") == npcId and model:IsDescendantOf(workspace) then
			local part = if model:IsA("BasePart") then model else model:FindFirstChildWhichIsA("BasePart", true)
			if part and (part.Position - root.Position).Magnitude <= NPC_RANGE then
				return true
			end
		end
	end
	return false
end

-- Requisitos da forma: lista de { Text, Have, Need, Done } (Have/Need para a barra; missão: 0/1)
local function requirementsOf(player, contractId, form)
	local entry = ContractData.Get(contractId)
	local data = ContractData.Form(contractId, form)
	local requires = data and data.Requires or {}
	local contract = PathData.Contracts[contractId]
	local list = {}
	if requires.Mastery then
		local have = PlayerData.GetContractMasteryLevel(player, contractId)
		table.insert(list, {
			Text = `Maestria do contrato ({contract and contract.DisplayName or contractId})`,
			Have = have,
			Need = requires.Mastery,
			Done = have >= requires.Mastery,
		})
	end
	if requires.StyleMastery and entry and entry.FusionStyle then
		local have = PlayerData.GetMasteryLevel(player, entry.FusionStyle)
		table.insert(list, {
			Text = `Maestria nos {entry.FusionStyle}`,
			Have = have,
			Need = requires.StyleMastery,
			Done = have >= requires.StyleMastery,
		})
	end
	if requires.Quest then
		local done = questCompleted(player, requires.Quest)
		table.insert(list, {
			Text = `Missão: {questName(requires.Quest) or "a provação final (em breve)"}`,
			Have = if done then 1 else 0,
			Need = 1,
			Done = done,
		})
	end
	return list
end

-- Cartão do diálogo do Mestre dos Pactos, ou nil para os outros NPCs.
-- Mode: "Locked" (sem contrato com formas), "Fuse" (próxima é a V2: o botão funde), "Quest" (próxima vem de
-- missão), "Max" (já é a última forma)
function ContractService.GetOffer(player, npcId)
	if npcId ~= ContractData.EvolutionNPC then return nil end
	local path, contracts = PathModule.Get(player)
	local contractId = path == "Hunter" and contracts[1] or nil
	if not contractId or not ContractData.HasForms(contractId) then
		return {
			Mode = "Locked",
			Reason = "Só Caçadores com um contrato podem evoluir o pacto. Escolha o caminho do Caçador no level 25.",
		}
	end

	local form = PathModule.GetForm(player)
	local nextForm = ContractData.NextForm(form)
	local contract = PathData.Contracts[contractId]
	local entry = ContractData.Get(contractId)
	local offer = {
		Contract = contractId,
		ContractName = contract and contract.DisplayName or contractId,
		Glyph = contract and contract.Glyph,
		Form = form,
		FormName = ContractData.FormNames[form],
		FusionStyle = entry.FusionStyle,
	}
	if not nextForm then
		offer.Mode = "Max"
		return offer
	end
	local nextData = ContractData.Form(contractId, nextForm)
	local requirements = requirementsOf(player, contractId, nextForm)
	local ready = true
	for _, requirement in requirements do
		ready = ready and requirement.Done
	end
	offer.Next = nextForm
	offer.NextName = ContractData.FormNames[nextForm]
	offer.Description = nextData and nextData.Description
	offer.Requirements = requirements
	offer.Ready = ready
	offer.Mode = if nextForm == "V2" then "Fuse" else "Quest"
	local fusion = ContractData.Fusion(contractId, nextForm)
	offer.FusionName = fusion and fusion.DisplayName
	return offer
end

-- Fusão V1 -> V2 (Remotes.ContractAction "Fuse")
function ContractService.Fuse(player, npcId)
	if not isNearNPC(player, npcId) then return false end
	local offer = ContractService.GetOffer(player, npcId)
	if not offer or offer.Mode ~= "Fuse" then return false end
	if not offer.Ready then
		PlayerData.Notify(player, npcName(), "Você ainda não cumpre o que a fusão pede.", 4)
		return false
	end
	if not PathModule.SetForm(player, "V2") then return false end
	local title = offer.FusionName or `{offer.ContractName} + {offer.FusionStyle}`
	PlayerData.Notify(player, "Fusão!", `{title}: o contrato e o estilo agora são uma coisa só.`, 8)
	Remotes.Announcement:FireAllClients("FUSÃO", `{player.DisplayName} fundiu os {offer.FusionStyle} com o {offer.ContractName}!`, 5)
	return true
end

-- Forma direto (recompensa de missão: a Ultimate). Devolve true se mudou.
function ContractService.SetForm(player, form)
	local current, contractId = PathModule.GetForm(player)
	if not contractId or ContractData.FormRank(form) <= ContractData.FormRank(current) then return false end
	return PathModule.SetForm(player, form)
end

local function onAction(player, action, npcId)
	if action ~= "Fuse" or type(npcId) ~= "string" or #npcId > 64 then return end
	local clock = os.clock()
	if clock - (lastAction[player] or 0) < ACTION_GAP then return end
	lastAction[player] = clock
	ContractService.Fuse(player, npcId)
end

function ContractService.Init()
	Remotes.ContractAction.OnServerEvent:Connect(onAction)
	Players.PlayerRemoving:Connect(function(player)
		lastAction[player] = nil
	end)
end

return ContractService
