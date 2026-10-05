-- Painel do servidor VIP (servidor: VIPPanel.server + VIPServers). Abre pelo botão SERVIDOR VIP da loja de passes
-- (BindableEvent VIPPanel.Toggle). Abas:
--   SERVIDOR: no público, ir para o próprio servidor e convidar quem está aqui; no servidor VIP, PvP, expulsar, banir e
--             dar mod (dono; mods só expulsam e mexem no PvP) e voltar ao público
--   LISTAS:   liberados (entram quando quiserem), mods e banidos do seu servidor, por nome
--   ENTRAR:   servidores VIP que liberaram você
-- Convite recebido: aviso embaixo com ACEITAR / RECUSAR.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local UI = require(ReplicatedStorage:WaitForChild("UITheme"))
local Remotes = require(ReplicatedStorage:WaitForChild("Remotes"))

local player = Players.LocalPlayer
local C = UI.Colors
local TOUCH = UI.isTouch() -- celular: botões maiores e o painel com a altura da tela (UITheme.fitTouchPanel)
local ROW_H, ROW_BUTTON_H, ACTION_H = if TOUCH then 44 else 34, if TOUCH then 36 else 26, if TOUCH then 42 else 34

local gui = UI.screen("VIPPanel", 61, player:WaitForChild("PlayerGui"))
local toggle = UI.new("BindableEvent", { Name = "Toggle", Parent = gui })
local shade = UI.new("TextButton", {
	Name = "Shade", Parent = gui, Size = UDim2.fromScale(1, 1), BackgroundColor3 = C.Black,
	BackgroundTransparency = 0.35, Text = "", Visible = false, AutoButtonColor = false,
})
local panel = UI.panel({
	Name = "Panel", Parent = gui, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromOffset(580, 540), Visible = false,
})
if not TOUCH then
	UI.autoScale(panel, 640, 600)
end
UI.label({ Parent = panel, Position = UDim2.fromOffset(20, 12), Size = UDim2.fromOffset(400, 34), Text = "VIP SERVER",
	Font = UI.Fonts.Display, TextSize = 25 })
local close = UI.button({ Parent = panel, Position = UDim2.new(1, if TOUCH then -56 else -50, 0, 12),
	Size = if TOUCH then UDim2.fromOffset(42, 36) else UDim2.fromOffset(32, 30), Text = "X" })
local subtitle = UI.label({ Parent = panel, Position = UDim2.fromOffset(20, 48), Size = UDim2.new(1, -40, 0, 22), TextSize = 13,
	TextColor3 = C.TextDim })

-- Abas
local TABS = { "SERVER", "LISTS", "JOIN" }
local tabButtons = {}
local currentTab = "SERVER"
for index, name in TABS do
	tabButtons[name] = UI.button({ Parent = panel, Position = UDim2.fromOffset(20 + (index - 1) * 140, 76),
		Size = UDim2.fromOffset(130, if TOUCH then 38 else 30), Text = name, TextSize = 13 }, C.PanelLight)
end

-- Barra de cima da aba (botões de ação) e a lista rolando embaixo
local actions = UI.new("Frame", { Parent = panel, Position = UDim2.fromOffset(20, if TOUCH then 122 else 114),
	Size = UDim2.new(1, -40, 0, ACTION_H + 2),
	BackgroundTransparency = 1 })
UI.list(actions, 8, Enum.FillDirection.Horizontal)
local scrollTop = if TOUCH then 172 else 158
local scroll = UI.new("ScrollingFrame", { Parent = panel, Position = UDim2.fromOffset(20, scrollTop), Size = UDim2.new(1, -40, 1, -scrollTop - 18),
	BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 5, AutomaticCanvasSize = Enum.AutomaticSize.Y,
	CanvasSize = UDim2.new() })
UI.list(scroll, 6)

UI.fitTouchPanel(panel, 640, 540, scroll)

-- Aviso de convite
local invite = UI.panel({ Name = "Invite", Parent = gui, AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -150),
	Size = UDim2.fromOffset(420, 92), Visible = false })
local inviteText = UI.label({ Parent = invite, Position = UDim2.fromOffset(14, 8), Size = UDim2.new(1, -28, 0, 36), TextSize = 15,
	TextWrapped = true })
local accept = UI.button({ Parent = invite, Position = UDim2.fromOffset(14, 50), Size = UDim2.fromOffset(190, 32), Text = "ACCEPT",
	TextSize = 13 })
local decline = UI.button({ Parent = invite, Position = UDim2.fromOffset(216, 50), Size = UDim2.fromOffset(190, 32), Text = "DECLINE",
	TextSize = 13 }, C.PanelLight)

local state = { Players = {}, Allowed = {} }
local inviteSeen = nil

local function send(action, value)
	Remotes.VIPPanel:FireServer(action, value)
end

local function clear(container)
	for _, child in container:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
end

local function actionButton(text, width, callback, color)
	local button = UI.button({ Parent = actions, Size = UDim2.fromOffset(width, ACTION_H), Text = text, TextSize = 12 }, color)
	button.Activated:Connect(callback)
	return button
end

local function note(text, order)
	return UI.label({ Parent = scroll, LayoutOrder = order, Size = UDim2.new(1, -10, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
		Text = text, TextSize = 13, TextColor3 = C.TextDim, TextWrapped = true })
end

local function header(text, order)
	return UI.label({ Parent = scroll, LayoutOrder = order, Size = UDim2.new(1, -10, 0, 24), Text = text, TextSize = 15,
		Font = UI.Fonts.Title })
end

-- Linha: nome à esquerda e botões à direita ({ Texto, ação, cor? })
local function row(order, text, buttons)
	local frame = UI.new("Frame", { Parent = scroll, LayoutOrder = order, Size = UDim2.new(1, -10, 0, ROW_H),
		BackgroundColor3 = C.Black, BackgroundTransparency = 0.6, BorderSizePixel = 0 })
	UI.corner(frame, UDim.new(0, 4))
	UI.label({ Parent = frame, Position = UDim2.fromOffset(10, 0), Size = UDim2.new(1, -20, 1, 0), Text = text, TextSize = 14,
		TextTruncate = Enum.TextTruncate.AtEnd })
	local x = -6
	for index = #buttons, 1, -1 do
		local entry = buttons[index]
		local width = math.max(70, #entry[1] * 9)
		x -= width
		local button = UI.button({ Parent = frame, AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(1, x, 0.5, 0),
			Size = UDim2.fromOffset(width, ROW_BUTTON_H), Text = entry[1], TextSize = if TOUCH then 12 else 11 }, entry[3])
		button.Activated:Connect(entry[2])
		x -= 6
	end
	return frame
end

local ROLE_NAMES = { Owner = "owner", Mod = "mod" }

local function renderServer()
	if state.Reserved then
		local role = state.Role
		if role then
			actionButton(if state.PvP then "PVP: ON" else "PVP: OFF", 170, function()
				send("PvP", not state.PvP)
			end, if state.PvP then C.Accent else C.PanelLight)
		end
		actionButton("BACK TO PUBLIC", 190, function() send("Leave") end, C.PanelLight)
		header("Players here", 1)
		if #state.Players == 0 then
			note("Only you are here. Invite people from the panel on a public server or allow friends on the LISTS tab.", 2)
		end
		for index, other in state.Players do
			local buttons = {}
			local canKick = role == "Owner" or (role == "Mod" and other.Role == nil)
			if other.Role ~= "Owner" and canKick then
				table.insert(buttons, { "KICK", function() send("Kick", other.UserId) end, C.PanelLight })
			end
			if role == "Owner" then
				if other.Role == "Mod" then
					table.insert(buttons, { "REMOVE MOD", function() send("ModRemove", other.UserId) end, C.PanelLight })
				else
					table.insert(buttons, { "GIVE MOD", function() send("ModAdd", other.UserId) end })
				end
				table.insert(buttons, { "BAN", function() send("Ban", other.UserId) end })
			end
			local label = other.Name .. (if other.Role then `  ({ROLE_NAMES[other.Role]})` else "")
			row(index + 1, label, buttons)
		end
		return
	end

	-- Servidor público
	if not state.IsVIP then
		note("With the VIP pass you get a server of your own: bring friends, choose who gets in, turn PvP on or off and "
			.. "have mods. Without the pass, you can still join the server of anyone who allowed you (JOIN tab) or invited you.", 1)
		return
	end
	actionButton("GO TO MY SERVER", 210, function() send("Go") end)
	header("Invite people here", 1)
	note("Invites last 2 minutes. ALLOW lets the person join whenever they want (from their JOIN tab).", 2)
	for index, other in state.Players do
		row(index + 2, other.Name, {
			{ "INVITE", function() send("Invite", other.UserId) end },
			{ "ALLOW", function() send("WhitelistAdd", other.UserId) end, C.PanelLight },
		})
	end
end

local nameBox
local function renderLists()
	if not state.IsVIP then
		note("The lists belong to the VIP pass owner.", 1)
		return
	end
	nameBox = UI.new("TextBox", { Parent = actions, Size = UDim2.fromOffset(220, ACTION_H), BackgroundColor3 = C.Black,
		BackgroundTransparency = 0.4, BorderSizePixel = 0, Font = UI.Fonts.Body, TextSize = 14, TextColor3 = C.Text,
		PlaceholderText = "player name", ClearTextOnFocus = false, Text = "" })
	UI.corner(nameBox, UDim.new(0, 4))
	actionButton("ALLOW", 100, function()
		if nameBox.Text ~= "" then send("WhitelistAdd", nameBox.Text) end
	end)
	actionButton("MOD", 80, function()
		if nameBox.Text ~= "" then send("ModAdd", nameBox.Text) end
	end, C.PanelLight)

	local order = 1
	local function section(title, list, buttonText, action, empty)
		header(title, order)
		order += 1
		if #list == 0 then
			note(empty, order)
			order += 1
		end
		for _, entry in list do
			row(order, entry.Name, { { buttonText, function() send(action, entry.UserId) end, C.PanelLight } })
			order += 1
		end
	end
	section("Allowed", state.Whitelist or {}, "REMOVE", "WhitelistRemove", "Nobody yet. Allowed players can join whenever they want.")
	section("Mods", state.Mods or {}, "REMOVE", "ModRemove", "No mods. Mods can kick and toggle PvP.")
	section("Banned", state.Banned or {}, "UNBAN", "Unban", "Nobody banned.")
end

local function renderJoin()
	if #(state.Allowed or {}) == 0 then
		note("No VIP server has allowed you yet. Ask a friend with VIP to allow or invite you.", 1)
		return
	end
	header("Servers that allowed you", 1)
	for index, entry in state.Allowed do
		row(index + 1, `{entry.Name}'s server`, { { "JOIN", function() send("Join", entry.UserId) end } })
	end
end

local function render()
	clear(actions) -- só os GuiObjects: o UIListLayout fica
	clear(scroll)
	for name, button in tabButtons do
		button.BackgroundColor3 = if name == currentTab then C.Accent else C.PanelLight
	end
	if state.Reserved then
		local role = if state.Role then ` · you are {ROLE_NAMES[state.Role]}` else ""
		subtitle.Text = `You are on {state.OwnerName or "?"}'s VIP server{role}`
	else
		subtitle.Text = if state.IsVIP then "Public server · you have the VIP pass" else "Public server"
	end
	if currentTab == "SERVER" then
		renderServer()
	elseif currentTab == "LISTS" then
		renderLists()
	else
		renderJoin()
	end
end

local function renderInvite()
	local data = state.Invite
	if data and inviteSeen ~= data.OwnerId then
		inviteText.Text = `{data.OwnerName} invited you to their VIP server.`
		invite.Visible = true
	elseif not data then
		invite.Visible = false
	end
end

local function show(visible)
	panel.Visible = visible
	shade.Visible = visible
	if visible then
		send("State")
		render()
	end
end

for name, button in tabButtons do
	button.Activated:Connect(function()
		currentTab = name
		render()
	end)
end
toggle.Event:Connect(function() show(not panel.Visible) end)
close.Activated:Connect(function() show(false) end)
shade.Activated:Connect(function() show(false) end)
accept.Activated:Connect(function()
	if state.Invite then
		send("Accept", state.Invite.OwnerId)
		inviteSeen = state.Invite.OwnerId
	end
	invite.Visible = false
end)
decline.Activated:Connect(function()
	if state.Invite then
		inviteSeen = state.Invite.OwnerId
	end
	send("Decline")
	invite.Visible = false
end)

Remotes.VIPPanelState.OnClientEvent:Connect(function(data)
	if type(data) ~= "table" then return end
	-- Convite novo do mesmo dono: mostra de novo
	if data.Invite and (not state.Invite or state.Invite.OwnerId ~= (data.Invite and data.Invite.OwnerId)) then
		inviteSeen = nil
	end
	state = data
	state.Players = state.Players or {}
	-- Não refaz a lista enquanto se digita um nome (perderia o texto)
	if panel.Visible and not (nameBox and nameBox.Parent and nameBox:IsFocused()) then
		render()
	end
	renderInvite()
end)

UserInputService.InputBegan:Connect(function(input, processed)
	if not processed and input.KeyCode == Enum.KeyCode.Escape and panel.Visible then
		show(false)
	end
end)
