local PhysicsService = game:GetService("PhysicsService")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

-- Registra grupos de colisão (ignora se já existem)
for _, group in { "NPCs", "Players" } do
	if not PhysicsService:IsCollisionGroupRegistered(group) then
		PhysicsService:RegisterCollisionGroup(group)
	end
end

-- Define que NPCs e Players não colidem entre si
PhysicsService:CollisionGroupSetCollidable("NPCs", "Players", false)

-- Função para aplicar grupo de colisão
local function setCollisionGroupRecursive(model, groupName)
	for _, part in ipairs(model:GetDescendants()) do
		if part:IsA("BasePart") then
			part.CollisionGroup = groupName
		end
	end
end

local function groupFor(character)
	return if Players:GetPlayerFromCharacter(character) then "Players" else "NPCs"
end

-- Só modelos com Humanoid são personagens; modelos do mapa/VFX não criam tarefas de espera.
local function characterOf(part)
	local model = part:FindFirstAncestorOfClass("Model")
	while model do
		if model:FindFirstChildOfClass("Humanoid") then return model end
		model = model:FindFirstAncestorOfClass("Model")
	end
	return nil
end

-- Humanoid adicionado por último: atualiza o corpo. Peça/acessório adicionado depois: atualiza só a peça.
Workspace.DescendantAdded:Connect(function(desc)
	if desc:IsA("Humanoid") then
		local character = desc.Parent
		if character and character:IsA("Model") then
			setCollisionGroupRecursive(character, groupFor(character))
		end
	elseif desc:IsA("BasePart") then
		local character = characterOf(desc)
		if character then
			desc.CollisionGroup = groupFor(character)
		end
	end
end)

for _, desc in Workspace:GetDescendants() do
	if desc:IsA("Humanoid") and desc.Parent and desc.Parent:IsA("Model") then
		setCollisionGroupRecursive(desc.Parent, groupFor(desc.Parent))
	end
end

-- Aplica grupo de colisão aos jogadores quando spawnarem
local function onCharacter(character)
	setCollisionGroupRecursive(character, "Players")
end

local function onPlayer(player)
	player.CharacterAdded:Connect(onCharacter)
	if player.Character then
		task.spawn(onCharacter, player.Character)
	end
end

Players.PlayerAdded:Connect(onPlayer)
for _, player in Players:GetPlayers() do
	onPlayer(player)
end
