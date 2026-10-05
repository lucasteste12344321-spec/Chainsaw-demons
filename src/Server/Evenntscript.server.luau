local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextService = game:GetService("TextService")
local Remotes = require(ReplicatedStorage:WaitForChild("Remotes"))
local Admins = require(script.Parent:WaitForChild("Admins"))

Admins.BindCommand("/anunciar", function(player, message)
	if message == "" or #message > 500 then
		Remotes.Notify:FireClient(player, "Aviso", "Use /anunciar seguido de uma mensagem de até 500 bytes.", 3)
		return
	end
	-- Texto escrito por um jogador precisa ser filtrado antes da transmissão.
	local ok, filtered = pcall(function()
		local result = TextService:FilterStringAsync(message, player.UserId)
		return result:GetNonChatStringForBroadcastAsync()
	end)
	if not ok then
		Remotes.Notify:FireClient(player, "Aviso", "Não foi possível filtrar o anúncio. Tente novamente depois.", 3)
		return
	end
	Remotes.Announcement:FireAllClients("Aviso", filtered, 6)
end)
