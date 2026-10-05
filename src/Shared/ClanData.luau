
local ClanData = {}

ClanData.SpinGoldCost = 1000 -- Gold por giro comprado
ClanData.StartingSpins = 3 -- giros de quem começa agora (além do sorteio grátis do primeiro acesso)

-- Contas em que o Roblox restringe item aleatório pago (PolicyService ArePaidRandomItemsRestricted: menores no Brasil, por
-- causa da lei das caixas de recompensa, e outros países): sem roleta. Elas escolhem o clã direto pagando Gold pela
-- raridade; cada giro guardado (código, tutorial) vira um crédito que vale SpinGoldCost de desconto. O clã do primeiro
-- acesso continua sorteado de graça. Atributo RandomItemsRestricted no player (CharacterService).
ClanData.ChooseGoldCost = {
	Comum = 2000,
	Incomum = 5000,
	Raro = 12000,
	["Épico"] = 35000,
	["Lendário"] = 250000,
}

-- Chance de cada raridade (somam 1). A chance da raridade é dividida igualmente entre os clãs dela.
ClanData.Rarities = {
	{ Id = "Comum", Chance = 0.55, Color = Color3.fromRGB(200, 200, 200) },
	{ Id = "Incomum", Chance = 0.27, Color = Color3.fromRGB(110, 220, 110) },
	{ Id = "Raro", Chance = 0.13, Color = Color3.fromRGB(80, 160, 255) },
	{ Id = "Épico", Chance = 0.045, Color = Color3.fromRGB(190, 100, 255) },
	{ Id = "Lendário", Chance = 0.005, Color = Color3.fromRGB(255, 190, 40) },
}

ClanData.Clans = {
	-- Comum
	{ Id = "Arai", Name = "Arai", Kanji = "荒井", Rarity = "Comum", Effects = { HP = 40 },
		Description = "Novatos teimosos que não recuam, mesmo com medo." },
	{ Id = "Ando", Name = "Ando", Kanji = "安藤", Rarity = "Comum", Effects = { Defesa = 2 },
		Description = "Família de guardas da Segurança Pública: aguentam firme." },
	{ Id = "Akoku", Name = "Akoku", Kanji = "亜国", Rarity = "Comum", Effects = { Energia = 20 },
		Description = "Corredores de rua, acostumados a fugir de demônio." },
	{ Id = "Kusakabe", Name = "Kusakabe", Kanji = "日下部", Rarity = "Comum", Effects = { GoldBonus = 0.08 },
		Description = "Caçadores particulares que cobram caro por cada serviço." },
	{ Id = "Tamaoki", Name = "Tamaoki", Kanji = "玉置", Rarity = "Comum", Effects = { XPBonus = 0.06 },
		Description = "Estudiosos dos demônios: aprendem rápido com cada luta." },
	{ Id = "Aldo", Name = "Aldo", Kanji = "アルド", Rarity = "Comum", Effects = { Forca = 4 },
		Description = "Assassinos estrangeiros de mão pesada." },
	{ Id = "Joey", Name = "Joey", Kanji = "ジョーイ", Rarity = "Comum", Effects = { StaminaRegen = 0.1 },
		Description = "Estrangeiros incansáveis: o fôlego volta rápido." },
	-- Incomum
	{ Id = "Kurose", Name = "Kurose", Kanji = "黒瀬", Rarity = "Incomum", Effects = { Forca = 5, Defesa = 1 },
		Description = "Caçadores de Kyoto, treinados para a linha de frente." },
	{ Id = "Tendo", Name = "Tendo", Kanji = "天童", Rarity = "Incomum", Effects = { GuardMax = 0.1, Defesa = 2 },
		Description = "Parceiros dos Kurose: frios e difíceis de derrubar." },
	{ Id = "Mifune", Name = "Mifune", Kanji = "三船", Rarity = "Incomum", Effects = { XPBonus = 0.1 },
		Description = "Agentes que sobrevivem a tudo e sempre voltam mais fortes." },
	{ Id = "Iseumi", Name = "Iseumi", Kanji = "伊勢海", Rarity = "Incomum", Effects = { Damage_Punhos = 0.05 },
		Description = "O clube de caçadores que jura ser o próprio Homem-Motosserra." },
	{ Id = "Sugo", Name = "Sugo", Kanji = "須郷", Rarity = "Incomum", Effects = { GoldBonus = 0.12 },
		Description = "Família rica que financia a caça aos demônios." },
	-- Raro
	{ Id = "Higashiyama", Name = "Higashiyama", Kanji = "東山", Rarity = "Raro", Effects = { DodgeChance = 0.05, Velocidade = 1 },
		Description = "Medrosos com reflexos absurdos: desviam de quase tudo." },
	{ Id = "Sawatari", Name = "Sawatari", Kanji = "沢渡", Rarity = "Raro", Effects = { Damage_Punhos = 0.08, Knockback = 0.1 },
		Description = "Contratantes da Serpente, cruéis e precisos." },
	{ Id = "Nomo", Name = "Nomo", Kanji = "野茂", Rarity = "Raro", Effects = { HP = 100, Regen = 0.004 },
		Description = "Corpos duros de matar, que se recuperam sozinhos." },
	{ Id = "Yoshida", Name = "Yoshida", Kanji = "吉田", Rarity = "Raro", Effects = { Velocidade = 1, DashCost = 0.15, ParryWindow = 0.03 },
		Description = "Contratantes do Polvo: rápidos e sempre um passo à frente." },
	-- Épico
	{ Id = "Hayakawa", Name = "Hayakawa", Kanji = "早川", Rarity = "Épico", Effects = { Forca = 8, ParryWindow = 0.05, GuardRegen = 0.15 },
		Description = "Espadachins disciplinados da Segurança Pública, marcados pelos contratos." },
	{ Id = "Bridge", Name = "Bridge", Kanji = "ブリッジ", Rarity = "Épico", Effects = { HP = 120, Defesa = 5, BlockTaken = 0.1 },
		Description = "Guarda-costas estrangeiros: uma parede na frente do protegido." },
	-- Lendário
	{ Id = "Mitaka", Name = "Mitaka", Kanji = "三鷹", Rarity = "Lendário", Effects = { Forca = 15, Damage_Punhos = 0.1, HP = 100 },
		Description = "Carregam o Demônio da Guerra. Tudo vira arma nas mãos deles." },
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
	return rarity ~= nil and rarity.Order >= rarityById["Épico"].Order
end

return ClanData
