-- Criador de personagem e clãs no servidor. Veste a aparência salva no personagem (ao nascer e ao salvar), sorteia o
-- clã do primeiro acesso e atende o menu principal (MainMenu.client): SaveAppearance, ClanSpin, BuySpin, ClanChoose e
-- RedeemCode. Contas com item aleatório pago restrito pelo Roblox (PolicyService; menores no Brasil) não giram nem
-- compram giro: escolhem o clã pagando Gold (ClanData.ChooseGoldCost), com os giros guardados valendo como crédito.
-- Publica no player os atributos que o menu lê: Appearance (JSON do AppearanceData), CharacterCreated, Clan (Id do
-- ClanData) e ClanSpins. Os dados ficam no perfil do PlayerData (Appearance, Created, Clan, Spins, Codes).
-- O avatar do Roblox não carrega: no Studio o StarterPlayer tem LoadCharacterAppearance = false e um StarterCharacter
-- R6 liso; aqui o CanLoadCharacterAppearance também é desligado em cada jogador, por garantia.
-- Física dos cabelos: o módulo do SmartBone fica em ServerStorage.SmartBone (fora do Argon, que não conseguia manter ele
-- dentro do VFX) e é copiado para ReplicatedStorage.VFX ao iniciar, onde o SmartBoneRunner do cliente procura.
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local PolicyService = game:GetService("PolicyService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage = game:GetService("ServerStorage")

local Remotes = require(ReplicatedStorage:WaitForChild("Remotes"))
local AppearanceData = require(ReplicatedStorage:WaitForChild("AppearanceData"))
local ClanData = require(ReplicatedStorage:WaitForChild("ClanData"))
local PlayerData = require(ServerScriptService:WaitForChild("PlayerData"))
local Codes = require(script.Parent:WaitForChild("Codes"))

local SAVE_GAP = 1 -- segundos entre dois pedidos de salvar a aparência
local SPIN_GAP = 2.5 -- o giro tem animação no menu: no máximo um a cada 2,5 s
local BUY_GAP = 0.4
local CODE_GAP = 1.5
local MAX_CODE_LENGTH = 32
local LEGENDARY_ANNOUNCE_DELAY = 4 -- o anúncio para o servidor sai depois da animação do giro

local rng = Random.new()
local lastRequest = {} -- [player] = { [tipo] = os.clock() }

local function throttled(player, kind, gap)
	local times = lastRequest[player]
	if not times then
		times = {}
		lastRequest[player] = times
	end
	local now = os.clock()
	if now - (times[kind] or 0) < gap then
		return true
	end
	times[kind] = now
	return false
end

local function publish(player, profile)
	player:SetAttribute("Appearance", HttpService:JSONEncode(profile.Appearance))
	player:SetAttribute("CharacterCreated", profile.Created)
	player:SetAttribute("Clan", profile.Clan)
	player:SetAttribute("ClanSpins", profile.Spins)
end

-- Veste a aparência do perfil no personagem atual (com a física do cabelo ligada)
local function dress(player, profile)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 or not character:FindFirstChild("Head") then return end
	AppearanceData.Apply(character, profile.Appearance, { Physics = true })
end

local function setClan(player, profile, clanId)
	profile.Clan = clanId
	PlayerData.RefreshEffects(player)
	publish(player, profile)
end

local function onProfileLoaded(player)
	local profile = PlayerData.GetProfile(player)
	if not profile then return end
	-- Primeiro acesso: o clã sai de graça (os giros guardados servem para tentar outro)
	if ClanData.Get(profile.Clan) then
		publish(player, profile)
	else
		setClan(player, profile, ClanData.Roll(rng))
	end
	dress(player, profile)
end

local function onCharacterAdded(player, character)
	if not character:WaitForChild("Head", 10) then return end
	local profile = PlayerData.GetProfile(player)
	if profile then
		dress(player, profile)
	end
end

-- Item aleatório pago restrito para a conta (PolicyService). Sem resposta do Roblox, vale a regra mais segura
-- (restrito). O comando de admin /restricao troca o atributo para testar (ItemCommands).
local function restricted(player)
	return player:GetAttribute("RandomItemsRestricted") ~= false
end

local function loadPolicy(player)
	for attempt = 1, 3 do
		local ok, info = pcall(function()
			return PolicyService:GetPolicyInfoForPlayerAsync(player)
		end)
		if ok and type(info) == "table" then
			if player.Parent and player:GetAttribute("RandomItemsRestricted") == nil then
				player:SetAttribute("RandomItemsRestricted", info.ArePaidRandomItemsRestricted == true)
			end
			return
		end
		task.wait(attempt * 2)
	end
	if player.Parent and player:GetAttribute("RandomItemsRestricted") == nil then
		player:SetAttribute("RandomItemsRestricted", true)
	end
end

local function onPlayerAdded(player)
	player.CanLoadCharacterAppearance = false
	task.spawn(loadPolicy, player)
	player.CharacterAdded:Connect(function(character)
		onCharacterAdded(player, character)
	end)
	if player.Character then
		task.spawn(onCharacterAdded, player, player.Character)
	end
end

-- ================= Pedidos do menu =================

local function onSaveAppearance(player, appearance)
	if type(appearance) ~= "table" or throttled(player, "Save", SAVE_GAP) then return end
	local profile = PlayerData.GetProfile(player)
	if not profile then return end
	profile.Appearance = AppearanceData.Sanitize(appearance)
	profile.Created = true
	publish(player, profile)
	dress(player, profile)
end

local function onClanSpin(player)
	if throttled(player, "Spin", SPIN_GAP) then return end
	local profile = PlayerData.GetProfile(player)
	if not profile then return end
	if profile.Spins < 1 or restricted(player) then
		-- Resposta vazia: o menu destrava o botão e mostra como conseguir giros (ou a escolha direta)
		Remotes.ClanResult:FireClient(player, nil, profile.Spins)
		return
	end
	profile.Spins -= 1
	local clanId = ClanData.Roll(rng)
	setClan(player, profile, clanId)
	Remotes.ClanResult:FireClient(player, clanId, profile.Spins)

	local clan = ClanData.Get(clanId)
	if clan.Rarity == "Lendário" then
		task.delay(LEGENDARY_ANNOUNCE_DELAY, function()
			if player.Parent then
				Remotes.Announcement:FireAllClients("Clã lendário!", `{player.DisplayName} tirou o clã {clan.Name} {clan.Kanji}!`, 6)
			end
		end)
	end
end

local function onBuySpin(player)
	if throttled(player, "Buy", BUY_GAP) then return end
	local profile = PlayerData.GetProfile(player)
	if not profile then return end
	if restricted(player) then
		PlayerData.Notify(player, "Clã", "Na sua conta não tem giro pago: escolha o clã direto na lista.")
		return
	end
	if not PlayerData.SpendGold(player, ClanData.SpinGoldCost) then
		PlayerData.Notify(player, "Clã", `Um giro custa {ClanData.SpinGoldCost} Gold.`)
		return
	end
	profile.Spins += 1
	publish(player, profile)
end

-- Escolha direta (só contas com sorteio pago restrito): paga o preço da raridade, primeiro com os giros guardados
local function onClanChoose(player, clanId)
	if throttled(player, "Choose", BUY_GAP) then return end
	local profile = PlayerData.GetProfile(player)
	local clan = ClanData.Get(clanId)
	if not profile or not clan or not restricted(player) then return end
	if profile.Clan == clan.Id then
		Remotes.ClanResult:FireClient(player, nil, profile.Spins)
		return
	end
	local credits, gold = ClanData.ChooseCost(clan.Id, profile.Spins)
	if gold > 0 and not PlayerData.SpendGold(player, gold) then
		PlayerData.Notify(player, "Clã", `Faltou Gold: o clã {clan.Name} custa {gold} Gold além dos créditos.`)
		Remotes.ClanResult:FireClient(player, nil, profile.Spins)
		return
	end
	profile.Spins -= credits
	setClan(player, profile, clan.Id)
	Remotes.ClanResult:FireClient(player, clan.Id, profile.Spins)
end

-- "  pochita " -> "POCHITA" (nil se não servir)
local function normalizeCode(text)
	if type(text) ~= "string" or #text > MAX_CODE_LENGTH * 4 then return nil end
	local code = string.upper((string.gsub(text, "%s", "")))
	if code == "" or #code > MAX_CODE_LENGTH then return nil end
	return code
end

local function onRedeemCode(player, text)
	if throttled(player, "Code", CODE_GAP) then return end
	local profile = PlayerData.GetProfile(player)
	if not profile then return end
	local code = normalizeCode(text)
	local entry = code and Codes[code]
	if type(entry) ~= "table" then
		Remotes.CodeResult:FireClient(player, false, "Código inválido.")
		return
	end
	if type(entry.Expires) == "number" and os.time() > entry.Expires then
		Remotes.CodeResult:FireClient(player, false, "Esse código expirou.")
		return
	end
	if profile.Codes[code] then
		Remotes.CodeResult:FireClient(player, false, "Você já usou esse código.")
		return
	end

	profile.Codes[code] = true
	local rewards = {}
	if type(entry.Spins) == "number" and entry.Spins > 0 then
		profile.Spins += math.floor(entry.Spins)
		table.insert(rewards, `+{math.floor(entry.Spins)} giros de clã`)
	end
	if type(entry.Gold) == "number" and entry.Gold > 0 then
		PlayerData.AddGold(player, math.floor(entry.Gold), true)
		table.insert(rewards, `+{math.floor(entry.Gold)} Gold`)
	end
	if type(entry.XP) == "number" and entry.XP > 0 then
		PlayerData.AddXP(player, math.floor(entry.XP), true)
		table.insert(rewards, `+{math.floor(entry.XP)} XP`)
	end
	publish(player, profile)
	local message = entry.Message or `Código resgatado: {table.concat(rewards, ", ")}.`
	Remotes.CodeResult:FireClient(player, true, message)
end

-- ================= Início =================

task.spawn(function()
	local source = ServerStorage:FindFirstChild("SmartBone")
	local vfx = ReplicatedStorage:WaitForChild("VFX", 10)
	if not source then
		warn("[CharacterService] ServerStorage.SmartBone não existe: cabelos sem física")
	elseif vfx and not vfx:FindFirstChild("SmartBone") then
		source:Clone().Parent = vfx
	end
end)

Players.PlayerAdded:Connect(onPlayerAdded)
for _, player in Players:GetPlayers() do
	onPlayerAdded(player)
end
Players.PlayerRemoving:Connect(function(player)
	lastRequest[player] = nil
end)

PlayerData.ProfileLoaded:Connect(onProfileLoaded)
for _, player in Players:GetPlayers() do
	if PlayerData.GetProfile(player) then
		task.spawn(onProfileLoaded, player)
	end
end

Remotes.SaveAppearance.OnServerEvent:Connect(onSaveAppearance)
Remotes.ClanSpin.OnServerEvent:Connect(onClanSpin)
Remotes.BuySpin.OnServerEvent:Connect(onBuySpin)
Remotes.ClanChoose.OnServerEvent:Connect(onClanChoose)
Remotes.RedeemCode.OnServerEvent:Connect(onRedeemCode)
