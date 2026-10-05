-- Números de dano e contador de acertos de quem bate. O servidor (CombatRules.Damage) avisa o jogador a cada dano que
-- ele causou, de golpe, skill ou poder (Remotes.CombatDamage: vítima, dano, resultado).
--   Número: salta da vítima num arco (sobe, abre para um lado e cai um pouco), maior e creme nos golpes fortes, azul
--   quando foi bloqueado. Fica numa ScreenGui seguindo o ponto 3D (e não num BillboardGui): sempre por cima de tudo.
--   Contador: do lado esquerdo da tela, conta os acertos seguidos e o dano somado; some e zera depois de COMBO_WINDOW
--   sem acertar. Golpe bloqueado mostra o número mas não conta no combo.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Remotes = require(ReplicatedStorage:WaitForChild("Remotes"))
local UITheme = require(ReplicatedStorage:WaitForChild("UITheme"))

local player = Players.LocalPlayer
local random = Random.new()
local Colors, Fonts = UITheme.Colors, UITheme.Fonts

local COMBO_WINDOW = 2.2 -- segundos sem acertar até o contador zerar
local COMBO_MIN = 2 -- o contador aparece a partir desse número de acertos
local MAX_NUMBERS = 40 -- números na tela ao mesmo tempo (os mais velhos somem antes)
local MAX_PER_VICTIM = 6
local NUMBER_DISTANCE = 160
local NUMBER_LIFE = 0.85
local GRAVITY = 30 -- studs/s² puxando o número para baixo depois do salto

local BLOCKED_COLOR = Color3.fromRGB(150, 190, 235)
local BROKEN_COLOR = Color3.fromRGB(255, 120, 60)
local INK = Color3.fromRGB(30, 0, 5)

local playerGui = player:WaitForChild("PlayerGui")

----------------------------------------------------------------------------------------------------
-- Números de dano
----------------------------------------------------------------------------------------------------

local numbersScreen = UITheme.screen("DamageNumbers", 3, playerGui)
numbersScreen.IgnoreGuiInset = true -- mesma origem do Camera:WorldToViewportPoint

local numbers = {} -- { Label, Scale, Victim, Origin, Velocity, Born, Heavy }

local function removeNumber(index)
	local entry = table.remove(numbers, index)
	entry.Label:Destroy()
end

local function showNumber(victim, amount, result)
	local anchor = victim:FindFirstChild("Head") or victim:FindFirstChild("HumanoidRootPart")
	local camera = workspace.CurrentCamera
	if not anchor or not anchor:IsA("BasePart") or not camera then return end
	if (camera.CFrame.Position - anchor.Position).Magnitude > NUMBER_DISTANCE then return end

	-- Golpe forte (uns 8% da vida da vítima, ou 40+): maior e creme
	local humanoid = victim:FindFirstChildOfClass("Humanoid")
	local maxHealth = if humanoid and humanoid.MaxHealth > 0 then humanoid.MaxHealth else 100
	local heavy = result ~= "Blocked" and amount >= math.max(40, maxHealth * 0.08)
	local color = if result == "Blocked" then BLOCKED_COLOR
		elseif result == "Broken" then BROKEN_COLOR
		elseif heavy then Colors.Gold
		else Colors.White

	-- Salto: sai de perto da cabeça, para cima e para um lado da tela (direita ou esquerda da câmera)
	local side = camera.CFrame.RightVector * (if random:NextNumber() < 0.5 then -1 else 1)
	local velocity = side * random:NextNumber(3, 6.5) + Vector3.new(0, random:NextNumber(11, 15), 0)
	local origin = anchor.Position + Vector3.new(0, 0.6, 0) + side * random:NextNumber(0, 0.6)

	local label = UITheme.label({
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromOffset(160, 56),
		Font = Fonts.Display,
		TextSize = math.clamp(22 + math.sqrt(amount) * 1.7, 22, 50),
		TextXAlignment = Enum.TextXAlignment.Center,
		TextColor3 = color,
		TextStrokeColor3 = INK,
		TextStrokeTransparency = 0,
		Text = UITheme.formatNumber(amount),
		Visible = false,
		Parent = numbersScreen,
	})
	local scale = Instance.new("UIScale")
	scale.Scale = 0.3
	scale.Parent = label

	table.insert(numbers, {
		Label = label,
		Scale = scale,
		Victim = victim,
		Origin = origin,
		Velocity = velocity,
		Born = os.clock(),
		Heavy = heavy,
	})

	-- Limites: no total e por vítima (Rajada e golpes seguidos não empilham sem fim)
	local count = 0
	for index = #numbers, 1, -1 do
		if numbers[index].Victim == victim then
			count += 1
			if count > MAX_PER_VICTIM then
				removeNumber(index)
			end
		end
	end
	while #numbers > MAX_NUMBERS do
		removeNumber(1)
	end
end

-- Um só laço para todos: posição no arco, projeção na tela, pulo de tamanho no começo e sumir no fim
RunService.RenderStepped:Connect(function()
	if #numbers == 0 then return end
	local camera = workspace.CurrentCamera
	if not camera then return end
	local clock = os.clock()
	for index = #numbers, 1, -1 do
		local entry = numbers[index]
		local t = clock - entry.Born
		if t >= NUMBER_LIFE then
			removeNumber(index)
			continue
		end
		local position = entry.Origin + entry.Velocity * t - Vector3.new(0, 0.5 * GRAVITY * t * t, 0)
		local point, onScreen = camera:WorldToViewportPoint(position)
		local label = entry.Label
		label.Visible = onScreen and point.Z > 0
		label.Position = UDim2.fromOffset(point.X, point.Y)
		-- Pula de tamanho (maior nos fortes), assenta e some no último terço
		local peak = if entry.Heavy then 1.45 else 1.2
		entry.Scale.Scale = if t < 0.08 then 0.3 + (peak - 0.3) * (t / 0.08)
			elseif t < 0.2 then peak + (1 - peak) * ((t - 0.08) / 0.12)
			else 1
		local fade = math.clamp((t - NUMBER_LIFE * 0.6) / (NUMBER_LIFE * 0.4), 0, 1)
		label.TextTransparency = fade
		label.TextStrokeTransparency = fade
	end
end)

----------------------------------------------------------------------------------------------------
-- Contador de acertos
----------------------------------------------------------------------------------------------------

local screen = UITheme.screen("HitCounter", 4, playerGui)
local holder = UITheme.new("Frame", {
	Name = "Counter",
	AnchorPoint = Vector2.new(0, 0.5),
	Position = UDim2.new(0, 34, 0.4, 0),
	Size = UDim2.fromOffset(240, 118),
	BackgroundTransparency = 1,
	Visible = false,
	Parent = screen,
})
local holderScale = UITheme.new("UIScale", { Parent = holder })
local countLabel = UITheme.label({
	Name = "Count",
	Size = UDim2.new(1, 0, 0, 70),
	Font = Fonts.Display,
	TextSize = 68,
	TextColor3 = Colors.White,
	TextStrokeColor3 = INK,
	TextStrokeTransparency = 0,
	Parent = holder,
})
local hitsLabel = UITheme.label({
	Name = "Hits",
	Position = UDim2.fromOffset(4, 62),
	Size = UDim2.new(1, 0, 0, 30),
	Font = Fonts.Display,
	TextSize = 28,
	TextColor3 = Colors.Accent,
	TextStrokeColor3 = INK,
	TextStrokeTransparency = 0.2,
	Text = "HITS",
	Parent = holder,
})
local damageLabel = UITheme.label({
	Name = "Damage",
	Position = UDim2.fromOffset(4, 92),
	Size = UDim2.new(1, 0, 0, 20),
	Font = Fonts.Title,
	TextSize = 15,
	TextColor3 = Colors.Gold,
	TextStrokeColor3 = INK,
	TextStrokeTransparency = 0.4,
	Parent = holder,
})
local fading = { countLabel, hitsLabel, damageLabel }
local strokeOf = { [countLabel] = 0, [hitsLabel] = 0.2, [damageLabel] = 0.4 }

local combo, comboDamage, lastHitAt = 0, 0, 0

local function hideCounter()
	combo, comboDamage = 0, 0
	for _, label in fading do
		UITheme.tween(label, 0.3, { TextTransparency = 1, TextStrokeTransparency = 1 })
	end
	task.delay(0.32, function()
		if combo == 0 then
			holder.Visible = false
		end
	end)
end

local function countHit(amount)
	local clock = os.clock()
	if clock - lastHitAt > COMBO_WINDOW then
		combo, comboDamage = 0, 0
	end
	lastHitAt = clock
	combo += 1
	comboDamage += amount
	if combo < COMBO_MIN then return end

	countLabel.Text = tostring(combo)
	damageLabel.Text = UITheme.formatNumber(comboDamage) .. " DAMAGE"
	-- Quanto maior o combo, mais vermelho
	countLabel.TextColor3 = Colors.White:Lerp(Colors.Orange, math.clamp((combo - COMBO_MIN) / 20, 0, 1))
	holder.Visible = player:GetAttribute("MenuOpen") ~= true
	for _, label in fading do
		label.TextTransparency = 0
		label.TextStrokeTransparency = strokeOf[label]
	end
	holderScale.Scale = 1.22
	UITheme.tween(holderScale, 0.16, { Scale = 1 }, Enum.EasingStyle.Back)

	task.delay(COMBO_WINDOW, function()
		if os.clock() - lastHitAt >= COMBO_WINDOW - 0.01 and combo > 0 then
			hideCounter()
		end
	end)
end

----------------------------------------------------------------------------------------------------
-- Início
----------------------------------------------------------------------------------------------------

Remotes.CombatDamage.OnClientEvent:Connect(function(victim, amount, result)
	if typeof(victim) ~= "Instance" or not victim:IsA("Model") or type(amount) ~= "number" then return end
	if amount ~= amount or amount < 0 then return end
	showNumber(victim, amount, result)
	if result ~= "Blocked" and amount > 0 then
		countHit(amount)
	end
end)

player.CharacterAdded:Connect(function()
	if combo > 0 then
		hideCounter()
	end
end)
