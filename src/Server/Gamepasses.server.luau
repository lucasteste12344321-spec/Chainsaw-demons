local Players = game:GetService("Players")
local Marketplace = game:GetService("MarketplaceService")
local RS = game:GetService("ReplicatedStorage")
local Remotes = require(RS.Remotes)
local Config = require(RS.GamepassConfig)
local Entitlements = require(script.Parent.GamepassEntitlements)
local Data = require(script.Parent.PlayerData)
local Rooms = require(script.Parent.VIPServers)
local times, refreshTimes, claims = {}, {}, {}
local function snapshot(player)
	if not player.Parent then return end
	local owned = {}; for _, key in Config.Order do owned[key] = Entitlements.Owns(player, key) end
	local profile = Data.GetProfile(player)
	Remotes.GamepassState:FireClient(player, { Owned = owned, Ready = Entitlements.Ready(player),
		DailyClaimed = profile ~= nil and profile.VIPRewards.Day >= Config.Day(os.time()),
		NextDailyAt = Config.NextDailyAt(os.time()), Reserved = Rooms.IsReserved(),
		Restricted = player:GetAttribute("RandomItemsRestricted") ~= false })
end
local function claim(player, automatic)
	if claims[player] or not Entitlements.Owns(player, "VIP") or not Data.GetProfile(player) then return end
	claims[player] = true
	local ok, reason = Data.ClaimVIPDaily(player)
	claims[player] = nil
	if player.Parent and (ok or not automatic) then
		Remotes.Notify:FireClient(player, "VIP", if ok then "+5 giros de clã diários recebidos!" else reason, 5)
	end
	snapshot(player)
end
Entitlements.Changed:Connect(function(player) snapshot(player); task.spawn(claim, player, true) end)
Data.ProfileLoaded:Connect(function(player) snapshot(player); task.spawn(claim, player, true) end)
local function joined(player)
	player:GetAttributeChangedSignal("RandomItemsRestricted"):Connect(function() Entitlements.PolicyChanged(player) end)
	for attempt = 1, 3 do
		if not player.Parent then return end
		if Entitlements.Refresh(player) then break end
		task.wait(attempt * 3)
	end
	if player.Parent then Rooms.CheckArrival(player) end
end
Players.PlayerAdded:Connect(function(player) task.spawn(joined, player) end)
for _, player in Players:GetPlayers() do task.spawn(joined, player) end
Marketplace.PromptGamePassPurchaseFinished:Connect(function(player, id, success)
	if success then Entitlements.ConfirmPurchase(player, id) end
end)
Remotes.GamepassAction.OnServerEvent:Connect(function(player, action)
	if type(action) ~= "string" or os.clock() < (times[player] or 0) then return end
	times[player] = os.clock() + 1
	if action == "State" then snapshot(player)
	elseif action == "Refresh" then
		if os.clock() < (refreshTimes[player] or 0) then return end
		refreshTimes[player] = os.clock() + 30; Entitlements.Refresh(player)
	elseif action == "Daily" then claim(player, false)
	elseif action == "VIPServer" then Rooms.Enter(player, false)
	elseif action == "PublicServer" then Rooms.Enter(player, true) end
end)
Players.PlayerRemoving:Connect(function(player) times[player] = nil; refreshTimes[player] = nil; claims[player] = nil end)
task.spawn(function()
	while true do
		task.wait(60)
		for _, player in Players:GetPlayers() do task.spawn(claim, player, true) end
	end
end)
