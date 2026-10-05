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
		"PERMANENT PASSES · one-time purchase",
		"2× XP and 2× Gold are separate from VIP. The bonuses multiply in-game earnings after the clan bonus. Codes, refunds and admin commands are not multiplied.",
		"VIP: 5 spins when you join or claim each day. Resets at midnight Brasília time (UTC-3); days you do not play do not stack. If your 9,999-spin reserve is full, use some spins before claiming.",
		"VIP server: a personal reserved server, accessed through the shop button. It is not a native Roblox private server subscription.",
		if restricted then "YOUR ACCOUNT: the luck bonus does not apply; the 5 spins become credits for a guaranteed clan choice, as in the clan menu." else "VIP doubles the chance of each boss item (max 100%). It does not double the amount or change fish rarity. You must reach the minimum damage contribution on the boss.",
		"",
	}
	for key, boss in Bosses.Bosses do
		-- Estilo de combate que o chefe ensina (StyleDrop): sorteio à parte, só para quem ainda não tem
		local styleDrop = boss.StyleDrop
		if styleDrop then
			local style = Styles.Styles[styleDrop.Style]
			table.insert(lines, string.format("%s — %s style (separate roll, only if you do not have it yet): normal %.2f%% · VIP %.2f%%",
				boss.Title or key, style and style.DisplayName or styleDrop.Style, styleDrop.Chance * 100,
				Config.DropChance(styleDrop.Chance, true, restricted) * 100))
		end
		if boss.Drops and #boss.Drops > 0 then
			table.insert(lines, (boss.Title or key) .. " — chance per item (independent rolls):")
			for _, drop in boss.Drops do
				local item = Items.Get(drop.Item)
				local boosted = Config.DropChance(drop.Chance, true, restricted)
				table.insert(lines, string.format("%s: normal %.2f%% · VIP %.2f%%", item and item.Name or drop.Item, drop.Chance*100, boosted*100))
			end
			table.insert(lines, if owned then "Results with your active VIP:" else "All results when using VIP:")
			for _, row in Odds.BossOutcomes(boss.Drops, true, restricted) do
				local names = {}; for _, id in row.Names do local item = Items.Get(id); table.insert(names, item and item.Name or id) end
				table.insert(lines, string.format("%s — %.4f%%", if #names == 0 then "No item" else table.concat(names, " + "), row.Units / 10000))
			end
			table.insert(lines, "")
		end
	end
	table.insert(lines, "CLANS — VIP does not change these chances:")
	local rows = {}; for _, clan in Clans.Clans do table.insert(rows, {Name = clan.Name, Chance = Clans.Chance(clan.Id)}) end
	for _, row in percentages(rows) do table.insert(lines, string.format("%s — %.4f%%", row.Name, row.Units / 10000)) end
	table.insert(lines, "Percentages are rounded; all results in each table add up to 100%.")
	return table.concat(lines, "\n\n")
end
return Odds
