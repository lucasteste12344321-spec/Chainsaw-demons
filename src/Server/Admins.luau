-- Lista única de permissões, somente no servidor.
local Players = game:GetService("Players")
local TextChatService = game:GetService("TextChatService")
local Admins = {}
local USER_IDS = {
	[3496725636] = true,
	[8307767509] = true,
	[1866665817] = true,
}
local lastCommand = {}

function Admins.IsAdmin(player)
	return USER_IDS[player.UserId] == true
end

function Admins.BindCommand(alias, callback)
	local command = Instance.new("TextChatCommand")
	command.Name = "Admin_" .. alias:sub(2)
	command.PrimaryAlias = alias
	command.AutocompleteVisible = false -- não mostrar comandos de admin para todo mundo
	command.Parent = TextChatService
	command.Triggered:Connect(function(source, text)
		local player = Players:GetPlayerByUserId(source.UserId)
		if not player or not Admins.IsAdmin(player) then return end
		local now = os.clock()
		if now - (lastCommand[player] or -math.huge) < 0.5 then return end
		lastCommand[player] = now
		local arguments = text:match("^%S+%s*(.-)%s*$") or ""
		callback(player, arguments)
	end)
	return command
end

Players.PlayerRemoving:Connect(function(player) lastCommand[player] = nil end)
return Admins
