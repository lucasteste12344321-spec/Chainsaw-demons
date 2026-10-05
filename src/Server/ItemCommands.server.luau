-- Comandos de admin para testar sem farmar (lista de admins em Admins.luau):
--   /item <Id>    dá 1 unidade do item (Id do ItemData, sem diferenciar maiúsculas)
--   /item todos   dá 1 de cada item
--   /estilo <Nome>             ensina um estilo de combate (ex.: /estilo Katana)
--   /maestria <Estilo> <nível>  sobe a maestria do estilo até o nível (ex.: /maestria Katana 30)
--   /pontos <n>                dá n pontos da árvore de habilidades (bônus salvo no perfil)
--   /cacador [Contrato]        vira Caçador com o contrato (padrão Raposa), sem level nem missão
--   /maestriacontrato <nível>  sobe a maestria do contrato atual até o nível (ex.: /maestriacontrato 120)
--   /forma <V1|V2|Ultimate>    troca a forma do contrato atual direto (ContractData)
--   /yen <n> (ou /gold <n>)    dá n de dinheiro (o Gold do jogo)
--   /esquiva <0-5>             muda o nível da esquiva automática (DodgeData; o normal é pelas missões do Treinador)
--   /esquiva <n>%              esquiva fixa em n% (ex.: /esquiva 100%), sem o teto e salva no perfil; /esquiva normal tira
--   /restricao <on|off>        simula conta com sorteio pago restrito (menor no Brasil): o clã vira escolha direta
--                              (até sair do jogo; o normal vem do PolicyService no CharacterService)
--   /treinador <treino|duelo>  chama a cópia do Treinador para testar (sem contar em missão; perto do NPC Treinador)
--   /destruir [raio]           explode o mapa na sua frente (Destruction) e mostra por que cada peça quebrou ou não
--   /chefe <Nome>              faz um chefe aparecer agora (ex.: /chefe Denji; o global não espera o horário)
--   /hibrido [Infernal] [Contrato]  modo híbrido: contrato no V/B e poderes do Infernal no H/J, seja qual for o caminho
--                              (padrão Sangue e Raposa; /hibrido off desliga; vale até sair do jogo)
local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Admins = require(ServerScriptService:WaitForChild("Admins"))
local PlayerData = require(ServerScriptService:WaitForChild("PlayerData"))
local ItemData = require(ReplicatedStorage:WaitForChild("ItemData"))
local CombatStyles = require(ReplicatedStorage:WaitForChild("CombatStyles"))
local SkillTreeData = require(ReplicatedStorage:WaitForChild("SkillTreeData"))
local ContractData = require(ReplicatedStorage:WaitForChild("ContractData"))
local PathData = require(ReplicatedStorage:WaitForChild("PathData"))
local PathModule = require(ServerScriptService:WaitForChild("PathModule"))

local function findItem(text)
	local wanted = string.lower(text)
	for id in ItemData.Items do
		if string.lower(id) == wanted then
			return id
		end
	end
	return nil
end

Admins.BindCommand("/item", function(player, argument)
	if argument == "" then
		local ids = {}
		for id in ItemData.Items do
			table.insert(ids, id)
		end
		table.sort(ids)
		PlayerData.Notify(player, "Itens", "Use /item <Id> ou /item todos. Ids: " .. table.concat(ids, ", "), 6)
		return
	end
	if string.lower(argument) == "todos" then
		for id in ItemData.Items do
			PlayerData.AddItem(player, id, 1)
		end
		PlayerData.Notify(player, "Itens", "Você recebeu 1 de cada item. Aperte G para abrir o inventário.")
		return
	end
	local id = findItem(argument)
	if not id then
		PlayerData.Notify(player, "Itens", `Não existe o item "{argument}".`)
		return
	end
	PlayerData.AddItem(player, id, 1)
	PlayerData.Notify(player, "Itens", `Você recebeu: {ItemData.Get(id).Name}.`)
end)

local function findStyle(text)
	local wanted = string.lower(text or "")
	for name in CombatStyles.Styles do
		if string.lower(name) == wanted then
			return name
		end
	end
	return nil
end

local function styleNames()
	local names = {}
	for name in CombatStyles.Styles do
		table.insert(names, name)
	end
	table.sort(names)
	return table.concat(names, ", ")
end

Admins.BindCommand("/estilo", function(player, argument)
	local name = findStyle(argument)
	if not name then
		PlayerData.Notify(player, "Estilos", `Use /estilo <Nome>. Estilos: {styleNames()}.`, 6)
		return
	end
	if not PlayerData.UnlockStyle(player, name) then
		PlayerData.Notify(player, "Estilos", `Você já tem o estilo {name}.`)
	end
end)

Admins.BindCommand("/maestria", function(player, argument)
	local styleText, levelText = string.match(argument or "", "^(%S+)%s*(%d*)$")
	local name = findStyle(styleText)
	if not name then
		PlayerData.Notify(player, "Maestria", `Use /maestria <Estilo> <nível>. Estilos: {styleNames()}.`, 6)
		return
	end
	local level = math.clamp(tonumber(levelText) or SkillTreeData.Mastery.MaxLevel, 0, SkillTreeData.Mastery.MaxLevel)
	local wanted = 0
	for step = 1, level do
		wanted += SkillTreeData.Mastery.Need(step)
	end
	local mastery = player:FindFirstChild("Mastery")
	local value = mastery and mastery:FindFirstChild(name)
	local current = if value then value.Value else 0
	if wanted > current then
		PlayerData.AddMastery(player, name, wanted - current)
	else
		PlayerData.Notify(player, "Maestria", `{name} já está no nível {level} ou acima.`)
	end
end)

Admins.BindCommand("/cacador", function(player, argument)
	local wanted = if argument and argument ~= "" then argument else "Raposa"
	local contractId
	for id in ContractData.Contracts do
		if string.lower(id) == string.lower(wanted) then
			contractId = id
		end
	end
	if not contractId or not PathModule.AdminHunter(player, contractId) then
		PlayerData.Notify(player, "Caçador", "Use /cacador <Contrato> (só contratos ativos, ex.: Raposa).", 5)
		return
	end
	PlayerData.Notify(player, "Caçador", `Agora você é Caçador com o contrato {contractId}.`, 5)
end)

Admins.BindCommand("/maestriacontrato", function(player, argument)
	local _, contractId = PathModule.GetForm(player)
	if not contractId then
		PlayerData.Notify(player, "Maestria do contrato", "Você precisa ser Caçador com um contrato (/cacador).", 5)
		return
	end
	local level = math.clamp(math.floor(tonumber(argument) or SkillTreeData.Mastery.MaxLevel), 0, SkillTreeData.Mastery.MaxLevel)
	local wanted = SkillTreeData.MasteryXP(level)
	local folder = player:FindFirstChild("ContractMastery")
	local value = folder and folder:FindFirstChild(contractId)
	local current = if value then value.Value else 0
	if wanted > current then
		PlayerData.AddContractMastery(player, contractId, wanted - current)
	else
		PlayerData.Notify(player, "Maestria do contrato", `Já está no nível {level} ou acima.`)
	end
end)

Admins.BindCommand("/forma", function(player, argument)
	local wanted
	for _, form in ContractData.FormOrder do
		if string.lower(form) == string.lower(argument or "") then
			wanted = form
		end
	end
	-- No modo híbrido a forma do contrato do V/B também muda
	local hybrid = wanted ~= nil and player:GetAttribute("Hybrid") == true
	if hybrid then
		player:SetAttribute("HybridForm", wanted)
	end
	if not wanted or (not PathModule.SetForm(player, wanted) and not hybrid) then
		PlayerData.Notify(player, "Forma", "Use /forma V1, /forma V2 ou /forma Ultimate (sendo Caçador com contrato).", 5)
		return
	end
	PlayerData.Notify(player, "Forma", `Contrato na forma {ContractData.FormNames[wanted]}.`, 4)
end)

local function giveYen(player, argument)
	local amount = math.clamp(math.floor(tonumber(argument) or 0), 0, 100000000)
	if amount <= 0 then
		PlayerData.Notify(player, "Yen", "Use /yen <quantidade> (até 100.000.000).", 5)
		return
	end
	PlayerData.AddGold(player, amount, true)
	PlayerData.Notify(player, "Yen", `+{amount} de dinheiro.`, 4)
end
Admins.BindCommand("/yen", giveYen)
Admins.BindCommand("/gold", giveYen)

-- Modo híbrido: atributos lidos pelo PathData.PlayerSkill (servidor e cliente); o caminho de verdade e o time não mudam
local function findKey(map, text)
	for id in map do
		if string.lower(id) == string.lower(text) then
			return id
		end
	end
	return nil
end

Admins.BindCommand("/hibrido", function(player, argument)
	local words = string.split(argument or "", " ")
	local first = string.lower(words[1] or "")
	if first == "off" or first == "desligar" or (first == "" and player:GetAttribute("Hybrid") == true) then
		player:SetAttribute("Hybrid", nil)
		player:SetAttribute("HybridContract", nil)
		player:SetAttribute("HybridForm", nil)
		player:SetAttribute("HybridFiend", nil)
		PlayerData.Notify(player, "Modo híbrido", "Desligado: os poderes voltam a ser os do seu caminho.", 4)
		return
	end
	local fiendType, contractId = "Sangue", "Raposa"
	for _, word in words do
		if word ~= "" then
			fiendType = findKey(PathData.FiendTypes, word) or fiendType
			contractId = findKey(ContractData.Contracts, word) or contractId
		end
	end
	if not PathData.FiendTypes[fiendType] or not PathData.Contracts[contractId] then
		PlayerData.Notify(player, "Modo híbrido", "Use /hibrido [Infernal] [Contrato] (ex.: /hibrido Sangue Raposa) ou /hibrido off.", 6)
		return
	end
	-- Forma salva desse contrato (quem já fundiu a Raposa usa os poderes da V2)
	local profile = PlayerData.GetProfile(player)
	local forms = profile and profile.Path and profile.Path.Forms
	local form = if type(forms) == "table" and ContractData.IsForm(forms[contractId]) then forms[contractId] else "V1"
	player:SetAttribute("HybridContract", contractId)
	player:SetAttribute("HybridForm", form)
	player:SetAttribute("HybridFiend", fiendType)
	player:SetAttribute("Hybrid", true)
	PlayerData.Notify(player, "Modo híbrido",
		`Contrato {PathData.Contracts[contractId].DisplayName} ({ContractData.FormNames[form]}) no V/B e {PathData.FiendTypes[fiendType].DisplayName} no H/J.`, 6)
end)

Admins.BindCommand("/restricao", function(player, argument)
	local text = string.lower(argument)
	if text ~= "on" and text ~= "off" then
		local now = if player:GetAttribute("RandomItemsRestricted") ~= false then "on" else "off"
		PlayerData.Notify(player, "Restrição", `Use /restricao on ou /restricao off. Agora: {now}.`, 5)
		return
	end
	player:SetAttribute("RandomItemsRestricted", text == "on")
	PlayerData.Notify(player, "Restrição", if text == "on"
		then "Conta simulada com sorteio pago restrito: o clã vira escolha direta."
		else "Sorteio de clã liberado de novo nesta conta.", 5)
end)

Admins.BindCommand("/esquiva", function(player, argument)
	-- /esquiva 100% (ou outro número com %): chance fixa, salva no perfil; /esquiva normal volta à chance normal
	local percent = tonumber(string.match(argument, "^([%d%.]+)%s*%%$"))
	if percent then
		PlayerData.SetDodgeForced(player, percent / 100)
		PlayerData.Notify(player, "Esquiva", `Esquiva fixa em {math.floor(math.clamp(percent, 0, 100) + 0.5)}% (salva no perfil). `
			.. "Para voltar ao normal: /esquiva normal.", 6)
		return
	end
	if string.lower(argument) == "normal" then
		PlayerData.SetDodgeForced(player, nil)
		PlayerData.Notify(player, "Esquiva", `Esquiva normal de novo (nível {PlayerData.GetDodgeLevel(player)}).`, 5)
		return
	end
	local level = tonumber(argument)
	if not level then
		local forced = player:GetAttribute("DodgeForced")
		PlayerData.Notify(player, "Esquiva", `Use /esquiva <0-5>, /esquiva <n>% ou /esquiva normal. Agora: nível {PlayerData.GetDodgeLevel(player)}`
			.. (if type(forced) == "number" then `, fixa em {math.floor(forced * 100 + 0.5)}%.` else "."), 6)
		return
	end
	PlayerData.SetDodgeLevel(player, level)
	local chance = player:GetAttribute("TreeDodgeChance")
	PlayerData.Notify(player, "Esquiva", `Nível {PlayerData.GetDodgeLevel(player)} (chance total sem o caminho: `
		.. `{math.floor((if type(chance) == "number" then chance else 0) * 100 + 0.5)}%).`, 5)
end)

Admins.BindCommand("/treinador", function(player, argument)
	local word = string.lower(argument or "")
	local mode = if word == "duelo" or word == "duel" then "Duel" elseif word == "treino" or word == "" then "Spar" else nil
	if not mode then
		PlayerData.Notify(player, "Treinador", "Use /treinador treino ou /treinador duelo (perto do NPC Treinador).", 5)
		return
	end
	local TrainerService = require(ServerScriptService:WaitForChild("TrainerService"))
	if not TrainerService.Start(player, mode, "Treinador", nil) then
		PlayerData.Notify(player, "Treinador", "Não deu para começar: o NPC Treinador (tag QuestGiver, NPCId Treinador) está no mapa?", 5)
	end
end)

Admins.BindCommand("/pontos", function(player, argument)
	local amount = math.clamp(math.floor(tonumber(argument) or 0), 0, 500)
	if amount <= 0 then
		PlayerData.Notify(player, "Pontos", "Use /pontos <quantidade> (até 500).")
		return
	end
	PlayerData.AddStatusPoints(player, amount)
	PlayerData.Notify(player, "Pontos", `+{amount} pontos na árvore de habilidades (M).`)
end)

Admins.BindCommand("/chefe", function(player, argument)
	local name = string.match(argument or "", "^%s*(.-)%s*$")
	if name == "" then
		PlayerData.Notify(player, "Chefe", "Use /chefe <Nome> (ex.: /chefe Denji).", 5)
		return
	end
	local service = ServerScriptService:FindFirstChild("BossService")
	local control = service and service:FindFirstChild("BossControl")
	if not control then
		PlayerData.Notify(player, "Chefe", "O BossService não está rodando.", 5)
		return
	end
	local _, message = control:Invoke("Spawn", name)
	PlayerData.Notify(player, "Chefe", tostring(message), 5)
end)

Admins.BindCommand("/destruir", function(player, argument)
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if not root then return end
	local radius = math.clamp(tonumber(argument) or 10, 2, 24)
	local Destruction = require(ServerScriptService:WaitForChild("Destruction"))
	local position = root.Position + root.CFrame.LookVector * (radius * 0.6)
	local counts = Destruction.Explain(position, radius)
	local broken = Destruction.Blast(position, radius, { Power = 60 })
	local parts = {}
	for reason, count in counts do
		table.insert(parts, `{reason}: {count}`)
	end
	local summary = if #parts > 0 then table.concat(parts, " · ") else "nenhuma peça perto"
	print(`[Destruição] /destruir de {player.Name}: quebrou {broken}. Perto: {summary}`)
	if workspace:GetAttribute("DestructionDisabled") == true then
		summary = "DESLIGADA (workspace.DestructionDisabled). " .. summary
	end
	PlayerData.Notify(player, "Destruição", `Quebrou {broken}. Perto: {summary}`, 10)
end)
