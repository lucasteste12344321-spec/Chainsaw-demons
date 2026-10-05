-- Barra do chefe (topo da tela): aparece com um chefe acordado perto (ou depois de você bater nele).
-- Mostra nome, level e fase, a vida, o dano de cada jogador (atributo BossDamage, JSON escrito pelo BossService)
-- e os drops com as chances (ReplicatedStorage.BossData + ItemData).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")

local UITheme = require(ReplicatedStorage:WaitForChild("UITheme"))
local BossData = require(ReplicatedStorage:WaitForChild("BossData"))
local ItemData = require(ReplicatedStorage:WaitForChild("ItemData"))

local Colors = UITheme.Colors
local Fonts = UITheme.Fonts

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local SHOW_RANGE = 150 -- studs até o chefe para a barra aparecer
local TOP_DAMAGE = 5
local CHECK_INTERVAL = 0.25

-- ================= Interface =================

local gui = UITheme.screen("BossBar", 2, playerGui)

local container = UITheme.new("Frame", {
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 64),
	Size = UDim2.fromOffset(560, 0),
	AutomaticSize = Enum.AutomaticSize.Y,
	BackgroundTransparency = 1,
	Visible = false,
	Parent = gui,
})
UITheme.list(container, 6)
UITheme.autoScale(container, 1100, 700)

-- Nome + fase
local titleRow = UITheme.new("Frame", {
	Size = UDim2.new(1, 0, 0, 30),
	BackgroundTransparency = 1,
	LayoutOrder = 1,
	Parent = container,
})
local titleLabel = UITheme.label({
	Size = UDim2.new(1, -120, 1, 0),
	Font = Fonts.Display,
	TextSize = 28,
	TextColor3 = Colors.Gold,
	TextStrokeTransparency = 0.3,
	Parent = titleRow,
})
local phaseLabel = UITheme.label({
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.fromScale(1, 0),
	Size = UDim2.new(0, 120, 1, 0),
	TextXAlignment = Enum.TextXAlignment.Right,
	Font = Fonts.Display,
	TextSize = 22,
	TextColor3 = Colors.Accent,
	TextStrokeTransparency = 0.3,
	Parent = titleRow,
})

-- Vida
local healthBar = UITheme.bar({
	Size = UDim2.new(1, 0, 0, 24),
	LayoutOrder = 2,
	Parent = container,
}, Colors.Health, 15)

-- Dano e drops lado a lado
local infoPanel = UITheme.panel({
	Size = UDim2.new(1, 0, 0, 0),
	AutomaticSize = Enum.AutomaticSize.Y,
	BackgroundTransparency = 0.25,
	LayoutOrder = 3,
	Parent = container,
})
UITheme.padding(infoPanel, 8, 10, 8, 10)

local function column(position, title)
	local frame = UITheme.new("Frame", {
		Position = position,
		Size = UDim2.new(0.5, -6, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		Parent = infoPanel,
	})
	UITheme.list(frame, 2)
	UITheme.label({
		Size = UDim2.new(1, 0, 0, 18),
		Font = Fonts.Display,
		TextSize = 17,
		TextColor3 = Colors.Orange,
		Text = title,
		LayoutOrder = 0,
		Parent = frame,
	})
	return frame
end
local damageColumn = column(UDim2.fromScale(0, 0), "DANO")
local dropsColumn = column(UDim2.new(0.5, 6, 0, 0), "DROPS")

local function row(parent, order)
	return UITheme.label({
		Size = UDim2.new(1, 0, 0, 16),
		Font = Fonts.Body,
		TextSize = 13,
		TextTruncate = Enum.TextTruncate.AtEnd,
		LayoutOrder = order,
		Parent = parent,
	})
end

local damageRows = {}
for i = 1, TOP_DAMAGE + 1 do
	damageRows[i] = row(damageColumn, i)
end

local dropRows = {}

-- ================= Dados =================

local currentBoss, currentHumanoid
local bossConnections = {}

local function disconnectBoss()
	for _, connection in bossConnections do
		connection:Disconnect()
	end
	table.clear(bossConnections)
end

local function readDamage(boss)
	local ok, data = pcall(function()
		return HttpService:JSONDecode(boss:GetAttribute("BossDamage") or "{}")
	end)
	local list = {}
	if ok and type(data) == "table" then
		for userId, damage in data do
			table.insert(list, { UserId = tonumber(userId), Damage = damage })
		end
	end
	table.sort(list, function(a, b)
		return a.Damage > b.Damage
	end)
	return list
end

local function playerName(userId)
	local other = userId and Players:GetPlayerByUserId(userId)
	return if other then other.DisplayName else "(saiu)"
end

local function updateDamage()
	if not currentBoss or not currentHumanoid then return end
	local list = readDamage(currentBoss)
	local maxHealth = math.max(1, currentHumanoid.MaxHealth)
	local mineShown = false
	for i = 1, TOP_DAMAGE + 1 do
		damageRows[i].Visible = false
	end
	for i = 1, math.min(TOP_DAMAGE, #list) do
		local entry = list[i]
		local mine = entry.UserId == player.UserId
		mineShown = mineShown or mine
		local label = damageRows[i]
		label.Visible = true
		label.TextColor3 = if mine then Colors.Gold else Colors.Text
		label.Text = `{i}. {playerName(entry.UserId)}  {UITheme.formatNumber(entry.Damage)} ({UITheme.formatPercent(entry.Damage / maxHealth)})`
	end
	if not mineShown then
		for index, entry in list do
			if entry.UserId == player.UserId then
				local label = damageRows[TOP_DAMAGE + 1]
				label.Visible = true
				label.TextColor3 = Colors.Gold
				label.Text = `{index}. Você  {UITheme.formatNumber(entry.Damage)} ({UITheme.formatPercent(entry.Damage / maxHealth)})`
				break
			end
		end
	end
	if #list == 0 then
		local label = damageRows[1]
		label.Visible = true
		label.TextColor3 = Colors.TextDim
		label.Text = "Ninguém bateu ainda."
	end
end

local function updateHealth()
	if not currentHumanoid then return end
	local health, maxHealth = math.max(0, currentHumanoid.Health), math.max(1, currentHumanoid.MaxHealth)
	local text = if health <= 0 then "DERROTADO" else `{UITheme.formatNumber(math.ceil(health))} / {UITheme.formatNumber(maxHealth)}`
	healthBar.Set(health / maxHealth, text)
end

local function updateTitle()
	if not currentBoss then return end
	local enemyType = currentBoss:GetAttribute("EnemyType")
	local config = BossData.Get(enemyType)
	local name = if config and config.Title then config.Title else tostring(enemyType)
	titleLabel.Text = `👑 {UITheme.upper(name)}  Lv. {currentBoss:GetAttribute("Level") or "?"}`
	phaseLabel.Text = if currentBoss:GetAttribute("BossPhase") == 2 then "FÚRIA!" else ""
end

local function updateDrops()
	for _, label in dropRows do
		label:Destroy()
	end
	table.clear(dropRows)
	local config = currentBoss and BossData.Get(currentBoss:GetAttribute("EnemyType"))
	for index, drop in (config and config.Drops) or {} do
		local item = ItemData.Get(drop.Item)
		if item then
			local label = row(dropsColumn, index)
			label.TextColor3 = ItemData.RarityColors[item.Rarity] or Colors.Text
			label.Text = `{item.Name}  {UITheme.formatPercent(drop.Chance)}`
			table.insert(dropRows, label)
		end
	end
end

local function setBoss(boss)
	if boss == currentBoss then return end
	disconnectBoss()
	currentBoss = boss
	currentHumanoid = boss and boss:FindFirstChildOfClass("Humanoid")
	container.Visible = boss ~= nil
	if not boss or not currentHumanoid then return end
	table.insert(bossConnections, currentHumanoid.HealthChanged:Connect(updateHealth))
	table.insert(bossConnections, boss:GetAttributeChangedSignal("BossDamage"):Connect(updateDamage))
	table.insert(bossConnections, boss:GetAttributeChangedSignal("BossPhase"):Connect(updateTitle))
	updateTitle()
	updateHealth()
	updateDamage()
	updateDrops()
end

-- Dano que eu já causei neste chefe
local function myDamage(boss)
	for _, entry in readDamage(boss) do
		if entry.UserId == player.UserId then
			return entry.Damage
		end
	end
	return 0
end

-- Chefe mais perto que está acordado (ou em que eu já bati), dentro de SHOW_RANGE
local function pickBoss()
	local character = player.Character
	local myRoot = character and character:FindFirstChild("HumanoidRootPart")
	local enemies = workspace:FindFirstChild("Enemies")
	if not myRoot or not enemies then return nil end
	local best, bestDistance = nil, SHOW_RANGE
	for _, model in enemies:GetChildren() do
		if model:GetAttribute("Boss") ~= true then continue end
		local root = model:FindFirstChild("HumanoidRootPart")
		local humanoid = model:FindFirstChildOfClass("Humanoid")
		if not root or not humanoid then continue end
		local distance = (root.Position - myRoot.Position).Magnitude
		local relevant = model:GetAttribute("BossAwake") == true or myDamage(model) > 0
		if relevant and distance <= bestDistance then
			best, bestDistance = model, distance
		end
	end
	return best
end

task.spawn(function()
	while true do
		task.wait(CHECK_INTERVAL)
		-- Chefe derrotado continua na tela até o corpo sumir
		if currentBoss and currentBoss.Parent and currentHumanoid and currentHumanoid.Health <= 0 then
			continue
		end
		setBoss(pickBoss())
	end
end)
