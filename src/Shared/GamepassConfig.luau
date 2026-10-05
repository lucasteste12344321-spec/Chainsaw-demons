-- Fill these with GAME PASS IDs from this experience (not developer product IDs).
-- Zero leaves that pass unavailable; never opens a purchase prompt for a placeholder.
local Config = {}
Config.Order = { "DoubleXP", "DoubleGold", "VIP", "ExtraSlots" }
Config.Passes = {
	DoubleXP = { Id = 2006715499, Name = "2× XP", Description = "Doubles XP from combat, quests, events and fishing. Stacks with your clan bonus. Does not include codes or mastery." },
	DoubleGold = { Id = 2006961470, Name = "2× Gold", Description = "Doubles Gold from combat, quests, events and fish sales. Does not multiply codes, refunds or admin values." },
	VIP = { Id = 2005803494, Name = "VIP", Description = "2× boss item chance, 5 clan spins per day and your own reserved server. The XP and Gold passes are sold separately." },
	-- Saves extras (PlayerData): libera o 2º e o 3º save (250 Robux).
	ExtraSlots = { Id = 2005809666, Name = "+2 Save Slots", Description = "Unlocks save slots 2 and 3: play other characters with their own level, clan, path and items." },
}
Config.DailySpins = 5
Config.DailyOffsetSeconds = -3 * 3600 -- Reset at midnight in Brasilia (UTC-3).
Config.MaxSpins = 9999
function Config.Day(now) return math.floor((now + Config.DailyOffsetSeconds) / 86400) end
function Config.NextDailyAt(now) return (Config.Day(now) + 1) * 86400 - Config.DailyOffsetSeconds end
function Config.KeyForId(id)
	if type(id) ~= "number" or id <= 0 then return nil end
	for _, key in Config.Order do if Config.Passes[key].Id == id then return key end end
	return nil
end
function Config.DropChance(chance, vip, restricted)
	return math.clamp(chance * (if vip and restricted == false then 2 else 1), 0, 1)
end
return Config
