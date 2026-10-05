-- Rede de segurança contra queda: quem cair abaixo do mapa (buraco, borda, bug de física) volta para o último lugar
-- onde estava pisando em chão firme, em vez de morrer no vazio.
-- O mapa foi conferido com raios em 2026-10-01: o canal oeste tinha três frestas sem colisão (a faixa de "água" é só
-- textura), tapadas no Studio em ChainsawCity.Collision.Canal.FallFix. O chão mais baixo do mapa fica em y = -4.
local Players = game:GetService("Players")

local VOID_Y = -40 -- abaixo disso é queda
local CHECK_INTERVAL = 0.25
local SAFE_INTERVAL = 0.5 -- de quanto em quanto tempo guarda a posição segura
local GROUND_PROBE = 4.5 -- da raiz até o chão (R6 em pé: 3 studs)
local RETURN_LIFT = 3 -- volta um pouco acima do chão

local lastSafe = {} -- [player] = CFrame da raiz pisando em chão firme
local nextSafeAt = {}

local probeParams = RaycastParams.new()
probeParams.FilterType = Enum.RaycastFilterType.Exclude
probeParams.RespectCanCollide = true

-- Pisando em chão firme agora? (o FloorMaterial é do cliente: aqui o servidor confere com um raio)
local function grounded(character, root)
	probeParams.FilterDescendantsInstances = { character }
	return workspace:Raycast(root.Position, Vector3.new(0, -GROUND_PROBE, 0), probeParams) ~= nil
end

-- Para onde volta sem posição segura: o spawn do jogador ou o primeiro SpawnLocation
local function fallbackCFrame(player)
	local spawnLocation = player.RespawnLocation
	if not spawnLocation then
		for _, item in workspace:GetDescendants() do
			if item:IsA("SpawnLocation") then
				spawnLocation = item
				break
			end
		end
	end
	return spawnLocation and spawnLocation.CFrame + Vector3.new(0, 4, 0) or nil
end

Players.PlayerRemoving:Connect(function(player)
	lastSafe[player] = nil
	nextSafeAt[player] = nil
end)

while true do
	task.wait(CHECK_INTERVAL)
	local clock = os.clock()
	for _, player in Players:GetPlayers() do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if not root or not humanoid or humanoid.Health <= 0 then continue end
		if root.Position.Y < VOID_Y then
			local target = lastSafe[player] or fallbackCFrame(player)
			if target then
				character:PivotTo(target + Vector3.new(0, RETURN_LIFT, 0))
				root.AssemblyLinearVelocity = Vector3.zero
				root.AssemblyAngularVelocity = Vector3.zero
			else
				player:LoadCharacter()
			end
		elseif clock >= (nextSafeAt[player] or 0) and grounded(character, root) then
			lastSafe[player] = root.CFrame
			nextSafeAt[player] = clock + SAFE_INTERVAL
		end
	end
end
