-- Pure merge rules used inside PlayerData's UpdateAsync. No rewards occur in the callback.
local Config = require(game.ReplicatedStorage.GamepassConfig)
local Rules = {}
local function integer(value, default, maximum)
	return if type(value) == "number" and value == value and value >= 0 and value <= maximum then math.floor(value) else default
end
function Rules.Reconcile(saved)
	saved = if type(saved) == "table" then saved else {}
	return { Day = integer(saved.Day, -1, 10000000), Total = integer(saved.Total, 0, 1000000000) }
end
function Rules.Merge(snapshot, stored, claimDay)
	local result = table.clone(snapshot)
	local mine = Rules.Reconcile(snapshot.VIPRewards)
	local old = Rules.Reconcile(if type(stored) == "table" then stored.VIPRewards else nil)
	local total = math.max(mine.Total, old.Total)
	local day = math.max(mine.Day, old.Day)
	local spins = math.clamp(snapshot.Spins + total - mine.Total, 0, Config.MaxSpins)
	if claimDay and day < claimDay and spins <= Config.MaxSpins - Config.DailySpins then
		spins += Config.DailySpins; total += Config.DailySpins; day = claimDay
	end
	result.Spins = spins
	result.VIPRewards = { Day = day, Total = total }
	return result
end
return Rules
