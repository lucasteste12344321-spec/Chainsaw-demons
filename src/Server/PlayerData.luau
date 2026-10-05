
local DataStoreService = game:GetService("DataStoreService")
local TeleportService = game:GetService("TeleportService")
local Debris = game:GetService("Debris")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Remotes = require(ReplicatedStorage:WaitForChild("Remotes"))
local StatConfig = require(ReplicatedStorage:WaitForChild("StatConfig"))
local PathData = require(ReplicatedStorage:WaitForChild("PathData"))
local ItemData = require(ReplicatedStorage:WaitForChild("ItemData"))
local SkillTreeData = require(ReplicatedStorage:WaitForChild("SkillTreeData"))
local ClanData = require(ReplicatedStorage:WaitForChild("ClanData"))
local AppearanceData = require(ReplicatedStorage:WaitForChild("AppearanceData"))
local CombatStyles = require(ReplicatedStorage:WaitForChild("CombatStyles"))
local TutorialData = require(ReplicatedStorage:WaitForChild("TutorialData"))
local DodgeData = require(ReplicatedStorage:WaitForChild("DodgeData"))
local ContractData = require(ReplicatedStorage:WaitForChild("ContractData"))
local QuestData = require(script.Parent:WaitForChild("QuestData"))
local FishingData = require(ReplicatedStorage:WaitForChild("FishingData"))
local DailyData = require(ReplicatedStorage:WaitForChild("DailyData"))
local MilestoneData = require(ReplicatedStorage:WaitForChild("MilestoneData"))
local WorldQuestData = require(script.Parent:WaitForChild("WorldQuestData"))

local Passes = require(script.Parent:WaitForChild("GamepassEntitlements"))
local PassConfig = require(ReplicatedStorage:WaitForChild("GamepassConfig"))
local VIPRules = require(script.Parent:WaitForChild("VIPRewardRules"))
local PlayerData = {}

-- Mantidos aqui para quem já usava PlayerData.BaseStats etc.
PlayerData.BaseStats = StatConfig.BaseStats
PlayerData.StatGain = StatConfig.StatGain
PlayerData.StatMax = StatConfig.StatMax
PlayerData.PointsPerLevel = StatConfig.PointsPerLevel
PlayerData.XPNeeded = StatConfig.XPNeeded

local DATASTORE_NAME = "PlayerData_v1"
local DATA_VERSION = 1
local AUTOSAVE_INTERVAL = 120
local MAX_RETRIES = 3

-- Saves (pedido do usuário, 2026-10-05): até SLOT_COUNT personagens por conta, tudo separado (level, Gold, clã,
-- itens, códigos...). O 1º é grátis e usa a chave antiga (ninguém perde o progresso); os outros pedem o passe
-- ExtraSlots (GamepassConfig). O perfil só carrega depois que o jogador escolhe o save na tela SaveSelect.client.
local SLOT_COUNT = 3
local FREE_SLOTS = 1
PlayerData.SlotCount = SLOT_COUNT
PlayerData.FreeSlots = FREE_SLOTS

-- Efeitos que não são stats viram atributos Tree<Efeito> (todos os que aparecem em algum nó da árvore ou item)
local EFFECT_KEYS = {}
local function addEffectKeys(effects)
	for key in effects do
		if key ~= "Technique" and StatConfig.BaseStats[key] == nil then
			EFFECT_KEYS[key] = true
		end
	end
end
for _, entry in SkillTreeData.Nodes do
	addEffectKeys(entry.Effects)
end
for _, item in ItemData.Items do
	addEffectKeys(item.Effects or {})
end
for _, clan in ClanData.Clans do
	addEffectKeys(clan.Effects)
end

local EQUIP_GAP = 0.25 -- intervalo mínimo entre dois pedidos de equipar do mesmo jogador
local EQUIPPED_ATTRIBUTE = "EquippedItem" -- no Accessory vestido: o Id do item

local store
do
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(DATASTORE_NAME)
	end)
	if ok then
		store = result
	else
		warn("[PlayerData] DataStore indisponível, os dados não serão salvos: " .. tostring(result))
	end
end

-- profiles[player] = { Quests, Path, Settings, Items, Equipped, Tree, Mastery, BonusPoints, Appearance, Created, Clan,
--   Spins, Codes, Styles, HiddenStyles, Tutorial, ContractMastery, DodgeLevel, DodgeForced, CanSave }
local profiles = {}
local loading = {}
local activeSaves = 0
local saving = {}

local loadedEvent = Instance.new("BindableEvent")
PlayerData.ProfileLoaded = loadedEvent.Event -- (player)

-- Caminho padrão: Humano comum, sem contratos, tempo de vida cheio, proteção de aliados ligada
local function defaultPath()
	return {
		Path = "None",
		Contracts = {},
		FiendType = "",
		Lifespan = PathData.MaxLifespan,
		PathResets = 0,
		AllyProtection = true,
		Forms = {}, -- [contrato] = "V1" | "V2" | "Ultimate" (ContractData); fica salvo mesmo renunciando ao caminho
	}
end

-- Configurações que o cliente pode salvar (o tipo do padrão é o único aceito)
local DEFAULT_SETTINGS = {
	FastMode = false,
	AutoRun = true, -- corrida automática (StaminaDashRunscript)
	Music = true, -- música do menu (LobbyMusic do SoundService; o menu principal liga e desliga)
}

local function defaultSettings()
	return table.clone(DEFAULT_SETTINGS)
end

local function reconcileSettings(saved)
	local data = defaultSettings()
	if type(saved) == "table" then
		for key, default in DEFAULT_SETTINGS do
			if type(saved[key]) == type(default) then
				data[key] = saved[key]
			end
		end
	end
	return data
end

-- Tutorial guiado (TutorialService): passo atual, se terminou (concluiu ou pulou) e se já ganhou a recompensa
local function defaultTutorial()
	return { Step = 1, Done = false, Rewarded = false }
end

-- Perfil de antes do tutorial: quem já passou do level TutorialData.SkipForLevel não precisa dele
local function reconcileTutorial(saved, level)
	if type(saved) ~= "table" then
		local veteran = level >= TutorialData.SkipForLevel
		return { Step = 1, Done = veteran, Rewarded = veteran }
	end
	local step = if type(saved.Step) == "number" and saved.Step == saved.Step then math.floor(saved.Step) else 1
	return {
		Step = math.clamp(step, 1, TutorialData.Count),
		Done = saved.Done == true,
		Rewarded = saved.Rewarded == true,
	}
end

local function defaultData()
	return {
		Version = DATA_VERSION,
		Level = 1,
		XP = 0,
		Gold = 0,
		Quests = { Active = {}, Completed = {} },
		Fishing = FishingData.Reconcile(nil),
		WorldActivities = WorldQuestData.Reconcile(nil),
		VIPRewards = VIPRules.Reconcile(nil),
		Path = defaultPath(),
		Settings = defaultSettings(),
		Items = {},
		Equipped = {},
		Tree = {},
		Mastery = {},
		BonusPoints = 0,
		TreeVersion = SkillTreeData.Version,
		Appearance = AppearanceData.Default(),
		Created = false,
		Clan = "",
		Spins = ClanData.StartingSpins,
		Codes = {},
		Styles = {},
		HiddenStyles = {}, -- estilos guardados no inventário (EquipStyle)
		Tutorial = defaultTutorial(),
		Daily = DailyData.Reconcile(nil), -- missões diárias (DailyService)
		Milestones = MilestoneData.Reconcile(nil), -- marcos (MilestoneService)
		ContractMastery = {}, -- [contrato] = XP total (mesma curva da maestria dos estilos)
		DodgeLevel = 0, -- esquiva automática (DodgeData), sobe com as missões do Treinador
		-- DodgeForced (opcional): chance de esquiva fixa de admin (/esquiva <n>%), de 0 a 1 e sem o teto; nil = normal
	}
end

-- Estilos aprendidos salvos: só os que existem no CombatStyles e não são dos iniciais, sem repetir
local function reconcileStyles(saved)
	local styles = {}
	if type(saved) == "table" then
		for _, name in ipairs(saved) do
			if type(name) == "string" and CombatStyles.Styles[name] and not table.find(CombatStyles.StartingStyles, name)
				and not table.find(styles, name) then
				table.insert(styles, name)
			end
		end
	end
	return styles
end

-- Estilos que o jogador guardou no inventário (não aparecem na hotbar): só nomes que existem, sem repetir
local function reconcileHiddenStyles(saved)
	local hidden = {}
	if type(saved) == "table" then
		for _, name in ipairs(saved) do
			if type(name) == "string" and CombatStyles.Styles[name] and not table.find(hidden, name) then
				table.insert(hidden, name)
			end
		end
	end
	return hidden
end

-- Códigos já resgatados: { [CÓDIGO] = true }
local function reconcileCodes(saved)
	local codes = {}
	if type(saved) == "table" then
		for code, used in saved do
			if type(code) == "string" and used == true then
				codes[code] = true
			end
		end
	end
	return codes
end

-- Itens salvos: só Ids que existem no ItemData, com quantidade inteira positiva
local function reconcileItems(saved)
	local items = {}
	if type(saved) == "table" then
		for id, count in saved do
			if type(id) == "string" and ItemData.Get(id) and type(count) == "number" and count >= 1 then
				items[id] = math.floor(count)
			end
		end
	end
	return items
end

-- Itens equipados salvos: slot certo e item que o jogador ainda tem
local function reconcileEquipped(saved, items)
	local equipped = {}
	if type(saved) == "table" then
		for slotId, id in saved do
			local item = type(id) == "string" and ItemData.Get(id)
			if item and item.Slot == slotId and (items[id] or 0) >= 1 then
				equipped[slotId] = id
			end
		end
	end
	return equipped
end

-- Nós salvos: só os que existem (e não são os que já vêm desbloqueados), sem repetir
local function reconcileTree(saved)
	local tree = {}
	if type(saved) == "table" then
		for _, id in ipairs(saved) do
			local entry = type(id) == "string" and SkillTreeData.Get(id)
			if entry and not entry.Default and not table.find(tree, id) then
				table.insert(tree, id)
			end
		end
	end
	return tree
end

local function reconcileMastery(saved)
	local mastery = {}
	local cap = SkillTreeData.MasteryCap()
	if type(saved) == "table" then
		for style, xp in saved do
			if type(style) == "string" and type(xp) == "number" and xp == xp and xp > 0 then
				mastery[style] = math.min(cap, math.floor(xp))
			end
		end
	end
	return mastery
end

-- Maestria dos contratos: só contratos com formas (ContractData), até o teto da curva
local function reconcileContractMastery(saved)
	local mastery = {}
	local cap = SkillTreeData.MasteryCap()
	if type(saved) == "table" then
		for contractId, xp in saved do
			if ContractData.HasForms(contractId) and type(xp) == "number" and xp == xp and xp > 0 then
				mastery[contractId] = math.min(cap, math.floor(xp))
			end
		end
	end
	return mastery
end

-- Pontos de status que as missões já completas deram (perfis de antes da árvore viram pontos bônus)
local function questBonusPoints(completed)
	local total = 0
	for _, quest in QuestData.Quests do
		local count = completed[quest.Id]
		local points = quest.Rewards and quest.Rewards.StatusPoints
		if type(count) == "number" and count > 0 and type(points) == "number" then
			total += points * (if quest.Repeatable then count else 1)
		end
	end
	return total
end

local function totalPoints(level, bonus)
	return (level - 1) * StatConfig.PointsPerLevel + bonus
end

-- Valida o caminho salvo. Perfis antigos (sem Path) ficam com o padrão.
local function reconcilePath(saved)
	local data = defaultPath()
	if type(saved) ~= "table" then
		return data
	end

	if type(saved.Path) == "string" and PathData.Paths[saved.Path] then
		data.Path = saved.Path
	end

	-- Contratos: só Caçadores, só ids que existem, sem repetir, no máximo MaxContracts (desde 2026-10-01, um só:
	-- quem tinha dois fica com o primeiro)
	if data.Path == "Hunter" and type(saved.Contracts) == "table" then
		for _, contractId in ipairs(saved.Contracts) do
			if #data.Contracts >= PathData.MaxContracts then break end
			if type(contractId) == "string" and PathData.Contracts[contractId] and not table.find(data.Contracts, contractId) then
				table.insert(data.Contracts, contractId)
			end
		end
	end
	-- Contrato desativado (ContractData.Enabled = false) ou Caçador sem contrato: vira Raposa
	if data.Path == "Hunter" and (#data.Contracts == 0 or not ContractData.IsEnabled(data.Contracts[1])) then
		data.Contracts = { "Raposa" }
	end
	if type(saved.Forms) == "table" then
		for contractId, form in saved.Forms do
			if ContractData.HasForms(contractId) and ContractData.IsForm(form) then
				data.Forms[contractId] = form
			end
		end
	end

	-- Infernal precisa de um tipo válido; sem ele volta a Humano comum
	if data.Path == "Fiend" then
		if type(saved.FiendType) == "string" and PathData.FiendTypes[saved.FiendType] then
			data.FiendType = saved.FiendType
		else
			data.Path = "None"
		end
	end

	if type(saved.Lifespan) == "number" and saved.Lifespan == saved.Lifespan then
		data.Lifespan = math.clamp(saved.Lifespan, 0, PathData.MaxLifespan)
	end
	if type(saved.PathResets) == "number" and saved.PathResets == saved.PathResets then
		data.PathResets = math.max(0, math.floor(saved.PathResets))
	end
	if type(saved.AllyProtection) == "boolean" then
		data.AllyProtection = saved.AllyProtection
	end

	return data
end

-- Junta o que veio do DataStore com os padrões (campos novos ganham o valor padrão)
local function reconcile(saved)
	local data = defaultData()
	if type(saved) ~= "table" then
		return data
	end

	for _, key in { "Level", "XP", "Gold" } do
		if type(saved[key]) == "number" then
			data[key] = math.floor(saved[key])
		end
	end
	-- Level máximo (perfis de antes do limite, ou de comando de admin, voltam para ele)
	data.Level = math.clamp(data.Level, 1, StatConfig.MaxLevel)
	if data.Level >= StatConfig.MaxLevel then
		data.XP = 0
	end

	if type(saved.Quests) == "table" then
		if type(saved.Quests.Active) == "table" then
			data.Quests.Active = saved.Quests.Active
		end
		if type(saved.Quests.Completed) == "table" then
			data.Quests.Completed = saved.Quests.Completed
		end
	end

	data.Fishing = FishingData.Reconcile(saved.Fishing)
	data.WorldActivities = WorldQuestData.Reconcile(saved.WorldActivities)
	data.VIPRewards = VIPRules.Reconcile(saved.VIPRewards)
	data.Path = reconcilePath(saved.Path)
	data.Settings = reconcileSettings(saved.Settings)
	data.Items = reconcileItems(saved.Items)
	data.Equipped = reconcileEquipped(saved.Equipped, data.Items)

	if type(saved.TreeVersion) == "number" then
		data.Tree = reconcileTree(saved.Tree)
		data.Mastery = reconcileMastery(saved.Mastery)
		if type(saved.BonusPoints) == "number" and saved.BonusPoints == saved.BonusPoints then
			data.BonusPoints = math.max(0, math.floor(saved.BonusPoints))
		end
	else
		-- Perfil de antes da árvore: os stats distribuídos somem; as missões já feitas viram pontos bônus
		data.BonusPoints = questBonusPoints(data.Quests.Completed)
	end
	-- Pontos gastos a mais do que tem (nós mudaram de custo): devolve tudo
	if SkillTreeData.Spent(data.Tree) > totalPoints(data.Level, data.BonusPoints) then
		data.Tree = {}
	end

	-- Personagem e clã (perfis de antes do criador ficam com o padrão e passam pelo criador na próxima entrada)
	data.Appearance = AppearanceData.Sanitize(saved.Appearance)
	data.Created = saved.Created == true
	data.Clan = if ClanData.Get(saved.Clan) then saved.Clan else ""
	if type(saved.Spins) == "number" and saved.Spins == saved.Spins then
		data.Spins = math.clamp(math.floor(saved.Spins), 0, 9999)
	end
	data.Codes = reconcileCodes(saved.Codes)
	data.Styles = reconcileStyles(saved.Styles)
	data.HiddenStyles = reconcileHiddenStyles(saved.HiddenStyles)
	data.Tutorial = reconcileTutorial(saved.Tutorial, data.Level)
	data.Daily = DailyData.Reconcile(saved.Daily)
	data.Milestones = MilestoneData.Reconcile(saved.Milestones)
	data.ContractMastery = reconcileContractMastery(saved.ContractMastery)
	if type(saved.DodgeLevel) == "number" and saved.DodgeLevel == saved.DodgeLevel then
		data.DodgeLevel = math.clamp(math.floor(saved.DodgeLevel), 0, DodgeData.MaxLevel)
	end
	if type(saved.DodgeForced) == "number" and saved.DodgeForced == saved.DodgeForced then
		data.DodgeForced = math.clamp(saved.DodgeForced, 0, 1)
	end

	return data
end

local function dataKey(player, slot)
	if not slot or slot <= 1 then
		return "Player_" .. player.UserId
	end
	return `Player_{player.UserId}_S{slot}`
end

-- No Studio sem "Enable Studio Access to API Services" não adianta tentar de novo
local function isAccessDenied(err)
	local message = tostring(err):lower()
	return message:find("studio", 1, true) ~= nil or message:find("403", 1, true) ~= nil
end

local function loadData(player, slot)
	if not store then
		return defaultData(), false
	end

	for attempt = 1, MAX_RETRIES do
		local ok, result = pcall(function()
			return store:GetAsync(dataKey(player, slot))
		end)
		if ok then
			return reconcile(result), true
		end
		warn(`[PlayerData] Falha ao carregar {player.Name} (tentativa {attempt}): {result}`)
		if isAccessDenied(result) then
			break
		end
		task.wait(attempt)
	end

	return defaultData(), false
end

local function serialize(player)
	local profile = profiles[player]
	local leaderstats = player:FindFirstChild("leaderstats")
	local progress = player:FindFirstChild("Progress")
	if not profile or not leaderstats or not progress then
		return nil
	end

	return {
		Version = DATA_VERSION,
		Level = leaderstats.Level.Value,
		Gold = leaderstats.Gold.Value,
		XP = progress.XP.Value,
		Quests = profile.Quests,
		Fishing = profile.Fishing,
		WorldActivities = profile.WorldActivities,
		VIPRewards = VIPRules.Reconcile(profile.VIPRewards),
		Path = profile.Path,
		Settings = profile.Settings,
		Items = profile.Items,
		Equipped = profile.Equipped,
		Tree = profile.Tree,
		Mastery = profile.Mastery,
		BonusPoints = profile.BonusPoints,
		TreeVersion = SkillTreeData.Version,
		Appearance = profile.Appearance,
		Created = profile.Created,
		Clan = profile.Clan,
		Spins = profile.Spins,
		Codes = profile.Codes,
		Styles = profile.Styles,
		HiddenStyles = profile.HiddenStyles,
		Tutorial = profile.Tutorial,
		Daily = profile.Daily,
		Milestones = profile.Milestones,
		ContractMastery = profile.ContractMastery,
		DodgeLevel = profile.DodgeLevel,
		DodgeForced = profile.DodgeForced,
	}
end

-- Serialize autosave, leaving and daily claims through the same per-player writer.
local function persist(player, claimDay)
	local profile = profiles[player]
	if not profile or not profile.CanSave or not store then return false end
	activeSaves += 1
	while saving[player] do task.wait(.05) end
	saving[player] = true
	local data = profiles[player] == profile and serialize(player)
	local success, result = false, nil
	if data then
		for attempt = 1, MAX_RETRIES do
			local ok, value = pcall(function()
				return store:UpdateAsync(dataKey(player, profile.Slot), function(old)
					return VIPRules.Merge(data, old, claimDay)
				end)
			end)
			if ok then success = true; result = value; break end
			warn(`[PlayerData] Falha ao salvar {player.Name} (tentativa {attempt}): {value}`)
			task.wait(attempt)
		end
	end
	local granted = 0
	if success and type(result) == "table" then
		local vip = VIPRules.Reconcile(result.VIPRewards)
		granted = math.max(0, vip.Total - profile.VIPRewards.Total)
		-- Preserve spins spent/earned while UpdateAsync yielded.
		profile.Spins = math.clamp(profile.Spins + granted, 0, PassConfig.MaxSpins)
		profile.VIPRewards = vip
		if player.Parent then player:SetAttribute("ClanSpins", profile.Spins) end
	end
	saving[player] = nil; activeSaves -= 1
	return success, granted
end
local function savePlayer(player) return persist(player) end

function PlayerData.ClaimVIPDaily(player)
	if not Passes.Owns(player, "VIP") then return false, "The VIP pass is required." end
	local profile = profiles[player]
	if not profile or not profile.CanSave then return false, "Wait for your data to finish loading safely and try again." end
	local day = PassConfig.Day(os.time())
	if profile.VIPRewards.Day >= day then return false, "You already got today's spins. They reset at midnight Brasília time (UTC-3)." end
	if profile.Spins > PassConfig.MaxSpins - PassConfig.DailySpins then return false, "Use some spins before claiming the 5 daily ones." end
	local ok, granted = persist(player, day)
	if not ok then return false, "Could not save the perk. Try again; today's claim was not used up." end
	return granted > 0, if granted > 0 then nil else "Today's perk was already claimed."
end

local function newInt(name, value, parent)
	local v = Instance.new("IntValue")
	v.Name = name
	v.Value = value
	v.Parent = parent
	return v
end

function PlayerData.GetProfile(player)
	return profiles[player]
end

-- Estilo da fusão do contrato (ContractData, forma V2 em diante) ou nil. Com a fusão, é o único estilo que dá para usar.
local function fusionStyleOf(player)
	local path, contracts, _, form = PathData.FromPlayer(player)
	if path ~= "Hunter" or ContractData.FormRank(form) < 2 then return nil end
	local _, style = ContractData.Fusion(contracts[1], form)
	return style
end

-- Estilos com Tool (hotbar): os aprendidos menos os guardados no inventário; com a fusão do contrato, só o estilo dela.
-- Sempre fica pelo menos um.
local function equippedStyles(player, profile)
	local learned = table.clone(CombatStyles.StartingStyles)
	for _, name in profile.Styles do
		table.insert(learned, name)
	end
	local fusion = fusionStyleOf(player)
	if fusion and table.find(learned, fusion) then
		return { fusion }, learned
	end
	local list = {}
	for _, name in learned do
		if not table.find(profile.HiddenStyles, name) then
			table.insert(list, name)
		end
	end
	if #list == 0 then
		list = { learned[1] }
	end
	return list, learned
end

-- Atributos do player: Styles (JSON com todos os estilos dele, os iniciais primeiro) e EquippedStyles (os que têm
-- Tool agora; o GiveTools entrega e tira as ferramentas por ele)
local function publishStyles(player, profile)
	local equipped, learned = equippedStyles(player, profile)
	player:SetAttribute("Styles", HttpService:JSONEncode(learned))
	player:SetAttribute("EquippedStyles", HttpService:JSONEncode(equipped))
	player:SetAttribute("StyleFusion", fusionStyleOf(player)) -- estilo travado pela fusão (o inventário mostra)
end

-- Espera os dados do jogador carregarem. Devolve nil se ele sair antes.
function PlayerData.WaitForProfile(player)
	while player.Parent and not profiles[player] do
		task.wait(0.1)
	end
	return profiles[player]
end

function PlayerData.Notify(player, title, text, duration)
	Remotes.Notify:FireClient(player, title, text, duration)
end

function PlayerData.GetStat(player, name)
	local stats = player:FindFirstChild("Stats")
	local stat = stats and stats:FindFirstChild(name)
	return stat and stat.Value or StatConfig.BaseStats[name] or 0
end

function PlayerData.GetLevel(player)
	local leaderstats = player:FindFirstChild("leaderstats")
	local level = leaderstats and leaderstats:FindFirstChild("Level")
	return level and level.Value or 1
end

-- Dá Gold. Ganhos (amount > 0) somam o bônus de Gold do clã, a não ser com noBonus (códigos, devoluções).
function PlayerData.AddGold(player, amount, noBonus, passBonus)
	local leaderstats = player:FindFirstChild("leaderstats")
	local gold = leaderstats and leaderstats:FindFirstChild("Gold")
	if gold then
		if amount > 0 and not noBonus then
			amount = math.floor(amount * (1 + PlayerData.GetTreeEffect(player, "GoldBonus")) + 0.5)
		end
		if amount > 0 and (not noBonus or passBonus) then amount = math.floor(amount * Passes.Multiplier(player, "DoubleGold") + .5) end
		gold.Value += amount
		return amount
	end
end

-- Tira Gold do jogador. Devolve false (sem tirar nada) se ele não tiver o suficiente.
function PlayerData.SpendGold(player, amount)
	if type(amount) ~= "number" or amount ~= amount or amount < 0 or amount == math.huge then
		return false
	end
	local leaderstats = player:FindFirstChild("leaderstats")
	local gold = leaderstats and leaderstats:FindFirstChild("Gold")
	if not gold then return false end

	amount = math.ceil(amount)
	if gold.Value < amount then
		return false
	end
	gold.Value -= amount
	return true
end

-- Vida máxima: Stats.HP vezes o multiplicador do caminho (contratos tiram vida, Infernal ganha +15%).
-- O caminho é lido dos atributos do player, que o PathModule escreve.
local function maxHealthFor(player)
	local multiplier = PathData.HPMultiplier(PathData.FromPlayer(player))
	return math.max(1, math.floor(PlayerData.GetStat(player, "HP") * multiplier + 0.5))
end

-- Aplica a vida máxima no Humanoid. Se refill, enche a vida; senão mantém o dano que já levou.
local function applyHealth(player, refill)
	local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then return end

	local newMax = maxHealthFor(player)
	local missing = math.max(0, humanoid.MaxHealth - humanoid.Health)
	humanoid.MaxHealth = newMax
	humanoid.Health = if refill then newMax else math.max(newMax - missing, 1)
end

-- Reaplica a vida máxima sem encher a vida (usado quando o caminho ou os contratos mudam)
function PlayerData.RefreshHealth(player)
	applyHealth(player, false)
end

-- ================= Árvore de habilidades e maestria =================

local function masteryLevels(profile)
	local levels = {}
	for style, xp in profile.Mastery do
		levels[style] = (SkillTreeData.MasteryLevel(xp))
	end
	return levels
end

local function availablePoints(player, profile)
	return totalPoints(PlayerData.GetLevel(player), profile.BonusPoints) - SkillTreeData.Spent(profile.Tree)
end

-- Pontos livres no Progress.StatusPoints (a HUD e a tela da árvore leem daqui)
local function refreshPoints(player)
	local profile = profiles[player]
	local progress = player:FindFirstChild("Progress")
	local points = progress and progress:FindFirstChild("StatusPoints")
	if profile and points then
		points.Value = math.max(0, availablePoints(player, profile))
	end
end

-- Aplica a árvore, os itens equipados, o clã e o treino de esquiva: stats (base + nós + itens + clã), atributos
-- Tree<Efeito> e Tech_<Técnica>, as listas para as telas (SkillTree e Equipped) e a vida máxima
local function applyTree(player, profile)
	local effects, techniques = SkillTreeData.Compute(SkillTreeData.UnlockedSet(profile.Tree))
	local dodge = { DodgeChance = DodgeData.Chance(profile.DodgeLevel) }
	player:SetAttribute("DodgeLevel", profile.DodgeLevel or 0)
	player:SetAttribute("DodgeForced", profile.DodgeForced)
	for _, extra in { ItemData.Compute(profile.Equipped), ClanData.Compute(profile.Clan), dodge } do
		for key, value in extra do
			if type(value) == "boolean" then
				effects[key] = effects[key] or value
			else
				effects[key] = (effects[key] or 0) + value
			end
		end
	end
	local stats = player:FindFirstChild("Stats")
	if stats then
		for name, base in StatConfig.BaseStats do
			local stat = stats:FindFirstChild(name) or newInt(name, base, stats)
			stat.Value = base + math.floor(effects[name] or 0)
		end
	end
	for key in EFFECT_KEYS do
		local value = effects[key]
		player:SetAttribute("Tree" .. key, if value == nil or value == 0 or value == false then nil else value)
	end
	for id in SkillTreeData.Techniques do
		player:SetAttribute("Tech_" .. id, if techniques[id] then true else nil)
	end
	player:SetAttribute("SkillTree", HttpService:JSONEncode(profile.Tree))
	player:SetAttribute("Equipped", HttpService:JSONEncode(profile.Equipped))
	applyHealth(player, false)
end

-- Recalcula stats e efeitos (depois de trocar o clã, por exemplo)
function PlayerData.RefreshEffects(player)
	local profile = profiles[player]
	if profile then
		applyTree(player, profile)
	end
end

-- ================= Esquiva automática (DodgeData) =================

function PlayerData.GetDodgeLevel(player)
	local profile = profiles[player]
	return if profile then profile.DodgeLevel or 0 else 0
end

-- Muda o nível da esquiva (recompensa das missões do Treinador, comando de admin). Devolve true se mudou.
function PlayerData.SetDodgeLevel(player, level)
	local profile = profiles[player]
	if not profile or type(level) ~= "number" or level ~= level then return false end
	level = math.clamp(math.floor(level), 0, DodgeData.MaxLevel)
	if profile.DodgeLevel == level then return false end
	profile.DodgeLevel = level
	applyTree(player, profile)
	return true
end

-- Chance de esquiva fixa de admin (/esquiva <n>%): de 0 a 1, vale no lugar da soma e sem o teto do DodgeData
-- (CombatRules lê o atributo DodgeForced). nil volta ao normal. Fica salva no perfil.
function PlayerData.SetDodgeForced(player, chance)
	local profile = profiles[player]
	if not profile then return false end
	profile.DodgeForced = if type(chance) == "number" and chance == chance then math.clamp(chance, 0, 1) else nil
	player:SetAttribute("DodgeForced", profile.DodgeForced)
	return true
end

-- ================= Estilos de combate =================

-- Todos os estilos do jogador (os iniciais + os aprendidos), na ordem em que chegaram
function PlayerData.GetStyles(player)
	local list = table.clone(CombatStyles.StartingStyles)
	local profile = profiles[player]
	for _, name in (if profile then profile.Styles else {}) do
		table.insert(list, name)
	end
	return list
end

function PlayerData.HasStyle(player, name)
	return table.find(PlayerData.GetStyles(player), name) ~= nil
end

-- Ensina um estilo (recompensa de missão, comando de admin). Devolve true se ele era novo. O GiveTools entrega o
-- Tool assim que o atributo Styles muda.
function PlayerData.UnlockStyle(player, name)
	local profile = profiles[player]
	local style = CombatStyles.Styles[name]
	if not profile or not style or PlayerData.HasStyle(player, name) then return false end
	table.insert(profile.Styles, name)
	publishStyles(player, profile)
	local slot = #PlayerData.GetStyles(player)
	PlayerData.Notify(player, "New combat style!", `{style.DisplayName}: press {slot} to equip it. Its techniques unlock in the skill tree (M).`, 7)
	return true
end

-- Estilos que estão com Tool agora (os aprendidos menos os guardados; com a fusão do contrato, só o dela)
function PlayerData.GetEquippedStyles(player)
	local profile = profiles[player]
	if not profile then return table.clone(CombatStyles.StartingStyles) end
	return (equippedStyles(player, profile))
end

-- Guarda ou equipa um estilo pelo inventário (Remotes.EquipStyle). Devolve (ok, motivo)
function PlayerData.SetStyleEquipped(player, name, equip)
	local profile = profiles[player]
	if not profile then return false, "Your data is still loading." end
	if not PlayerData.HasStyle(player, name) then return false, "You do not know that style." end
	local fusion = fusionStyleOf(player)
	if fusion then
		local contract = PathData.Contracts[(select(2, PathData.FromPlayer(player)))[1]]
		local name2 = if contract then contract.DisplayName else "contract"
		return false, `Your {SkillTreeData.StyleName(fusion)} are fused with the {name2}: it is the only style you can use.`
	end
	local index = table.find(profile.HiddenStyles, name)
	if equip then
		if not index then return false, nil end
		table.remove(profile.HiddenStyles, index)
	else
		if index then return false, nil end
		local equipped = equippedStyles(player, profile)
		if #equipped <= 1 and equipped[1] == name then
			return false, "You need at least one style equipped."
		end
		table.insert(profile.HiddenStyles, name)
	end
	publishStyles(player, profile)
	return true, nil
end

-- Tem a técnica (desbloqueada na árvore)? Os atributos são do servidor: o cliente não consegue mudar.
function PlayerData.HasTechnique(player, techniqueId)
	return player:GetAttribute("Tech_" .. techniqueId) == true
end

-- Valor de um efeito da árvore (0 ou false se o jogador não tem)
function PlayerData.GetTreeEffect(player, key)
	local value = player:GetAttribute("Tree" .. key)
	if value == nil then
		return if key == "DoubleJump" then false else 0
	end
	return value
end

function PlayerData.GetMasteryLevel(player, style)
	local profile = profiles[player]
	return if profile then (SkillTreeData.MasteryLevel(profile.Mastery[style] or 0)) else 0
end

-- Aviso de forma ao alcance (ContractData): a maestria (do contrato ou do estilo da fusão) passou do que a
-- próxima forma pede. kind = "Mastery" (contrato) ou "StyleMastery" (estilo)
local function formHint(player, kind, id, oldLevel, newLevel)
	local path, contracts = PathData.FromPlayer(player)
	local contractId = contracts[1]
	local entry = path == "Hunter" and ContractData.Get(contractId)
	if not entry or not entry.Forms then return nil end
	if kind == "Mastery" and id ~= contractId then return nil end
	if kind == "StyleMastery" and entry.FusionStyle ~= id then return nil end
	for _, form in ContractData.FormOrder do
		local requires = entry.Forms[form] and entry.Forms[form].Requires
		local need = requires and requires[kind]
		if need and oldLevel < need and newLevel >= need then
			local npc = QuestData.NPCs[ContractData.EvolutionNPC] or "the Pact Master"
			return ` {ContractData.FormNames[form]} form requirement met: talk to {npc}.`
		end
	end
	return nil
end

-- XP de maestria num estilo (o CombatService chama a cada golpe que acerta). Avisa quando sobe de nível e quais
-- técnicas ficaram ao alcance.
function PlayerData.AddMastery(player, style, amount)
	local profile = profiles[player]
	if not profile or type(style) ~= "string" or type(amount) ~= "number" or amount <= 0 then return end
	local before = profile.Mastery[style] or 0
	local after = math.min(SkillTreeData.MasteryCap(), before + amount)
	if after == before then return end
	profile.Mastery[style] = after

	local folder = player:FindFirstChild("Mastery")
	if folder then
		local value = folder:FindFirstChild(style) or newInt(style, 0, folder)
		value.Value = after
	end

	local oldLevel = SkillTreeData.MasteryLevel(before)
	local newLevel = SkillTreeData.MasteryLevel(after)
	if newLevel <= oldLevel then return end
	local ready = {}
	for _, entry in SkillTreeData.Nodes do
		local need = entry.Mastery
		if need and need.Style == style and need.Level > oldLevel and need.Level <= newLevel then
			table.insert(ready, entry.Name)
		end
	end
	local text = `{SkillTreeData.StyleName(style)}: mastery {newLevel}.`
	if #ready > 0 then
		text ..= ` You can now unlock in the tree (M): {table.concat(ready, ", ")}.`
	end
	text ..= formHint(player, "StyleMastery", style, oldLevel, newLevel) or ""
	PlayerData.Notify(player, "Mastery!", text, 5)
end

function PlayerData.GetContractMasteryLevel(player, contractId)
	local profile = profiles[player]
	return if profile then (SkillTreeData.MasteryLevel(profile.ContractMastery[contractId] or 0)) else 0
end

-- XP de maestria no contrato (PathSkills: acertos e abates dos poderes; CombatService: golpes do estilo fundido).
-- Mesma curva da maestria dos estilos; avisa quando sobe de nível e quando uma forma fica ao alcance.
function PlayerData.AddContractMastery(player, contractId, amount)
	local profile = profiles[player]
	if not profile or not ContractData.HasForms(contractId) or type(amount) ~= "number" or amount <= 0 then return end
	local before = profile.ContractMastery[contractId] or 0
	local after = math.min(SkillTreeData.MasteryCap(), before + math.floor(amount))
	if after == before then return end
	profile.ContractMastery[contractId] = after

	local folder = player:FindFirstChild("ContractMastery")
	if folder then
		local value = folder:FindFirstChild(contractId) or newInt(contractId, 0, folder)
		value.Value = after
	end

	local oldLevel = SkillTreeData.MasteryLevel(before)
	local newLevel = SkillTreeData.MasteryLevel(after)
	if newLevel <= oldLevel then return end
	local contract = PathData.Contracts[contractId]
	local name = if contract then contract.DisplayName else contractId
	local text = `{name}: maestria do contrato {newLevel}.` .. (formHint(player, "Mastery", contractId, oldLevel, newLevel) or "")
	PlayerData.Notify(player, "Contract mastery!", text, 5)
end

-- Desbloqueia um nó. Devolve (true) ou (false, motivo).
function PlayerData.UnlockNode(player, nodeId)
	local profile = profiles[player]
	local entry = type(nodeId) == "string" and SkillTreeData.Get(nodeId)
	if not profile or not entry or entry.Default then
		return false, "That node does not exist."
	end
	local blocker = SkillTreeData.Blocker(entry, SkillTreeData.UnlockedSet(profile.Tree), masteryLevels(profile),
		availablePoints(player, profile))
	if blocker then
		return false, blocker
	end
	table.insert(profile.Tree, nodeId)
	refreshPoints(player)
	applyTree(player, profile)
	return true
end

-- Pontos de missão e de chefe (somam nos pontos da árvore)
function PlayerData.AddStatusPoints(player, amount)
	local profile = profiles[player]
	if not profile or type(amount) ~= "number" or amount <= 0 then return end
	profile.BonusPoints += math.floor(amount)
	refreshPoints(player)
end

local function levelUpEffect(player)
	local character = player.Character
	if not character then return end

	local highlight = Instance.new("Highlight")
	highlight.FillColor = Color3.fromRGB(255, 200, 0)
	highlight.OutlineColor = Color3.fromRGB(255, 255, 255)
	highlight.FillTransparency = 0.4
	highlight.Parent = character
	TweenService:Create(highlight, TweenInfo.new(1.2), { FillTransparency = 1, OutlineTransparency = 1 }):Play()
	Debris:AddItem(highlight, 1.3)
end

-- Dá um item (ItemData) ao jogador: salva no perfil e atualiza a pasta Inventory. Devolve true se deu.
function PlayerData.AddItem(player, itemId, amount)
	local profile = profiles[player]
	if not profile or not ItemData.Get(itemId) then return false end
	amount = math.max(1, math.floor(amount or 1))
	profile.Items[itemId] = (profile.Items[itemId] or 0) + amount
	local inventory = player:FindFirstChild("Inventory")
	if inventory then
		local value = inventory:FindFirstChild(itemId) or newInt(itemId, 0, inventory)
		value.Value = profile.Items[itemId]
	end
	return true
end

-- ================= Itens equipados =================

local warnedModels = {}
local lastEquip = setmetatable({}, { __mode = "k" })

-- Veste no personagem os itens equipados (cópia do Accessory de ReplicatedStorage.VFX.Items) e tira os que saíram
local function dressCharacter(player, profile)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then return end
	local wanted = {}
	for _, id in profile.Equipped do
		wanted[id] = "missing"
	end
	for _, child in character:GetChildren() do
		local id = child:IsA("Accessory") and child:GetAttribute(EQUIPPED_ATTRIBUTE)
		if id then
			if wanted[id] == "missing" then
				wanted[id] = "worn"
			else
				child:Destroy()
			end
		end
	end
	for id, state in wanted do
		if state ~= "missing" then continue end
		local model = ItemData.FindModel(id)
		if model and model:IsA("Accessory") then
			local copy = model:Clone()
			copy:SetAttribute(EQUIPPED_ATTRIBUTE, id)
			humanoid:AddAccessory(copy)
		elseif not warnedModels[id] then
			warnedModels[id] = true
			warn(`[PlayerData] O item {id} não tem modelo em ReplicatedStorage.VFX.Items ({ItemData.ModelName(id)}): equipa sem aparecer`)
		end
	end
end

-- Veste (equip = true) ou tira um item. Devolve (true) ou (false, motivo).
function PlayerData.EquipItem(player, itemId, equip)
	local profile = profiles[player]
	local item = type(itemId) == "string" and ItemData.Get(itemId)
	if not profile or not item or not ItemData.GetSlot(item.Slot) then
		return false, "That item does not exist."
	end
	if equip then
		if (profile.Items[itemId] or 0) < 1 then
			return false, "You do not have that item."
		end
		if profile.Equipped[item.Slot] == itemId then return true end
		profile.Equipped[item.Slot] = itemId
	else
		if profile.Equipped[item.Slot] ~= itemId then return true end
		profile.Equipped[item.Slot] = nil
	end
	applyTree(player, profile)
	dressCharacter(player, profile)
	return true
end

-- Dá XP (sobe de level quando enche). Ganhos somam o bônus de XP do clã, a não ser com noBonus.
function PlayerData.AddXP(player, amount, noBonus)
	local leaderstats = player:FindFirstChild("leaderstats")
	local progress = player:FindFirstChild("Progress")
	if not leaderstats or not progress then return end
	if amount > 0 and not noBonus then
		amount = math.floor(amount * (1 + PlayerData.GetTreeEffect(player, "XPBonus")) * Passes.Multiplier(player, "DoubleXP") + 0.5)
	end

	local level = leaderstats.Level
	local xp = progress.XP
	local xpNeeded = progress.XPNeeded

	-- No level máximo o XP não conta mais
	if level.Value >= StatConfig.MaxLevel then
		xp.Value = 0
		return 0
	end
	xp.Value += amount

	local levelsGained = 0
	while xp.Value >= xpNeeded.Value and level.Value < StatConfig.MaxLevel do
		xp.Value -= xpNeeded.Value
		level.Value += 1
		xpNeeded.Value = StatConfig.XPNeeded(level.Value)
		levelsGained += 1
	end
	if level.Value >= StatConfig.MaxLevel then
		xp.Value = 0
	end

	if levelsGained > 0 then
		refreshPoints(player)
		applyHealth(player, true)
		levelUpEffect(player)
		PlayerData.Notify(player, "Level up!", "You reached level " .. level.Value .. ". Press M to open the skill tree.", 4)
	end
	return amount
end

local function setupPlayer(player, slot)
	if profiles[player] or loading[player] then return end
	loading[player] = true

	local data, canSave = loadData(player, slot)
	loading[player] = nil
	if not player.Parent then return end

	-- Monta cada pasta completa antes de colocar no player
	local leaderstats = Instance.new("Folder")
	leaderstats.Name = "leaderstats"
	newInt("Level", data.Level, leaderstats)
	newInt("Gold", data.Gold, leaderstats)

	local stats = Instance.new("Folder")
	stats.Name = "Stats"
	for name, value in StatConfig.BaseStats do
		newInt(name, value, stats)
	end

	local progress = Instance.new("Folder")
	progress.Name = "Progress"
	newInt("XP", data.XP, progress)
	newInt("XPNeeded", StatConfig.XPNeeded(data.Level), progress)
	newInt("StatusPoints", 0, progress)

	local inventory = Instance.new("Folder")
	inventory.Name = "Inventory"
	for id, count in data.Items do
		newInt(id, count, inventory)
	end

	local mastery = Instance.new("Folder")
	mastery.Name = "Mastery"
	for style, xp in data.Mastery do
		newInt(style, xp, mastery)
	end

	-- Maestria dos contratos (ContractData): uma IntValue com o XP total por contrato
	local contractMastery = Instance.new("Folder")
	contractMastery.Name = "ContractMastery"
	for contractId, xp in data.ContractMastery do
		newInt(contractId, xp, contractMastery)
	end

	local profile = {
		Quests = data.Quests,
		Fishing = data.Fishing,
		WorldActivities = data.WorldActivities,
		VIPRewards = data.VIPRewards,
		Path = data.Path,
		Settings = data.Settings,
		Items = data.Items,
		Equipped = data.Equipped,
		Tree = data.Tree,
		Mastery = data.Mastery,
		BonusPoints = data.BonusPoints,
		Appearance = data.Appearance,
		Created = data.Created,
		Clan = data.Clan,
		Spins = data.Spins,
		Codes = data.Codes,
		Styles = data.Styles,
		HiddenStyles = data.HiddenStyles,
		Tutorial = data.Tutorial,
		Daily = data.Daily,
		Milestones = data.Milestones,
		ContractMastery = data.ContractMastery,
		DodgeLevel = data.DodgeLevel,
		DodgeForced = data.DodgeForced,
		CanSave = canSave,
		Slot = slot,
	}
	profiles[player] = profile
	player:SetAttribute("SaveSlot", slot)
	publishStyles(player, profile)
	-- Fusão do contrato (atributos que o PathModule escreve): trava ou solta os estilos
	for _, attribute in { "Path", "Contracts", "ContractForm" } do
		player:GetAttributeChangedSignal(attribute):Connect(function()
			if profiles[player] == profile then
				publishStyles(player, profile)
			end
		end)
	end

	-- Configurações chegam antes do leaderstats: a tela de carregamento espera o leaderstats
	for key, value in data.Settings do
		player:SetAttribute("Setting" .. key, value)
	end

	inventory.Parent = player
	mastery.Parent = player
	contractMastery.Parent = player
	stats.Parent = player
	progress.Parent = player
	leaderstats.Parent = player
	refreshPoints(player)
	applyTree(player, profile)

	player.CharacterAdded:Connect(function(character)
		character:WaitForChild("Humanoid")
		applyHealth(player, true)
		dressCharacter(player, profile)
	end)
	if player.Character then
		applyHealth(player, true)
		dressCharacter(player, profile)
	end

	loadedEvent:Fire(player)

	if not canSave then
		if RunService:IsStudio() then
			warn("[PlayerData] Dados não carregados no Studio (ative Game Settings > Security > Enable Studio Access to API Services para testar o salvamento)")
		else
			task.delay(5, function()
				PlayerData.Notify(player, "Warning", "Could not load your data. Progress in this session will not be saved.", 8)
			end)
		end
	end
end

local function onSkillTreeUnlock(player, nodeId)
	local ok, reason = PlayerData.UnlockNode(player, nodeId)
	if not ok then
		PlayerData.Notify(player, "Skill tree", reason or "Could not unlock.")
	end
end

-- Reseta a árvore: devolve todos os pontos gastos em troca de Gold (a maestria continua)
local function onStatusReset(player)
	local profile = profiles[player]
	local leaderstats = player:FindFirstChild("leaderstats")
	if not profile or not leaderstats then return end

	local refund = SkillTreeData.Spent(profile.Tree)
	if refund == 0 then
		PlayerData.Notify(player, "Skill tree", "You have nothing unlocked to reset.")
		return
	end

	local cost = StatConfig.ResetCost(leaderstats.Level.Value)
	if not PlayerData.SpendGold(player, cost) then
		PlayerData.Notify(player, "Skill tree", `Resetting costs {cost} Gold. You have {leaderstats.Gold.Value}.`)
		return
	end

	table.clear(profile.Tree)
	refreshPoints(player)
	applyTree(player, profile)
	PlayerData.Notify(player, "Skill tree", `Tree reset: {refund} points refunded for {cost} Gold.`)
end

-- Cliente pedindo para vestir/tirar um item (o inventário se atualiza pelo atributo Equipped)
-- Cliente guardando/equipando um estilo de combate no inventário
local lastStyleToggle = {}
local function onEquipStyle(player, name, equip)
	if type(name) ~= "string" or #name > 40 or type(equip) ~= "boolean" then return end
	local clock = os.clock()
	if clock - (lastStyleToggle[player] or 0) < 0.4 then return end
	lastStyleToggle[player] = clock
	local ok, reason = PlayerData.SetStyleEquipped(player, name, equip)
	if not ok and reason then
		PlayerData.Notify(player, "Styles", reason, 5)
	end
end

local function onEquipItem(player, itemId, equip)
	local clock = os.clock()
	if clock - (lastEquip[player] or 0) < EQUIP_GAP then return end
	lastEquip[player] = clock
	local ok, reason = PlayerData.EquipItem(player, itemId, equip == true)
	if not ok and reason then
		PlayerData.Notify(player, "Inventory", reason)
	end
end

-- Cliente salvando uma configuração: só chaves conhecidas, com o mesmo tipo do padrão. Só muda a tabela do
-- perfil (vai para o DataStore no próximo salvamento); o atributo Setting<Nome> serve só para a entrada no jogo.
local function onSaveSetting(player, key, value)
	if type(key) ~= "string" or DEFAULT_SETTINGS[key] == nil or type(value) ~= type(DEFAULT_SETTINGS[key]) then return end
	local profile = profiles[player]
	if profile then
		profile.Settings[key] = value
	end
end

-- ================= Saves =================

local slotCache = {} -- [player] = { [slot] = resumo | false } lido na entrada (só enquanto escolhe)
local slotBusy = {}
local lastSlotAction = {}

local function slotUnlocked(player, slot)
	return slot <= FREE_SLOTS or Passes.Owns(player, "ExtraSlots")
end

-- Resumo para o cartão do save (só o que a tela mostra; o perfil inteiro continua no servidor)
local function slotSummary(raw)
	if type(raw) ~= "table" then return false end
	local path = if type(raw.Path) == "table" then raw.Path else {}
	local contract = nil
	if type(path.Contracts) == "table" then
		for _, id in path.Contracts do
			if type(id) == "string" then
				contract = id
				break
			end
		end
	end
	return {
		Level = if type(raw.Level) == "number" then math.floor(raw.Level) else 1,
		Gold = if type(raw.Gold) == "number" then math.floor(raw.Gold) else 0,
		Path = if type(path.Path) == "string" then path.Path else "None",
		Contract = contract,
		FiendType = if type(path.FiendType) == "string" and path.FiendType ~= "" then path.FiendType else nil,
		Clan = if type(raw.Clan) == "string" and raw.Clan ~= "" then raw.Clan else nil,
		Created = raw.Created == true,
		Appearance = AppearanceData.Sanitize(raw.Appearance),
	}
end

-- Lê os saves da conta (uma chave por save). Sem DataStore (Studio sem acesso): todos vazios, sem salvar.
local function readSlots(player)
	local list = {}
	local offline = store == nil
	for slot = 1, SLOT_COUNT do
		list[slot] = false
		if store then
			for attempt = 1, MAX_RETRIES do
				local ok, result = pcall(function()
					return store:GetAsync(dataKey(player, slot))
				end)
				if ok then
					list[slot] = slotSummary(result)
					break
				end
				if isAccessDenied(result) or attempt == MAX_RETRIES then
					offline = true
					break
				end
				task.wait(attempt)
			end
			if offline then break end
		end
		if not player.Parent then return nil, offline end
	end
	return list, offline
end

local function sendSlots(player)
	if not player.Parent or profiles[player] then return end
	local cache = slotCache[player]
	if not cache then return end
	local unlocked = {}
	for slot = 1, SLOT_COUNT do
		unlocked[slot] = slotUnlocked(player, slot)
	end
	Remotes.SaveSlots:FireClient(player, {
		Slots = cache.List,
		Unlocked = unlocked,
		Offline = cache.Offline,
		PassesReady = Passes.Ready(player),
		Count = SLOT_COUNT,
	})
end

local function refreshSlots(player)
	if slotBusy[player] then return end
	slotBusy[player] = true
	local list, offline = readSlots(player)
	slotBusy[player] = nil
	if not list or not player.Parent then return end
	slotCache[player] = { List = list, Offline = offline }
	sendSlots(player)
end

local function onSlotAction(player, action, slot)
	if type(action) ~= "string" then return end
	local clock = os.clock()
	if clock < (lastSlotAction[player] or 0) then return end
	lastSlotAction[player] = clock + 0.5

	if action == "List" then
		if slotCache[player] then sendSlots(player) else task.spawn(refreshSlots, player) end
		return
	elseif action == "Switch" then
		-- Trocar de save no meio do jogo: salva e volta para um servidor novo (a tela de saves abre de novo)
		if not profiles[player] then return end
		if RunService:IsStudio() then
			PlayerData.Notify(player, "Saves", "Changing saves only works in the published game. Stop and press Play again.", 5)
			return
		end
		savePlayer(player)
		local ok, err = pcall(function()
			TeleportService:TeleportAsync(game.PlaceId, { player })
		end)
		if not ok then
			warn("[PlayerData] Falha ao trocar de save: " .. tostring(err))
			PlayerData.Notify(player, "Saves", "Could not change saves right now. Try again in a moment.", 5)
		end
		return
	end

	if type(slot) ~= "number" or slot ~= math.floor(slot) or slot < 1 or slot > SLOT_COUNT then return end
	if profiles[player] or loading[player] or slotBusy[player] then return end
	local cache = slotCache[player]
	if not cache then return end

	if action == "Select" then
		-- O passe pode ainda estar sendo conferido logo na entrada
		local deadline = os.clock() + 6
		while not Passes.Ready(player) and not slotUnlocked(player, slot) and os.clock() < deadline and player.Parent do
			task.wait(0.2)
		end
		if not slotUnlocked(player, slot) then
			sendSlots(player)
			return
		end
		slotCache[player] = nil
		setupPlayer(player, slot)
	elseif action == "Delete" then
		if not store or cache.Offline or not cache.List[slot] then return end
		slotBusy[player] = true
		local ok, err = pcall(function()
			store:RemoveAsync(dataKey(player, slot))
		end)
		slotBusy[player] = nil
		if not ok then
			warn("[PlayerData] Falha ao apagar save: " .. tostring(err))
			PlayerData.Notify(player, "Saves", "Could not delete this save. Try again.", 4)
			return
		end
		cache.List[slot] = false
		sendSlots(player)
	end
end

function PlayerData.Init()
	-- O perfil só carrega quando o jogador escolhe o save (Remotes.SaveSlotAction "Select")
	Players.PlayerAdded:Connect(function(player)
		refreshSlots(player)
	end)
	for _, player in Players:GetPlayers() do
		task.spawn(refreshSlots, player)
	end
	Passes.Changed:Connect(sendSlots)
	Remotes.SaveSlotAction.OnServerEvent:Connect(onSlotAction)

	Players.PlayerRemoving:Connect(function(player)
		slotCache[player] = nil
		slotBusy[player] = nil
		lastSlotAction[player] = nil
		savePlayer(player)
		profiles[player] = nil
	end)

	Remotes.SkillTreeUnlock.OnServerEvent:Connect(onSkillTreeUnlock)
	Remotes.StatusReset.OnServerEvent:Connect(onStatusReset)
	Remotes.SaveSetting.OnServerEvent:Connect(onSaveSetting)
	Remotes.EquipItem.OnServerEvent:Connect(onEquipItem)
	Remotes.EquipStyle.OnServerEvent:Connect(onEquipStyle)

	task.spawn(function()
		while true do
			task.wait(AUTOSAVE_INTERVAL)
			for player in profiles do
				task.spawn(savePlayer, player)
			end
		end
	end)

	game:BindToClose(function()
		for _, player in Players:GetPlayers() do
			task.spawn(savePlayer, player)
		end
		local deadline = os.clock() + 25
		repeat
			task.wait(0.2)
		until activeSaves == 0 or os.clock() > deadline
	end)
end

return PlayerData
