local Teleport = game:GetService("TeleportService")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local Store = game:GetService("DataStoreService"):GetDataStore("VIPServers_v1")
local Entitlements = require(script.Parent.GamepassEntitlements)
local Remotes = require(game.ReplicatedStorage.Remotes)
local Rooms = {}
local busy, cooldown = {}, {}
local function message(player, text)
	if player.Parent then Remotes.Notify:FireClient(player, "Servidor VIP", text, 5) end
end
function Rooms.IsReserved() return game.PrivateServerId ~= "" and game.PrivateServerOwnerId == 0 end
local function valid(record)
	return type(record) == "table" and record.PlaceId == game.PlaceId and type(record.Code) == "string" and record.Code ~= "" and type(record.PrivateId) == "string" and record.PrivateId ~= ""
end
function Rooms.Enter(player, public)
	if busy[player] or os.clock() < (cooldown[player] or 0) then return end
	if not public and not Entitlements.Owns(player, "VIP") then message(player, "O passe VIP é necessário."); return end
	if public and not Rooms.IsReserved() then message(player, "Você já está em um servidor público."); return end
	if RunService:IsStudio() then message(player, "O teleporte deve ser testado pelo aplicativo Roblox, no jogo publicado."); return end
	local character = player.Character
	if character and character:GetAttribute("Stunned") then return end
	busy[player] = true; cooldown[player] = os.clock() + 15
	local ok = pcall(function()
		local options = Instance.new("TeleportOptions")
		if not public then
			local key = "Owner_" .. game.PlaceId .. "_" .. player.UserId
			local room = Store:GetAsync(key)
			if not valid(room) then
				local code, privateId = Teleport:ReserveServerAsync(game.PlaceId)
				local candidate = { Code = code, PrivateId = privateId, PlaceId = game.PlaceId }
				room = Store:UpdateAsync(key, function(old) return if valid(old) then old else candidate end)
			end
			assert(valid(room), "Missing reservation")
			Store:SetAsync("Room_" .. room.PrivateId, { Owner = player.UserId, PlaceId = game.PlaceId })
			if game.PrivateServerId == room.PrivateId then message(player, "Você já está no seu servidor VIP."); busy[player] = nil; return end
			options.ReservedServerAccessCode = room.Code -- Never replicated or accepted from the client.
		end
		if player.Parent then Teleport:TeleportAsync(game.PlaceId, {player}, options) end
	end)
	if not ok then busy[player] = nil; message(player, "Não foi possível entrar agora. Tente novamente em alguns segundos.") end
	task.delay(30, function() busy[player] = nil end)
end
function Rooms.CheckArrival(player)
	if not Rooms.IsReserved() or RunService:IsStudio() then return end
	local ok, room = pcall(Store.GetAsync, Store, "Room_" .. game.PrivateServerId)
	if ok and type(room) == "table" and room.PlaceId == game.PlaceId and room.Owner == player.UserId and Entitlements.Owns(player, "VIP") then return end
	message(player, "Não foi possível confirmar o acesso a este servidor. Voltando ao público.")
	Rooms.Enter(player, true)
end
Teleport.TeleportInitFailed:Connect(function(player)
	if busy[player] then busy[player] = nil; message(player, "O teleporte falhou. Você pode tentar novamente.") end
end)
Players.PlayerRemoving:Connect(function(player) busy[player] = nil; cooldown[player] = nil end)
return Rooms
