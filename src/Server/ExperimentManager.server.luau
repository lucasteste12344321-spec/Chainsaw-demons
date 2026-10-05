local ConfigService = game:GetService("ConfigService")
local Players = game:GetService("Players")

local ONBOARDING = "onboarding"

local function onPlayerAdded(player)
	local success, result = pcall(function()
		local playerConfigSnapshot = ConfigService:GetConfigForPlayerAsync(player)
		return playerConfigSnapshot:GetValue(ONBOARDING)
	end)

	if not success then
		warn("Erro ao pegar experimento de " .. player.Name, result)
		return
	end

	local onboarding = result

	print("================================")
	print(player.Name .. " entrou no experimento")
	print("VARIANTE:", onboarding)
	print("================================")

	if onboarding == "Control" then

		print(player.Name .. " recebeu o onboarding NORMAL")

		-- Tutorial atual aqui

	elseif onboarding == "fast" then

		print(player.Name .. " recebeu o onboarding RÁPIDO")

		-- Tutorial novo aqui

	else

		warn("Valor de onboarding desconhecido:", onboarding)

	end
end

Players.PlayerAdded:Connect(onPlayerAdded)