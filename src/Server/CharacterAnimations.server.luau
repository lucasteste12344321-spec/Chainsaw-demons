-- Troca as animações padrão do Roblox (script Animate do personagem) pelas do CharacterAnimations.Default,
-- a cada renascimento. Mesmo método da documentação da Roblox ("Replace default animations").
-- Walk vale para "walk" e "run": o R6 anda com walk, o R15 mistura os dois conforme a velocidade.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CharacterAnimations = require(ReplicatedStorage:WaitForChild("CharacterAnimations"))

-- [chave no Default] = lista de { pasta dentro do Animate, Animation dentro da pasta }
local TARGETS = {
	Idle = { { "idle", "Animation1" }, { "idle", "Animation2" } },
	Walk = { { "walk", "WalkAnim" }, { "run", "RunAnim" } },
	Jump = { { "jump", "JumpAnim" } },
	Fall = { { "fall", "FallAnim" } },
	Climb = { { "climb", "ClimbAnim" } },
}

local function hasOverrides()
	for key in TARGETS do
		if CharacterAnimations.Id(CharacterAnimations.Default[key]) then
			return true
		end
	end
	return false
end

local function onCharacterAdded(character)
	if not hasOverrides() then return end
	local humanoid = character:WaitForChild("Humanoid", 10)
	local animate = character:WaitForChild("Animate", 10)
	if not humanoid or not animate then return end

	-- Para o que já está tocando, para o Animate recomeçar com as animações novas
	local animator = humanoid:FindFirstChildOfClass("Animator")
	if animator then
		for _, track in animator:GetPlayingAnimationTracks() do
			track:Stop(0)
		end
	end

	for key, targets in TARGETS do
		local id = CharacterAnimations.Id(CharacterAnimations.Default[key])
		if not id then continue end
		for _, target in targets do
			local folder = animate:FindFirstChild(target[1])
			local animation = folder and folder:FindFirstChild(target[2])
			if animation and animation:IsA("Animation") then
				animation.AnimationId = "rbxassetid://" .. id
			end
		end
	end
end

local function onPlayer(player)
	player.CharacterAdded:Connect(onCharacterAdded)
	if player.Character then
		task.spawn(onCharacterAdded, player.Character)
	end
end

Players.PlayerAdded:Connect(onPlayer)
for _, player in Players:GetPlayers() do
	onPlayer(player)
end
