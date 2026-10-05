-- Painel do servidor VIP (cliente: VIPPanel.client). Remotes.VIPPanel (C->S: action, value) e Remotes.VIPPanelState
-- (S->C: estado). Regras e salvamento ficam no VIPServers.
--   Todos: "State", "Accept"/"Decline" (convite), "Join" (servidor de um dono que liberou você), "Leave" (volta ao público)
--   Dono do passe VIP (as listas dele, de qualquer servidor): "Go" (vai para o próprio servidor), "Invite" (alguém deste
--     servidor), "WhitelistAdd"/"WhitelistRemove", "ModAdd"/"ModRemove", "Unban" (userId ou nome)
--   No servidor VIP, dono ou mod: "PvP" (bool), "Kick" (userId). Só o dono: "Ban" (userId; também tira da lista)
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage:WaitForChild("Remotes"))
local Entitlements = require(script.Parent:WaitForChild("GamepassEntitlements"))
local Rooms = require(script.Parent:WaitForChild("VIPServers"))

local RATE = 0.3
local lastAction = {}
local allowedCache = {} -- [Player] = { donos que liberaram } (lido ao abrir o painel)
local names = {} -- [userId] = nome

local function nameOf(userId)
	if type(userId) ~= "number" then return nil end
	local online = Players:GetPlayerByUserId(userId)
	if online then return online.DisplayName end
	if names[userId] then return names[userId] end
	local ok, name = pcall(Players.GetNameFromUserIdAsync, Players, userId)
	names[userId] = if ok and type(name) == "string" then name else tostring(userId)
	return names[userId]
end

local function named(list)
	local result = {}
	for _, userId in list do
		table.insert(result, { UserId = userId, Name = nameOf(userId) })
	end
	return result
end

local function stateFor(player)
	local reserved = Rooms.IsReserved()
	local ownerId = Rooms.OwnerId()
	local isVIP = Entitlements.Owns(player, "VIP")
	local data = {
		Reserved = reserved,
		OwnerId = ownerId,
		OwnerName = ownerId and nameOf(ownerId),
		Role = if reserved then Rooms.RoleOf(player.UserId) else nil,
		IsVIP = isVIP,
		Players = {},
	}
	if reserved and ownerId then
		data.PvP = Rooms.GetSettings(ownerId).PvP
	end
	for _, other in Players:GetPlayers() do
		if other ~= player then
			table.insert(data.Players, {
				UserId = other.UserId,
				Name = other.DisplayName,
				Role = if reserved then Rooms.RoleOf(other.UserId) else nil,
			})
		end
	end
	if isVIP then
		local settings = Rooms.GetSettings(player.UserId)
		data.Mods = named(settings.Mods)
		data.Whitelist = named(settings.Whitelist)
		data.Banned = named(settings.Banned)
	end
	local invite = Rooms.InviteOf(player)
	if invite then
		data.Invite = { OwnerId = invite.Owner, OwnerName = invite.OwnerName }
	end
	data.Allowed = named(allowedCache[player] or {})
	return data
end

local function push(player)
	if not player.Parent then return end
	task.spawn(function()
		local ok, data = pcall(stateFor, player)
		if ok and player.Parent then
			Remotes.VIPPanelState:FireClient(player, data)
		end
	end)
end

local function pushAll()
	for _, player in Players:GetPlayers() do
		push(player)
	end
end

-- userId (número) ou nome de usuário (texto) -> userId
local function resolveUser(value)
	if type(value) == "number" and value > 0 then return math.floor(value) end
	if type(value) == "string" then
		local name = string.match(value, "^%s*@?([%w_]+)%s*$")
		if not name or #name < 3 or #name > 20 then return nil end
		local ok, userId = pcall(Players.GetUserIdFromNameAsync, Players, name)
		if ok and type(userId) == "number" then return userId end
	end
	return nil
end

local function notify(player, text)
	Remotes.Notify:FireClient(player, "VIP Server", text, 4)
end

local LIST_ACTIONS = {
	WhitelistAdd = { "Whitelist", true, "Allowed to join your server." },
	WhitelistRemove = { "Whitelist", false, "Removed from the list." },
	ModAdd = { "Mods", true, "Is now a mod of your server." },
	ModRemove = { "Mods", false, "Is no longer a mod." },
	Unban = { "Banned", false, "Unbanned." },
}

local function handle(player, action, value)
	local reserved = Rooms.IsReserved()
	local ownerId = Rooms.OwnerId()
	local role = if reserved then Rooms.RoleOf(player.UserId) else nil

	if action == "State" then
		allowedCache[player] = Rooms.AllowedFor(player.UserId)
	elseif action == "Go" then
		Rooms.Enter(player, false)
	elseif action == "Leave" then
		Rooms.Enter(player, true)
	elseif action == "Accept" or action == "Join" then
		Rooms.EnterRoomOf(player, value)
	elseif action == "Decline" then
		Rooms.Decline(player)
	elseif action == "Invite" then
		local target = type(value) == "number" and Players:GetPlayerByUserId(value)
		if target and not reserved and Rooms.Invite(player, target) then
			push(target)
		end
	elseif LIST_ACTIONS[action] then
		if not Entitlements.Owns(player, "VIP") then notify(player, "The VIP pass is required."); return end
		local userId = resolveUser(value)
		if not userId or userId == player.UserId then notify(player, "Player not found."); return end
		local entry = LIST_ACTIONS[action]
		if Rooms.Update(player.UserId, entry[1], userId, entry[2]) then
			notify(player, `{nameOf(userId)}: {entry[3]}`)
		else
			notify(player, "The list is full (max 50).")
		end
	elseif action == "PvP" then
		if not role or not ownerId then return end
		Rooms.Update(ownerId, "PvP", nil, value == true)
		for _, other in Players:GetPlayers() do
			notify(other, if value == true then "PvP is on in this server." else "PvP is off in this server.")
		end
	elseif action == "Kick" or action == "Ban" then
		if not role or not ownerId then return end
		if action == "Ban" and role ~= "Owner" then return end
		local target = type(value) == "number" and Players:GetPlayerByUserId(value)
		if not target or target == player then return end
		local targetRole = Rooms.RoleOf(target.UserId)
		if targetRole == "Owner" or (targetRole == "Mod" and role ~= "Owner") then
			notify(player, "You cannot remove that person.")
			return
		end
		if action == "Ban" then
			Rooms.Update(ownerId, "Whitelist", target.UserId, false)
			Rooms.Update(ownerId, "Mods", target.UserId, false)
			Rooms.Update(ownerId, "Banned", target.UserId, true)
		end
		Rooms.SendToPublic(target, if action == "Ban" then "You were banned from this VIP server." else "You were kicked from this VIP server.")
		notify(player, `{target.DisplayName} was {if action == "Ban" then "banned" else "kicked"}.`)
	end
end

Remotes.VIPPanel.OnServerEvent:Connect(function(player, action, value)
	if type(action) ~= "string" then return end
	local clock = os.clock()
	if clock < (lastAction[player] or 0) then return end
	lastAction[player] = clock + RATE
	local ok, err = pcall(handle, player, action, value)
	if not ok then
		warn("[VIPPanel] " .. tostring(err))
	end
	push(player)
end)

Rooms.Changed:Connect(pushAll)
Entitlements.Changed:Connect(push)
Players.PlayerAdded:Connect(function(player)
	task.delay(3, push, player)
end)
Players.PlayerRemoving:Connect(function(player)
	lastAction[player] = nil
	allowedCache[player] = nil
end)
