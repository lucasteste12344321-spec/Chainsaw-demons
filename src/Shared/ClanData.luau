
local ClanData = {}

ClanData.SpinGoldCost = 1000 -- Gold por giro comprado
ClanData.StartingSpins = 3 -- giros de quem começa agora (além do sorteio grátis do primeiro acesso)

-- Contas em que o Roblox restringe item aleatório pago (PolicyService ArePaidRandomItemsRestricted: menores no Brasil, por
-- causa da lei das caixas de recompensa, e outros países): sem roleta. Elas escolhem o clã direto pagando Gold pela
-- raridade; cada giro guardado (código, tutorial) vira um crédito que vale SpinGoldCost de desconto. O clã do primeiro
-- acesso continua sorteado de graça. Atributo RandomItemsRestricted no player (CharacterService).
ClanData.ChooseGoldCost = {
	Common = 2000,
	Uncommon = 5000,
	Rare = 12000,
	Epic = 35000,
	Legendary = 250000,
}

-- Chance de cada raridade (somam 1). A chance da raridade é dividida igualmente entre os clãs dela.
ClanData.Rarities = {
	{ Id = "Common", Chance = 0.55, Color = Color3.fromRGB(200, 200, 200) },
	{ Id = "Uncommon", Chance = 0.27, Color = Color3.fromRGB(110, 220, 110) },
	{ Id = "Rare", Chance = 0.13, Color = Color3.fromRGB(80, 160, 255) },
	{ Id = "Epic", Chance = 0.045, Color = Color3.fromRGB(190, 100, 255) },
	{ Id = "Legendary", Chance = 0.005, Color = Color3.fromRGB(255, 190, 40) },
}

ClanData.Clans = {
	-- Comum
	{ Id = "Arai", Name = "Arai", Kanji = "荒井", Rarity = "Common", Effects = { HP = 40 },
		Description = "Stubborn rookies who never back down, even when scared." },
	{ Id = "Ando", Name = "Ando", Kanji = "安藤", Rarity = "Common", Effects = { Defesa = 2 },
		Description = "A family of Public Safety guards: they hold the line." },
	{ Id = "Akoku", Name = "Akoku", Kanji = "亜国", Rarity = "Common", Effects = { Energia = 20 },
		Description = "Street runners, used to fleeing from devils." },
	{ Id = "Kusakabe", Name = "Kusakabe", Kanji = "日下部", Rarity = "Common", Effects = { GoldBonus = 0.08 },
		Description = "Private hunters who charge a lot for every job." },
	{ Id = "Tamaoki", Name = "Tamaoki", Kanji = "玉置", Rarity = "Common", Effects = { XPBonus = 0.06 },
		Description = "Devil scholars: they learn fast from every fight." },
	{ Id = "Aldo", Name = "Aldo", Kanji = "アルド", Rarity = "Common", Effects = { Forca = 4 },
		Description = "Heavy-handed foreign assassins." },
	{ Id = "Joey", Name = "Joey", Kanji = "ジョーイ", Rarity = "Common", Effects = { StaminaRegen = 0.1 },
		Description = "Tireless foreigners: their stamina comes back fast." },
	-- Incomum
	{ Id = "Kurose", Name = "Kurose", Kanji = "黒瀬", Rarity = "Uncommon", Effects = { Forca = 5, Defesa = 1 },
		Description = "Kyoto hunters, trained for the front line." },
	{ Id = "Tendo", Name = "Tendo", Kanji = "天童", Rarity = "Uncommon", Effects = { GuardMax = 0.1, Defesa = 2 },
		Description = "The Kurose's partners: cold and hard to take down." },
	{ Id = "Mifune", Name = "Mifune", Kanji = "三船", Rarity = "Uncommon", Effects = { XPBonus = 0.1 },
		Description = "Agents who survive everything and always come back stronger." },
	{ Id = "Iseumi", Name = "Iseumi", Kanji = "伊勢海", Rarity = "Uncommon", Effects = { Damage_Punhos = 0.05 },
		Description = "The hunter club that swears it is the real Chainsaw Man." },
	{ Id = "Sugo", Name = "Sugo", Kanji = "須郷", Rarity = "Uncommon", Effects = { GoldBonus = 0.12 },
		Description = "A wealthy family that funds the devil hunt." },
	-- Raro
	{ Id = "Higashiyama", Name = "Higashiyama", Kanji = "東山", Rarity = "Rare", Effects = { DodgeChance = 0.05, Velocidade = 1 },
		Description = "Cowards with absurd reflexes: they dodge almost anything." },
	{ Id = "Sawatari", Name = "Sawatari", Kanji = "沢渡", Rarity = "Rare", Effects = { Damage_Punhos = 0.08, Knockback = 0.1 },
		Description = "Snake contractors, cruel and precise." },
	{ Id = "Nomo", Name = "Nomo", Kanji = "野茂", Rarity = "Rare", Effects = { HP = 100, Regen = 0.004 },
		Description = "Bodies that are hard to kill and heal on their own." },
	{ Id = "Yoshida", Name = "Yoshida", Kanji = "吉田", Rarity = "Rare", Effects = { Velocidade = 1, DashCost = 0.15, ParryWindow = 0.03 },
		Description = "Octopus contractors: fast and always one step ahead." },
	-- Épico
	{ Id = "Hayakawa", Name = "Hayakawa", Kanji = "早川", Rarity = "Epic", Effects = { Forca = 8, ParryWindow = 0.05, GuardRegen = 0.15 },
		Description = "Disciplined Public Safety swordsmen, scarred by their contracts." },
	{ Id = "Bridge", Name = "Bridge", Kanji = "ブリッジ", Rarity = "Epic", Effects = { HP = 120, Defesa = 5, BlockTaken = 0.1 },
		Description = "Foreign bodyguards: a wall in front of whoever they protect." },
	-- Lendário
	{ Id = "Mitaka", Name = "Mitaka", Kanji = "三鷹", Rarity = "Legendary", Effects = { Forca = 15, Damage_Punhos = 0.1, HP = 100 },
		Description = "They carry the War Devil. Anything becomes a weapon in their hands." },
}

local rarityById = {}
for index, rarity in ClanData.Rarities do
	rarity.Order = index
	rarityById[rarity.Id] = rarity
end

local clanById = {}
local countByRarity = {}
for index, clan in ClanData.Clans do
	clan.Order = index
	clanById[clan.Id] = clan
	countByRarity[clan.Rarity] = (countByRarity[clan.Rarity] or 0) + 1
end

function ClanData.Get(id)
	return type(id) == "string" and clanById[id] or nil
end

function ClanData.GetRarity(rarityId)
	return rarityById[rarityId]
end

-- Cor da raridade do clã (cinza se não achar)
function ClanData.Color(id)
	local clan = ClanData.Get(id)
	local rarity = clan and rarityById[clan.Rarity]
	return if rarity then rarity.Color else Color3.fromRGB(200, 200, 200)
end

-- Chance de sair esse clã num giro (0 a 1)
function ClanData.Chance(id)
	local clan = ClanData.Get(id)
	local rarity = clan and rarityById[clan.Rarity]
	if not rarity then return 0 end
	return rarity.Chance / countByRarity[clan.Rarity]
end

-- Sorteia um clã (Id) respeitando as chances
function ClanData.Roll(rng)
	rng = rng or Random.new()
	local roll = rng:NextNumber()
	local total = 0
	for _, clan in ClanData.Clans do
		total += ClanData.Chance(clan.Id)
		if roll < total then
			return clan.Id
		end
	end
	return ClanData.Clans[1].Id -- arredondamento
end

-- Efeitos do clã (cópia, para somar com a árvore e os itens)
function ClanData.Compute(id)
	local clan = ClanData.Get(id)
	return if clan then table.clone(clan.Effects) else {}
end

-- Clãs do mais raro para o mais comum (lista da tela)
function ClanData.Sorted()
	local list = table.clone(ClanData.Clans)
	table.sort(list, function(a, b)
		local ra, rb = rarityById[a.Rarity].Order, rarityById[b.Rarity].Order
		if ra ~= rb then return ra > rb end
		return a.Order < b.Order
	end)
	return list
end

-- Preço de escolher o clã direto (contas sem sorteio pago): devolve (créditos usados, Gold a pagar, preço cheio).
-- Os créditos (giros guardados) pagam SpinGoldCost cada, sem passar do preço.
function ClanData.ChooseCost(id, credits)
	local clan = ClanData.Get(id)
	local price = clan and ClanData.ChooseGoldCost[clan.Rarity]
	if not price then return 0, 0, 0 end
	local used = math.clamp(math.floor(price / ClanData.SpinGoldCost), 0, math.max(0, math.floor(credits or 0)))
	return used, price - used * ClanData.SpinGoldCost, price
end

-- Clã "bom" o bastante para pedir confirmação antes de girar e perder ele
function ClanData.IsPrecious(id)
	local clan = ClanData.Get(id)
	local rarity = clan and rarityById[clan.Rarity]
	return rarity ~= nil and rarity.Order >= rarityById["Epic"].Order
end

return ClanData
