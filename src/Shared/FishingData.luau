-- Shared catalog and save migration. Catch rolls and rewards are decided by the server.
local Data = {}
Data.Order = { "RiverCarp", "Perch", "Trout", "Catfish", "Koi", "GhostEel" }
Data.Fish = {
	RiverCarp = { Name = "Kuro Carp", Rarity = "Common", Weight = 40, Price = 8, MinKg = 0.4, MaxKg = 2.8, Difficulty = 0.8, Color = Color3.fromRGB(180, 155, 100) },
	Perch = { Name = "Striped Perch", Rarity = "Common", Weight = 30, Price = 10, MinKg = 0.3, MaxKg = 1.9, Difficulty = 0.9, Color = Color3.fromRGB(115, 159, 109) },
	Trout = { Name = "Silver Trout", Rarity = "Uncommon", Weight = 18, Price = 16, MinKg = 0.6, MaxKg = 3.5, Difficulty = 1.0, Color = Color3.fromRGB(148, 199, 210) },
	Catfish = { Name = "Root Catfish", Rarity = "Uncommon", Weight = 9, Price = 22, MinKg = 1.2, MaxKg = 6.0, Difficulty = 1.1, Color = Color3.fromRGB(83, 103, 119) },
	Koi = { Name = "Scarlet Koi", Rarity = "Rare", Weight = 2.5, Price = 55, MinKg = 1.0, MaxKg = 5.0, Difficulty = 1.2, Color = Color3.fromRGB(231, 116, 74) },
	GhostEel = { Name = "Spectral Eel", Rarity = "Epic", Weight = 0.5, Price = 100, MinKg = 1.5, MaxKg = 7.0, Difficulty = 1.35, Night = true, Color = Color3.fromRGB(167, 136, 229) },
}
Data.Rods = {
	{ Name = "Bamboo Rod", Price = 0, Catches = 0, Control = 1, Luck = 1 },
	{ Name = "Reinforced Rod", Price = 750, Catches = 20, Control = 1.14, Luck = 1.25 },
	{ Name = "Kuro River Rod", Price = 2200, Catches = 60, Control = 1.28, Luck = 1.6 },
}
Data.BagLimit = 150
Data.SpotRange = 15
Data.MoveLimit = 12
Data.MaxCastRange = 48
Data.HookWindow = 1.8
Data.NPCId = "KuroDaichi"

local function number(value, default, low, high)
	return if type(value) == "number" and value == value and math.abs(value) < math.huge then math.clamp(value, low, high) else default
end

function Data.Reconcile(saved)
	saved = if type(saved) == "table" then saved else {}
	local data = {
		HasRod = saved.HasRod == true,
		RodTier = math.floor(number(saved.RodTier, 1, 1, #Data.Rods)),
		Catches = math.floor(number(saved.Catches, 0, 0, 10000000)),
		Meals = math.floor(number(saved.Meals, 0, 0, 20)),
		Counts = {}, Records = {},
	}
	local remaining = Data.BagLimit
	for _, id in Data.Order do
		local count = math.floor(number(type(saved.Counts) == "table" and saved.Counts[id], 0, 0, remaining))
		data.Counts[id] = count; remaining -= count
		data.Records[id] = number(type(saved.Records) == "table" and saved.Records[id], 0, 0, Data.Fish[id].MaxKg)
	end
	return data
end

function Data.BagCount(data)
	local count = 0
	for _, id in Data.Order do count += data.Counts[id] or 0 end
	return count
end

function Data.SaleValue(data)
	local value = 0
	for _, id in Data.Order do value += (data.Counts[id] or 0) * Data.Fish[id].Price end
	return value
end

function Data.CatchWeight(id, rodTier, hour, hotspot)
	local fish = Data.Fish[id]
	if fish.Night and hour >= 6 and hour < 18 then return 0 end
	local value = fish.Weight
	if id == "Koi" or id == "GhostEel" then value *= Data.Rods[rodTier].Luck end
	if hotspot then value *= if fish.Rarity == "Common" then 0.8 else 1.5 end
	return value
end

return Data
