-- Servidor VIP (passe VIP, GamepassConfig): cada dono tem um servidor reservado (ReserveServerAsync) guardado no
-- DataStore. Entram no servidor de um dono: ele mesmo, quem está na lista de liberados dele (Whitelist) e quem ele
-- convidou agora (convite de 2 minutos, feito pelo painel VIP no servidor público). Banidos não entram e, se estiverem
-- lá, voltam para o público. O código de acesso nunca sai do servidor: só este módulo leva alguém para lá.
-- Configurações do dono ("Settings_<dono>"): PvP, Mods, Whitelist, Banned. Lista inversa "Allowed_<jogador>" = donos
-- que liberaram esse jogador (aba ENTRAR do painel).
-- No servidor VIP: workspace.PvPDisabled (CombatRules.CanDamage) e o atributo VIPRole ("Owner"/"Mod") de cada jogador.
-- Teste no Studio: ReplicatedStorage:SetAttribute("TestVIPServer", true) antes do Play = o servidor finge ser VIP do
-- primeiro jogador que entrar (o painel funciona; o teleporte não, só no jogo publicado).
local Teleport = game:GetService("TeleportService")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Store = game:GetService("DataStoreService"):GetDataStore("VIPServers_v1")
local Entitlements = require(script.Parent.GamepassEntitlements)
local Remotes = require(game.ReplicatedStorage.Remotes)

local Rooms = {}
local MAX_LIST = 50 -- máximo de nomes em cada lista do dono
local INVITE_TIME = 120

local busy, cooldown = {}, {}
local invites = {} -- [Player convidado] = { Owner = userId, Expires = os.clock() }
local settingsCache = {} -- [donoId] = configurações
local roomOwnerId = nil -- dono deste servidor (só no servidor VIP)
local changed = Instance.new("BindableEvent")
Rooms.Changed = changed.Event -- algo mudou (o painel manda o estado de novo)

local function message(player, text)
	if player.Parent then Remotes.Notify:FireClient(player, "Servidor VIP", text, 5) end
end

local function testMode()
	return RunService:IsStudio() and ReplicatedStorage:GetAttribute("TestVIPServer") == true
end

function Rooms.IsReserved()
	return (game.PrivateServerId ~= "" and game.PrivateServerOwnerId == 0) or testMode()
end

function Rooms.OwnerId()
	return roomOwnerId
end

local function valid(record)
	return type(record) == "table" and record.PlaceId == game.PlaceId and type(record.Code) == "string" and record.Code ~= "" and type(record.PrivateId) == "string" and record.PrivateId ~= ""
end

-- ================= Configurações do dono =================

local function cleanList(list)
	local result, seen = {}, {}
	if type(list) == "table" then
		for _, id in list do
			if type(id) == "number" and id > 0 and not seen[id] and #result < MAX_LIST then
				seen[id] = true
				table.insert(result, math.floor(id))
			end
		end
	end
	return result
end

local function cleanSettings(raw)
	raw = if type(raw) == "table" then raw else {}
	return {
		PvP = raw.PvP ~= false,
		Mods = cleanList(raw.Mods),
		Whitelist = cleanList(raw.Whitelist),
		Banned = cleanList(raw.Banned),
	}
end

function Rooms.GetSettings(ownerId)
	if settingsCache[ownerId] then return settingsCache[ownerId] end
	local settings
	if RunService:IsStudio() then
		settings = cleanSettings(nil)
	else
		local ok, raw = pcall(Store.GetAsync, Store, "Settings_" .. ownerId)
		settings = cleanSettings(ok and raw or nil)
	end
	settingsCache[ownerId] = settingsCache[ownerId] or settings
	return settingsCache[ownerId]
end

local function saveSettings(ownerId)
	local settings = settingsCache[ownerId]
	if not settings or RunService:IsStudio() then return end
	task.spawn(pcall, Store.SetAsync, Store, "Settings_" .. ownerId, settings)
end

-- Lista inversa: donos que liberaram este jogador
function Rooms.AllowedFor(userId)
	if RunService:IsStudio() then return {} end
	local ok, list = pcall(Store.GetAsync, Store, "Allowed_" .. userId)
	return cleanList(ok and list or nil)
end

local function setAllowed(userId, ownerId, allowed)
	if RunService:IsStudio() then return end
	task.spawn(pcall, Store.UpdateAsync, Store, "Allowed_" .. userId, function(old)
		local list = cleanList(old)
		local index = table.find(list, ownerId)
		if allowed and not index and #list < MAX_LIST then
			table.insert(list, ownerId)
		elseif not allowed and index then
			table.remove(list, index)
		end
		return list
	end)
end

local function contains(list, id)
	return table.find(list, id) ~= nil
end

-- Papel de alguém no servidor VIP atual: "Owner", "Mod" ou nil
function Rooms.RoleOf(userId)
	if not roomOwnerId then return nil end
	if userId == roomOwnerId then return "Owner" end
	if contains(Rooms.GetSettings(roomOwnerId).Mods, userId) then return "Mod" end
	return nil
end

local function applyRoomSettings()
	if not roomOwnerId then return end
	local settings = Rooms.GetSettings(roomOwnerId)
	workspace:SetAttribute("PvPDisabled", not settings.PvP)
	workspace:SetAttribute("VIPOwnerId", roomOwnerId)
	for _, player in Players:GetPlayers() do
		player:SetAttribute("VIPRole", Rooms.RoleOf(player.UserId))
	end
end

-- Muda uma lista (Mods, Whitelist, Banned) ou o PvP do dono e salva
function Rooms.Update(ownerId, field, userId, value)
	local settings = Rooms.GetSettings(ownerId)
	if field == "PvP" then
		settings.PvP = value == true
	else
		local list = settings[field]
		if type(list) ~= "table" or type(userId) ~= "number" then return false end
		local index = table.find(list, userId)
		if value and not index then
			if #list >= MAX_LIST then return false end
			table.insert(list, userId)
		elseif not value and index then
			table.remove(list, index)
		else
			return true
		end
		if field == "Whitelist" then
			setAllowed(userId, ownerId, value)
		end
	end
	saveSettings(ownerId)
	if ownerId == roomOwnerId then
		applyRoomSettings()
	end
	changed:Fire()
	return true
end

-- ================= Teleporte =================

-- Servidor reservado de um dono (cria na primeira vez, se create)
local function roomOf(ownerId, create)
	local key = "Owner_" .. game.PlaceId .. "_" .. ownerId
	local room = Store:GetAsync(key)
	if valid(room) or not create then
		return if valid(room) then room else nil
	end
	local code, privateId = Teleport:ReserveServerAsync(game.PlaceId)
	local candidate = { Code = code, PrivateId = privateId, PlaceId = game.PlaceId }
	room = Store:UpdateAsync(key, function(old) return if valid(old) then old else candidate end)
	if valid(room) then
		Store:SetAsync("Room_" .. room.PrivateId, { Owner = ownerId, PlaceId = game.PlaceId })
	end
	return if valid(room) then room else nil
end

local function teleportInto(player, room)
	local options = Instance.new("TeleportOptions")
	options.ReservedServerAccessCode = room.Code -- nunca vai para o cliente
	if player.Parent then Teleport:TeleportAsync(game.PlaceId, { player }, options) end
end

local function canStart(player)
	if busy[player] or os.clock() < (cooldown[player] or 0) then return false end
	if RunService:IsStudio() then message(player, "O teleporte deve ser testado pelo aplicativo Roblox, no jogo publicado."); return false end
	local character = player.Character
	if character and character:GetAttribute("Stunned") then return false end
	return true
end

local function run(player, action)
	busy[player] = true; cooldown[player] = os.clock() + 15
	local ok, err = pcall(action)
	if not ok then
		busy[player] = nil
		warn("[VIPServers] " .. tostring(err))
		message(player, "Não foi possível entrar agora. Tente novamente em alguns segundos.")
	end
	task.delay(30, function() busy[player] = nil end)
end

-- public = true: volta para um servidor público. Senão vai para o próprio servidor VIP (precisa do passe).
function Rooms.Enter(player, public)
	if not public and not Entitlements.Owns(player, "VIP") then message(player, "O passe VIP é necessário."); return end
	if public and not Rooms.IsReserved() then message(player, "Você já está em um servidor público."); return end
	if not canStart(player) then return end
	run(player, function()
		if public then
			if player.Parent then Teleport:TeleportAsync(game.PlaceId, { player }, Instance.new("TeleportOptions")) end
			return
		end
		local room = roomOf(player.UserId, true)
		assert(room, "Missing reservation")
		if game.PrivateServerId == room.PrivateId then message(player, "Você já está no seu servidor VIP."); busy[player] = nil; return end
		teleportInto(player, room)
	end)
end

-- Entra no servidor VIP de outro dono: precisa estar na lista dele ou ter convite dele, e não estar banido
function Rooms.EnterRoomOf(player, ownerId)
	if type(ownerId) ~= "number" or ownerId == player.UserId then return end
	local settings = Rooms.GetSettings(ownerId)
	if contains(settings.Banned, player.UserId) then message(player, "Você foi banido desse servidor VIP."); return end
	local invite = invites[player]
	local invited = invite and invite.Owner == ownerId and os.clock() < invite.Expires
	if not invited and not contains(settings.Whitelist, player.UserId) then
		message(player, "Você não tem acesso a esse servidor VIP.")
		return
	end
	if not canStart(player) then return end
	invites[player] = nil
	run(player, function()
		local room = roomOf(ownerId, false)
		if not room then
			message(player, "O dono ainda não abriu o servidor VIP dele.")
			busy[player] = nil
			return
		end
		if game.PrivateServerId == room.PrivateId then message(player, "Você já está nesse servidor VIP."); busy[player] = nil; return end
		teleportInto(player, room)
	end)
end

-- Convite do dono (servidor público): vale INVITE_TIME s
function Rooms.Invite(owner, target)
	if not Entitlements.Owns(owner, "VIP") then message(owner, "O passe VIP é necessário."); return false end
	if target == owner or not target.Parent then return false end
	if contains(Rooms.GetSettings(owner.UserId).Banned, target.UserId) then message(owner, `{target.DisplayName} está banido do seu servidor.`); return false end
	invites[target] = { Owner = owner.UserId, OwnerName = owner.DisplayName, Expires = os.clock() + INVITE_TIME }
	message(owner, `Convite enviado para {target.DisplayName}.`)
	changed:Fire()
	return true
end

function Rooms.InviteOf(player)
	local invite = invites[player]
	if invite and os.clock() < invite.Expires then return invite end
	invites[player] = nil
	return nil
end

function Rooms.Decline(player)
	invites[player] = nil
end

-- Tira alguém do servidor VIP (volta para o público)
function Rooms.SendToPublic(player, text)
	if text then message(player, text) end
	busy[player] = nil; cooldown[player] = nil
	if RunService:IsStudio() then
		message(player, "(Studio: aqui você voltaria para um servidor público.)")
		return
	end
	run(player, function()
		if player.Parent then Teleport:TeleportAsync(game.PlaceId, { player }, Instance.new("TeleportOptions")) end
	end)
end

-- ================= Servidor VIP rodando =================

-- Quem chega: só este módulo traz gente para cá (o código não sai do servidor); banido volta para o público
function Rooms.CheckArrival(player)
	if not Rooms.IsReserved() then return end
	if not roomOwnerId and testMode() then
		roomOwnerId = player.UserId
		applyRoomSettings()
	end
	local deadline = os.clock() + 15
	while not roomOwnerId and os.clock() < deadline do task.wait(0.5) end
	if not roomOwnerId then return end
	player:SetAttribute("VIPRole", Rooms.RoleOf(player.UserId))
	if contains(Rooms.GetSettings(roomOwnerId).Banned, player.UserId) then
		Rooms.SendToPublic(player, "Você foi banido deste servidor VIP.")
	end
	changed:Fire()
end

if Rooms.IsReserved() and not RunService:IsStudio() then
	task.spawn(function()
		for attempt = 1, 5 do
			local ok, room = pcall(Store.GetAsync, Store, "Room_" .. game.PrivateServerId)
			if ok and type(room) == "table" and type(room.Owner) == "number" then
				roomOwnerId = room.Owner
				applyRoomSettings()
				changed:Fire()
				return
			end
			task.wait(attempt * 2)
		end
		warn("[VIPServers] Não achei o dono deste servidor VIP")
	end)
end

Teleport.TeleportInitFailed:Connect(function(player)
	if busy[player] then busy[player] = nil; message(player, "O teleporte falhou. Você pode tentar novamente.") end
end)
Players.PlayerRemoving:Connect(function(player)
	busy[player] = nil; cooldown[player] = nil; invites[player] = nil
	changed:Fire()
end)
return Rooms
