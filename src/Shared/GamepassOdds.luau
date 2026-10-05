local RS = game:GetService("ReplicatedStorage")
local Config = require(RS.GamepassConfig)
local Bosses = require(RS.BossData)
local Items = require(RS.ItemData)
local Clans = require(RS.ClanData)
local Styles = require(RS.CombatStyles)
local Odds = {}
-- Largest remainder: the displayed outcomes sum to 100.0000%, including no item.
local function percentages(rows)
	local used = 0; local order = {}
	for i, row in rows do
		local exact = row.Chance * 1000000
		row.Units = math.floor(exact); used += row.Units
		table.insert(order, {Index = i, Fraction = exact - row.Units})
	end
	table.sort(order, function(a,b) if a.Fraction == b.Fraction then return a.Index < b.Index end; return a.Fraction > b.Fraction end)
	for i = 1, 1000000 - used do rows[order[(i-1) % #order + 1].Index].Units += 1 end
	return rows
end
function Odds.BossOutcomes(drops, vip, restricted)
	local rows = {{Names = {}, Chance = 1}}
	for _, drop in drops do
		local chance = Config.DropChance(drop.Chance, vip, restricted)
		local nextRows = {}
		for _, row in rows do
			table.insert(nextRows, {Names = table.clone(row.Names), Chance = row.Chance * (1 - chance)})
			local names = table.clone(row.Names); table.insert(names, drop.Item)
			table.insert(nextRows, {Names = names, Chance = row.Chance * chance})
		end
		rows = nextRows
	end
	return percentages(rows)
end
function Odds.Text(restricted, owned)
	local lines = {
		"PASSES PERMANENTES · compra única",
		"2× XP e 2× Gold são separados do VIP. Os bônus multiplicam o ganho de jogo após bônus de clã. Códigos, reembolsos e comandos de admin não são multiplicados.",
		"VIP: 5 giros ao entrar ou resgatar a cada dia. Renova à meia-noite de Brasília; dias sem jogar não acumulam. Se a reserva de 9.999 giros estiver cheia, use giros antes de resgatar.",
		"Servidor VIP: um servidor reservado pessoal, com acesso pelo botão da loja. Não é uma assinatura de servidor privado nativo do Roblox.",
		if restricted then "SUA CONTA: o bônus de sorte não se aplica; os 5 giros viram créditos para a escolha garantida de clã, como no menu de clãs." else "VIP dobra a chance de cada item de chefe (máximo 100%). Não duplica a quantidade nem altera a raridade dos peixes. É necessário atingir a contribuição mínima de dano do chefe.",
		"",
	}
	for key, boss in Bosses.Bosses do
		-- Estilo de combate que o chefe ensina (StyleDrop): sorteio à parte, só para quem ainda não tem
		local styleDrop = boss.StyleDrop
		if styleDrop then
			local style = Styles.Styles[styleDrop.Style]
			table.insert(lines, string.format("%s — estilo %s (sorteio à parte, só para quem ainda não tem): normal %.2f%% · VIP %.2f%%",
				boss.Title or key, style and style.DisplayName or styleDrop.Style, styleDrop.Chance * 100,
				Config.DropChance(styleDrop.Chance, true, restricted) * 100))
		end
		if boss.Drops and #boss.Drops > 0 then
			table.insert(lines, (boss.Title or key) .. " — chances por item (sorteios independentes):")
			for _, drop in boss.Drops do
				local item = Items.Get(drop.Item)
				local boosted = Config.DropChance(drop.Chance, true, restricted)
				table.insert(lines, string.format("%s: normal %.2f%% · VIP %.2f%%", item and item.Name or drop.Item, drop.Chance*100, boosted*100))
			end
			table.insert(lines, if owned then "Resultados com seu VIP ativo:" else "Todos os resultados ao usar VIP:")
			for _, row in Odds.BossOutcomes(boss.Drops, true, restricted) do
				local names = {}; for _, id in row.Names do local item = Items.Get(id); table.insert(names, item and item.Name or id) end
				table.insert(lines, string.format("%s — %.4f%%", if #names == 0 then "Nenhum item" else table.concat(names, " + "), row.Units / 10000))
			end
			table.insert(lines, "")
		end
	end
	table.insert(lines, "CLÃS — o VIP não modifica estas chances:")
	local rows = {}; for _, clan in Clans.Clans do table.insert(rows, {Name = clan.Name, Chance = Clans.Chance(clan.Id)}) end
	for _, row in percentages(rows) do table.insert(lines, string.format("%s — %.4f%%", row.Name, row.Units / 10000)) end
	table.insert(lines, "Percentuais apresentados com arredondamento; todos os resultados de cada tabela somam 100%.")
	return table.concat(lines, "\n\n")
end
return Odds
