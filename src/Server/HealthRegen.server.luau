-- Regeneração fora de combate da árvore de habilidades (nó "Regeneração": atributo TreeRegen no player, fração da
-- vida máxima por segundo). Só volta a regenerar depois de COMBAT_DELAY segundos sem levar dano.
local Players = game:GetService("Players")

local TICK = 0.5
local COMBAT_DELAY = 5

local lastDamage = setmetatable({}, { __mode = "k" }) -- [Humanoid] = os.clock() do último dano

local function watch(character)
	local humanoid = character:WaitForChild("Humanoid", 10)
	if not humanoid then return end
	local last = humanoid.Health
	humanoid.HealthChanged:Connect(function(health)
		if health < last then
			lastDamage[humanoid] = os.clock()
		end
		last = health
	end)
end

local function onPlayer(player)
	player.CharacterAdded:Connect(watch)
	if player.Character then
		task.spawn(watch, player.Character)
	end
end

Players.PlayerAdded:Connect(onPlayer)
for _, player in Players:GetPlayers() do
	onPlayer(player)
end

while true do
	task.wait(TICK)
	local clock = os.clock()
	for _, player in Players:GetPlayers() do
		local regen = player:GetAttribute("TreeRegen")
		if type(regen) ~= "number" or regen <= 0 then continue end
		local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		if not humanoid or humanoid.Health <= 0 or humanoid.Health >= humanoid.MaxHealth then continue end
		if clock - (lastDamage[humanoid] or 0) < COMBAT_DELAY then continue end
		humanoid.Health = math.min(humanoid.MaxHealth, humanoid.Health + humanoid.MaxHealth * regen * TICK)
	end
end
