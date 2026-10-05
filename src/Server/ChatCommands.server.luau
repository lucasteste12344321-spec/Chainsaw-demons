local Players = game:GetService("Players")
local TeleportService = game:GetService("TeleportService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Teams = game:GetService("Teams")
local Remotes = require(ReplicatedStorage:WaitForChild("Remotes"))
local Admins = require(script.Parent:WaitForChild("Admins"))

local function notify(player, title, message)
	Remotes.Notify:FireClient(player, title, message, 3)
end
local function humanoidOf(player)
	return player.Character and player.Character:FindFirstChildOfClass("Humanoid")
end

Admins.BindCommand("/killall", function(player)
	for _, target in Players:GetPlayers() do
		local humanoid = humanoidOf(target)
		if target ~= player and humanoid then humanoid.Health = 0 end
	end
	notify(player, "Comando", "Todos os outros jogadores foram mortos.")
end)
Admins.BindCommand("/healall", function(player)
	for _, target in Players:GetPlayers() do
		local humanoid = humanoidOf(target)
		if humanoid then humanoid.Health = humanoid.MaxHealth end
	end
	notify(player, "Comando", "Todos os jogadores foram curados.")
end)
Admins.BindCommand("/heal", function(player)
	local humanoid = humanoidOf(player)
	if humanoid then humanoid.Health = humanoid.MaxHealth notify(player, "Comando", "Você foi curado.") end
end)
Admins.BindCommand("/speed", function(player)
	if player.Character then
		-- Temporário: não altera o stat salvo nem disputa WalkSpeed com o cliente.
		player.Character:SetAttribute("AdminWalkSpeed", 100)
		notify(player, "Comando", "Velocidade temporária aumentada para 100.")
	end
end)
Admins.BindCommand("/jump", function(player)
	local humanoid = humanoidOf(player)
	if not humanoid then return end
	if humanoid:GetAttribute("AdminOriginalJumpPower") == nil then
		humanoid:SetAttribute("AdminOriginalJumpPower", humanoid.JumpPower)
		humanoid:SetAttribute("AdminOriginalJumpHeight", humanoid.JumpHeight)
	end
	humanoid.JumpPower = 150
	humanoid.JumpHeight = 150 * 150 / (2 * math.max(1, workspace.Gravity))
	notify(player, "Comando", "Pulo aumentado.")
end)
Admins.BindCommand("/resetstats", function(player)
	local character = player.Character
	local humanoid = humanoidOf(player)
	if not character or not humanoid then return end
	character:SetAttribute("AdminWalkSpeed", nil)
	local power = humanoid:GetAttribute("AdminOriginalJumpPower")
	local height = humanoid:GetAttribute("AdminOriginalJumpHeight")
	if power ~= nil then humanoid.JumpPower = power end
	if height ~= nil then humanoid.JumpHeight = height end
	humanoid:SetAttribute("AdminOriginalJumpPower", nil)
	humanoid:SetAttribute("AdminOriginalJumpHeight", nil)
	humanoid.Health = humanoid.MaxHealth
	notify(player, "Comando", "Modificadores removidos e vida restaurada. Seus atributos foram preservados.")
end)
Admins.BindCommand("/tp", function(player, targetName)
	for _, target in Players:GetPlayers() do
		if target.Name:lower() == targetName:lower() then
			local root = target.Character and target.Character:FindFirstChild("HumanoidRootPart")
			if root and player.Character and player.Character:FindFirstChild("HumanoidRootPart") then
				player.Character:PivotTo(root.CFrame * CFrame.new(2, 0, 0))
				notify(player, "Teleport", "Teleportado para " .. target.Name)
			else
				notify(player, "Erro", "Personagem ainda não carregou.")
			end
			return
		end
	end
	notify(player, "Erro", "Jogador não encontrado.")
end)
Admins.BindCommand("/resetserver", function(player)
	notify(player, "Comando", "Reentrada dos jogadores solicitada.")
	local ok = pcall(function() TeleportService:TeleportAsync(game.PlaceId, Players:GetPlayers()) end)
	if not ok then notify(player, "Erro", "Não foi possível teleportar os jogadores (indisponível no Studio).") end
end)
Admins.BindCommand("/admins", function(player)
	local online = {}
	for _, target in Players:GetPlayers() do
		if Admins.IsAdmin(target) then table.insert(online, target.Name) end
	end
	notify(player, "Admins online", if #online > 0 then table.concat(online, ", ") else "Nenhum admin online.")
end)
Admins.BindCommand("/tm", function(player, teamName)
	for _, team in Teams:GetTeams() do
		if team.Name:lower() == teamName:lower() then
			player.Team = team
			player.Neutral = false
			player:SetAttribute("Team", team.Name)
			notify(player, "Time", "Você entrou no time " .. team.Name)
			return
		end
	end
	notify(player, "Erro", "Time inválido. Use o nome de um time existente.")
end)
