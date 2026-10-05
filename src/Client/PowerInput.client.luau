-- Teclas V e B: pedem ao servidor para usar o poder do caminho (contrato do Caçador ou habilidade do Infernal).
-- Por dentro os slots continuam "Z" e "X" (PathData, PathSkills, atributos Power<slot>ReadyAt); Z/X/C são das
-- skills dos estilos (CombatInput).
-- O servidor (PathSkills) valida tudo de novo; aqui só evitamos pedidos que com certeza seriam recusados.
-- A HUD (HUB_GUI) também dispara Remotes.UsePower ao clicar/tocar no slot.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Remotes = require(ReplicatedStorage:WaitForChild("Remotes"))
local PathData = require(ReplicatedStorage:WaitForChild("PathData"))
local FoxAim = require(script.Parent:WaitForChild("FoxAim"))

local player = Players.LocalPlayer

local KEYS = {
	[Enum.KeyCode.V] = "Z",
	[Enum.KeyCode.B] = "X",
	-- Controle (Xbox): direcional para cima e para a direita
	[Enum.KeyCode.DPadUp] = "Z",
	[Enum.KeyCode.DPadRight] = "X",
	-- Modo híbrido de admin (/hibrido): poderes do Infernal em H e J
	[Enum.KeyCode.H] = "HZ",
	[Enum.KeyCode.J] = "HX",
}
local REQUEST_INTERVAL = 0.2 -- segundos entre dois pedidos (evita spam segurando a tecla)
local lastRequest = 0

local function canUse(slot)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 or character:GetAttribute("Stunned") == true then
		return false
	end
	-- Guarda levantada ou carregando o R: o servidor recusa (CombatState.IsLocked)
	if character:GetAttribute("Blocking") == true or character:GetAttribute("Charging") == true then
		return false
	end

	-- Habilidade do slot pelo caminho (e pelo modo híbrido de admin)
	if not PathData.PlayerSkill(player, slot) then
		return false
	end

	local readyAt = player:GetAttribute("Power" .. slot .. "ReadyAt")
	return type(readyAt) ~= "number" or workspace:GetServerTimeNow() >= readyAt
end

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed or player:GetAttribute("MenuOpen") then return end
	local slot = KEYS[input.KeyCode]
	if not slot or not canUse(slot) then return end

	local now = os.clock()
	if now - lastRequest < REQUEST_INTERVAL then return end
	lastRequest = now
	if FoxAim.IsFox(slot) then
		FoxAim.Begin(slot)
	elseif FoxAim.IsLunge(slot) then
		FoxAim.Cast(slot)
	else
		player:SetAttribute("PredictedRootUntil", workspace:GetServerTimeNow() + 0.4) -- parado já na hora
		Remotes.UsePower:FireServer(slot)
	end
end)

UserInputService.InputEnded:Connect(function(input)
	local slot = KEYS[input.KeyCode]
	if slot then FoxAim.Release(slot) end
end)
