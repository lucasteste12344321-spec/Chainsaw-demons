-- Server-only ownership cache. Client-written attributes never grant a benefit.
local Marketplace = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local Config = require(game.ReplicatedStorage.GamepassConfig)
local Service = {}
local owned, ready, checking = {}, {}, {}
local changed = Instance.new("BindableEvent")
Service.Changed = changed.Event
local function publish(player)
	if not player.Parent then return end
	for _, key in Config.Order do player:SetAttribute("Pass" .. key, Service.Owns(player, key)) end
	player:SetAttribute("PassesReady", ready[player] == true)
	player:SetAttribute("VIPDropMultiplier", if Service.Owns(player, "VIP") and player:GetAttribute("RandomItemsRestricted") == false then 2 else 1)
	changed:Fire(player)
end
function Service.Owns(player, key) return owned[player] ~= nil and owned[player][key] == true end
function Service.Ready(player) return ready[player] == true end
function Service.Multiplier(player, key) return if Service.Owns(player, key) then 2 else 1 end
function Service.DropChance(player, chance)
	return Config.DropChance(chance, Service.Owns(player, "VIP"), player:GetAttribute("RandomItemsRestricted"))
end
function Service.Refresh(player)
	if checking[player] then return false end
	checking[player] = true
	owned[player] = owned[player] or {}
	local success = true
	for _, key in Config.Order do
		local id = Config.Passes[key].Id
		if id > 0 then
			local ok, result = pcall(Marketplace.UserOwnsGamePassAsync, Marketplace, player.UserId, id)
			if not player.Parent then checking[player] = nil; return false end
			if ok then owned[player][key] = result == true or owned[player][key] == true else success = false end
		else owned[player][key] = false end
	end
	checking[player] = nil; ready[player] = success; publish(player)
	return success
end
function Service.ConfirmPurchase(player, passId)
	local key = Config.KeyForId(passId)
	if not key or not player.Parent then return false end
	owned[player] = owned[player] or {}; owned[player][key] = true; publish(player)
	return true
end
function Service.PolicyChanged(player) publish(player) end
Players.PlayerRemoving:Connect(function(player) owned[player] = nil; ready[player] = nil; checking[player] = nil end)
return Service
