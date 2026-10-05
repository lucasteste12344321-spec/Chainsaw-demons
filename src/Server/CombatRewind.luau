-- Uma amostra por personagem/NPC a 30 Hz. Memória e atraso máximos definidos no CombatNetConfig.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Config = require(game:GetService("ReplicatedStorage"):WaitForChild("CombatNetConfig"))
local History = require(script.Parent:WaitForChild("PositionHistory"))
local Rewind = {}
local tracked = {}

local function track(model)
	if model:IsA("Model") and not tracked[model] then
		tracked[model] = { History = History.new(Config), SeenWorld = model:IsDescendantOf(workspace) }
	end
end

local function onPlayer(player)
	player.CharacterAdded:Connect(track)
	player.CharacterRemoving:Connect(function(character) tracked[character] = nil end)
	if player.Character then track(player.Character) end
end
Players.PlayerAdded:Connect(onPlayer)
Players.PlayerRemoving:Connect(function(player)
	if player.Character then tracked[player.Character] = nil end
end)
for _, player in Players:GetPlayers() do onPlayer(player) end

local enemyFolder, enemyConnections
local function watchEnemies(folder)
	if folder.Name ~= "Enemies" or folder == enemyFolder then return end
	if enemyConnections then
		for _, connection in enemyConnections do connection:Disconnect() end
	end
	enemyFolder = folder
	enemyConnections = {
		folder.ChildAdded:Connect(track),
		folder.ChildRemoved:Connect(function(model) tracked[model] = nil end),
	}
	for _, model in folder:GetChildren() do track(model) end
end
workspace.ChildAdded:Connect(watchEnemies)
local enemies = workspace:FindFirstChild("Enemies")
if enemies then watchEnemies(enemies) end

local elapsed = 0
RunService.Heartbeat:Connect(function(dt)
	elapsed += dt
	if elapsed < 1 / Config.HistoryRate then return end
	elapsed %= 1 / Config.HistoryRate
	local now = workspace:GetServerTimeNow()
	for model, entry in tracked do
		local root = model:FindFirstChild("HumanoidRootPart")
		local hum = model:FindFirstChildOfClass("Humanoid")
		local inWorld = model:IsDescendantOf(workspace)
		-- CharacterAdded pode ocorrer antes de o personagem entrar no Workspace.
		if (entry.SeenWorld and not inWorld) or (hum and hum.Health <= 0) then
			tracked[model] = nil
		elseif inWorld then
			entry.SeenWorld = true
			if entry.Root ~= root then
				entry.Root = root
				entry.History = History.new(Config)
			end
			if root and root:IsA("BasePart") and hum then entry.History:Push(now, root.CFrame) end
		end
	end
end)

function Rewind.Frame(model, time)
	local entry = tracked[model]
	return entry and entry.History:At(time) or nil
end

Rewind.FrameValid = History.FrameValid

-- Timestamp do cliente nunca aumenta o orçamento: ping é medido no servidor e há teto de 250 ms.
-- extraSlack (opcional): folga a mais só para conferir se o pedido é recente (o dash usa; não aumenta o rewind)
function Rewind.ResolveTime(player, timestamp, receivedAt, extraSlack)
	if not History.Finite(timestamp) then return nil end
	local ok, ping = pcall(function() return player:GetNetworkPing() end)
	-- Creator Hub define GetNetworkPing como ida e volta (RTT); estima cada trecho pela metade.
	ping = if ok and History.Finite(ping) then math.clamp(ping / 2, 0, Config.RewindWindow) else 0
	local budget = math.min(Config.RewindWindow, ping + Config.TimestampSlack) + (extraSlack or 0)
	if timestamp > receivedAt + Config.FutureSlack or receivedAt - timestamp > budget then return nil end
	local sentAt = math.min(timestamp, receivedAt)
	-- O alvo desenhado no cliente também chega atrasado. Nunca extrapola além da janela máxima.
	return math.max(receivedAt - Config.RewindWindow, sentAt - ping), sentAt
end

-- A origem que o cliente mandou está perto do caminho que o servidor viu o personagem fazer (de OriginLookback antes
-- do envio até agora)? Antes comparava com um ponto só, na hora do envio: a posição do personagem chega ao servidor com
-- o atraso do ping, e correndo com ping alto a diferença passava da tolerância (dash recusado e puxado para trás).
function Rewind.Origin(character, timestamp, frame)
	if not History.FrameValid(frame) then return nil end
	local entry = tracked[character]
	local distance = entry and entry.History:DistanceToPath(timestamp - Config.OriginLookback, frame.Position)
	if not distance or distance > Config.OriginTolerance then return nil end
	return frame
end

return Rewind
