-- Fill these with GAME PASS IDs from this experience (not developer product IDs).
-- Zero leaves that pass unavailable; never opens a purchase prompt for a placeholder.
local Config = {}
Config.Order = { "DoubleXP", "DoubleGold", "VIP" }
Config.Passes = {
	DoubleXP = { Id = 2006715499, Name = "2× XP", Description = "Dobra o XP de combate, missões, eventos e pesca. Acumula com o bônus do clã. Não inclui códigos nem maestria." },
	DoubleGold = { Id = 2006961470, Name = "2× Gold", Description = "Dobra o Gold de combate, missões, eventos e venda de peixes. Não multiplica códigos, reembolsos ou valores de admin." },
	VIP = { Id = 2005803494, Name = "VIP", Description = "2× chance de itens dos chefes, 5 giros de clã por dia e seu servidor reservado. Os passes de XP e Gold são vendidos separadamente." },
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
