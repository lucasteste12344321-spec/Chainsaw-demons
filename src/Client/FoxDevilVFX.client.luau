-- Mordida da Raposa (Kon): toca o efeito (ReplicatedStorage.FoxDevilVFX) quando o servidor manda CombatFX "FoxBite",
-- e a finalização (o Kon devora quem ficou com pouca vida) quando manda "FoxDevour".
-- Só pode existir UM script deste no StarterPlayerScripts: uma cópia a mais toca o Kon duas vezes.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ContentProvider = game:GetService("ContentProvider")
local Remotes = require(ReplicatedStorage:WaitForChild("Remotes"))
local Renderer = require(ReplicatedStorage:WaitForChild("FoxDevilVFX"))
local FoxConfig = require(ReplicatedStorage:WaitForChild("FoxDevilConfig"))
local FastMode = require(script.Parent:WaitForChild("FastMode"))
Remotes.CombatFX.OnClientEvent:Connect(function(kind, data)
	if type(data) ~= "table" then return end
	if kind == "FoxBite" then
		Renderer.Play(data, FastMode.IsEnabled())
	elseif kind == "FoxDevour" then
		Renderer.Devour(data, FastMode.IsEnabled())
	elseif kind == "FoxLunge" then
		Renderer.Lunge(data, FastMode.IsEnabled())
	elseif kind == "FoxLungeCatch" then
		Renderer.LungeCatch(data, FastMode.IsEnabled())
	end
end)
task.spawn(function()
	local assets = ReplicatedStorage:WaitForChild("VFX"):WaitForChild("FoxDevil", 30)
	if assets then pcall(function() ContentProvider:PreloadAsync(assets:GetDescendants()) end) end
	local sounds = {}
	for _, id in FoxConfig.DevourSounds do table.insert(sounds, "rbxassetid://" .. id) end
	pcall(function() ContentProvider:PreloadAsync(sounds) end)
end)
