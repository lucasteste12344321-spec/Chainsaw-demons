-- Notificações: toasts (Remotes.Notify) empilhados no topo e banner grande de anúncio (Remotes.Announcement).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage:WaitForChild("Remotes"))
local UITheme = require(ReplicatedStorage:WaitForChild("UITheme"))

local Colors = UITheme.Colors
local Fonts = UITheme.Fonts

local MAX_TOASTS = 4

local gui = UITheme.screen("Notifications", 20, Players.LocalPlayer:WaitForChild("PlayerGui"))

-- Pilha de toasts no topo, no centro (o chat fica à esquerda e a lista de jogadores à direita)
local stack = UITheme.new("Frame", {
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 8),
	Size = UDim2.fromOffset(380, 0),
	AutomaticSize = Enum.AutomaticSize.Y,
	BackgroundTransparency = 1,
	Parent = gui,
})
UITheme.list(stack, 8, Enum.FillDirection.Vertical, Enum.HorizontalAlignment.Center)
UITheme.autoScale(stack, 420, 400)

local activeToasts = {}
local toastCounter = 0

-- Cor da faixa lateral conforme o título
local function accentFor(title)
	local lower = title:lower()
	if lower:find("level") or lower:find("complete") or lower:find("kill") or lower:find("defeated") then
		return Colors.Gold
	elseif lower:find("error") or lower:find("warning") then
		return Colors.Accent
	elseif lower:find("quest") then
		return Colors.Orange
	end
	return Colors.Blue
end

local function removeToast(toast)
	local index = table.find(activeToasts, toast)
	if not index then return end
	table.remove(activeToasts, index)
	UITheme.tween(toast.Scale, 0.18, { Scale = 0.85 })
	UITheme.tween(toast.Frame, 0.18, { BackgroundTransparency = 1 })
	for _, label in toast.Labels do
		UITheme.tween(label, 0.18, { TextTransparency = 1, TextStrokeTransparency = 1 })
	end
	task.delay(0.2, function()
		toast.Frame:Destroy()
	end)
end

local function showToast(title, message, duration)
	toastCounter += 1
	local accent = accentFor(title)

	local frame = UITheme.panel({
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 0.1,
		LayoutOrder = -toastCounter, -- o mais novo fica em cima
		Parent = stack,
	})
	UITheme.padding(frame, 10, 14, 10, 18)
	UITheme.list(frame, 2)

	-- Faixa colorida à esquerda (fora do layout: é filha de um Frame sem UIListLayout)
	local stripHolder = UITheme.new("Frame", {
		Size = UDim2.new(1, 0, 0, 0),
		BackgroundTransparency = 1,
		LayoutOrder = 0,
		Parent = frame,
	})
	UITheme.new("Frame", {
		Position = UDim2.fromOffset(-11, -2),
		Size = UDim2.fromOffset(4, 40),
		BackgroundColor3 = accent,
		BorderSizePixel = 0,
		Parent = stripHolder,
	})

	local heading = UITheme.label({
		Size = UDim2.new(1, 0, 0, 20),
		Font = Fonts.Display,
		TextSize = 16,
		TextColor3 = accent,
		Text = UITheme.upper(title),
		LayoutOrder = 1,
		Parent = frame,
	})
	local body = UITheme.label({
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		TextWrapped = true,
		Font = Fonts.Body,
		TextSize = 15,
		Text = message,
		LayoutOrder = 2,
		Parent = frame,
	})

	local scale = UITheme.new("UIScale", { Scale = 0.85, Parent = frame })
	UITheme.tween(scale, 0.22, { Scale = 1 }, Enum.EasingStyle.Back)

	local toast = { Frame = frame, Scale = scale, Labels = { heading, body } }
	table.insert(activeToasts, toast)
	if #activeToasts > MAX_TOASTS then
		removeToast(activeToasts[1])
	end

	task.delay(duration, function()
		removeToast(toast)
	end)
end

-- ================= Banner =================

local banner = UITheme.new("Frame", {
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, -140),
	Size = UDim2.new(0.8, 0, 0, 110),
	BackgroundColor3 = Colors.AccentDark,
	BackgroundTransparency = 0.05,
	BorderSizePixel = 0,
	Visible = false,
	ZIndex = 5,
	Parent = gui,
})
UITheme.new("UISizeConstraint", { MaxSize = Vector2.new(780, 110), Parent = banner })
UITheme.corner(banner, UDim.new(0, 12))
UITheme.stroke(banner, Colors.Gold, 2, 0.2)
UITheme.gradient(banner, { Color3.fromRGB(255, 255, 255), Color3.fromRGB(110, 110, 110) })
UITheme.padding(banner, 12, 20)

local bannerTitle = UITheme.label({
	Size = UDim2.new(1, 0, 0, 30),
	TextXAlignment = Enum.TextXAlignment.Center,
	Font = Fonts.Display,
	TextSize = 26,
	TextColor3 = Colors.Gold,
	TextStrokeTransparency = 0.4,
	ZIndex = 6,
	Parent = banner,
})
local bannerBody = UITheme.label({
	Position = UDim2.fromOffset(0, 34),
	Size = UDim2.new(1, 0, 1, -34),
	TextXAlignment = Enum.TextXAlignment.Center,
	TextYAlignment = Enum.TextYAlignment.Top,
	TextWrapped = true,
	Font = Fonts.Title,
	TextSize = 17,
	TextStrokeTransparency = 0.5,
	ZIndex = 6,
	Parent = banner,
})

local bannerToken = 0
local function showBanner(title, message, duration)
	bannerToken += 1
	local token = bannerToken
	bannerTitle.Text = `📢 {UITheme.upper(title)}`
	bannerBody.Text = message
	banner.Visible = true
	banner.Position = UDim2.new(0.5, 0, 0, -140)
	UITheme.tween(banner, 0.35, { Position = UDim2.new(0.5, 0, 0, 12) }, Enum.EasingStyle.Back)
	-- Os avisos (toasts) descem para baixo do banner enquanto ele aparece, para não ficarem escondidos
	UITheme.tween(stack, 0.35, { Position = UDim2.new(0.5, 0, 0, 12 + math.max(banner.AbsoluteSize.Y, 110) + 8) })

	task.delay(duration, function()
		if token ~= bannerToken then return end
		UITheme.tween(banner, 0.3, { Position = UDim2.new(0.5, 0, 0, -140) }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		UITheme.tween(stack, 0.3, { Position = UDim2.new(0.5, 0, 0, 8) })
		task.delay(0.32, function()
			if token == bannerToken then
				banner.Visible = false
			end
		end)
	end)
end

local function cleanDuration(duration)
	return if type(duration) == "number" and duration == duration then math.clamp(duration, 1, 15) else 3
end

Remotes.Notify.OnClientEvent:Connect(function(title, message, duration)
	if type(title) ~= "string" or type(message) ~= "string" then return end
	showToast(title, message, cleanDuration(duration))
end)

Remotes.Announcement.OnClientEvent:Connect(function(title, message, duration)
	if type(title) ~= "string" or type(message) ~= "string" then return end
	showBanner(title, message, cleanDuration(duration))
end)
