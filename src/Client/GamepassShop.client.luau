local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local Marketplace = game:GetService("MarketplaceService")
local UserInput = game:GetService("UserInputService")
local UI = require(RS.UITheme)
local Config = require(RS.GamepassConfig)
local Odds = require(RS.GamepassOdds)
local Remotes = require(RS.Remotes)
local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local C = UI.Colors
local gui = UI.screen("GamepassShop", 60, playerGui)
-- Sem botão próprio na tela (2026-10-05): abre pelo botão ★ do grupo de menus da HUD (HUB_GUI) e pelo PASSES do menu
-- principal (MainMenu), que disparam este BindableEvent
local open = UI.new("BindableEvent", {Name = "Toggle", Parent = gui})
local shade = UI.new("TextButton", {Name = "Shade", Parent = gui, Size = UDim2.fromScale(1,1), BackgroundColor3 = C.Black, BackgroundTransparency = .35, Text = "", Visible = false, AutoButtonColor = false})
local panel = UI.panel({Name = "Shop", Parent = gui, AnchorPoint = Vector2.new(.5,.5), Position = UDim2.fromScale(.5,.5), Size = UDim2.fromOffset(580,570), Visible = false})

UI.label({Parent=panel,Position=UDim2.fromOffset(20,12),Size=UDim2.fromOffset(440,34),Text="PASSES & VIP",Font=UI.Fonts.Display,TextSize=25})
local close = UI.button({Name="Close",Parent=panel,Position=UDim2.new(1,-50,0,14),Size=UDim2.fromOffset(32,30),Text="X"})
UI.label({Parent=panel,Position=UDim2.fromOffset(20,49),Size=UDim2.new(1,-40,0,26),Text="Compra única · benefícios permanentes",TextSize=13,TextColor3=C.TextDim})
local cards, info = {}, {}
local EXTRA = (#Config.Order - 3) * 106 -- cada passe a mais empurra os botões de baixo
panel.Size = UDim2.fromOffset(580, 570 + EXTRA)
if not UI.isTouch() then UI.autoScale(panel, 640, 630 + EXTRA) end
local state = {Owned={}, Ready=false, Restricted=true}
local prompting = false
local refresh
for i, key in Config.Order do
	local pass = Config.Passes[key]
	local row = UI.panel({Name=key,Parent=panel,Position=UDim2.fromOffset(20,78+(i-1)*106),Size=UDim2.new(1,-40,0,98)})
	UI.label({Parent=row,Position=UDim2.fromOffset(12,8),Size=UDim2.new(1,-166,0,25),Text=pass.Name,TextSize=20,Font=UI.Fonts.Title,TextColor3=if key=="VIP" then C.Gold else C.Text})
	local description = UI.label({Parent=row,Position=UDim2.fromOffset(12,37),Size=UDim2.new(1,-170,0,52),Text=pass.Description,TextSize=12,TextWrapped=true,TextYAlignment=Enum.TextYAlignment.Top})
	local button = UI.button({Name="Buy",Parent=row,Position=UDim2.new(1,-149,0,29),Size=UDim2.fromOffset(136,38),Text="EM BREVE",TextSize=12})
	cards[key] = {Button=button, Description=description}
	button.Activated:Connect(function()
		if prompting or pass.Id <= 0 or state.Owned[key] or not state.Ready or (info[key] and info[key].IsForSale == false) then return end
		prompting = true; refresh()
		local ok = pcall(Marketplace.PromptGamePassPurchase, Marketplace, player, pass.Id)
		if not ok then prompting = false; refresh() end
	end)
	if pass.Id > 0 then task.spawn(function()
		-- GetProductInfoAsync não existe nos apps antigos de celular: aí vale o GetProductInfo (o nome antigo)
		local ok, product = pcall(function()
			return Marketplace:GetProductInfoAsync(pass.Id, Enum.InfoType.GamePass)
		end)
		if not ok then
			ok, product = pcall(function()
				return Marketplace:GetProductInfo(pass.Id, Enum.InfoType.GamePass)
			end)
		end
		if ok then info[key] = product end
		if refresh then refresh() end
	end) end
end
local daily = UI.button({Name="DailyVIP",Parent=panel,Position=UDim2.fromOffset(20,405+EXTRA),Size=UDim2.fromOffset(260,34),Text="5 GIROS DIÁRIOS",TextSize=12})
local server = UI.button({Name="VIPServer",Parent=panel,Position=UDim2.fromOffset(300,405+EXTRA),Size=UDim2.fromOffset(260,34),Text="MEU SERVIDOR VIP",TextSize=12})
local status = UI.label({Name="DailyStatus",Parent=panel,Position=UDim2.fromOffset(20,446+EXTRA),Size=UDim2.new(1,-40,0,30),TextSize=12,TextColor3=C.TextDim,TextWrapped=true})
local details = UI.button({Name="Details",Parent=panel,Position=UDim2.fromOffset(20,486+EXTRA),Size=UDim2.fromOffset(340,34),Text="CHANCES E REGRAS DOS BENEFÍCIOS",TextSize=12},C.PanelLight)
local recheck = UI.button({Name="Refresh",Parent=panel,Position=UDim2.fromOffset(376,486+EXTRA),Size=UDim2.fromOffset(184,34),Text="ATUALIZAR PASSES",TextSize=11},C.PanelLight)
UI.label({Parent=panel,Position=UDim2.fromOffset(20,529+EXTRA),Size=UDim2.new(1,-40,0,24),Text="O preço final aparece na confirmação oficial do Roblox.",TextSize=11,TextColor3=C.TextDim})
local oddsPanel = UI.panel({Name="Odds",Parent=gui,AnchorPoint=Vector2.new(.5,.5),Position=UDim2.fromScale(.5,.5),Size=UDim2.fromOffset(580,570),Visible=false})
if not UI.isTouch() then UI.autoScale(oddsPanel,640,630) end
local back = UI.button({Parent=oddsPanel,Position=UDim2.fromOffset(16,12),Size=UDim2.fromOffset(130,32),Text="VOLTAR",TextSize=12})
local scroll = UI.new("ScrollingFrame",{Parent=oddsPanel,Position=UDim2.fromOffset(16,54),Size=UDim2.new(1,-32,1,-70),BackgroundTransparency=1,BorderSizePixel=0,ScrollBarThickness=5,AutomaticCanvasSize=Enum.AutomaticSize.Y,CanvasSize=UDim2.new()})
local oddsText = UI.label({Parent=scroll,Size=UDim2.new(1,-14,0,0),AutomaticSize=Enum.AutomaticSize.Y,TextWrapped=true,TextYAlignment=Enum.TextYAlignment.Top,TextSize=13})
-- Celular: o painel fica com a altura da tela e o conteúdo rola (botões no tamanho normal, sem encolher)
UI.fitTouchPanel(panel, 640, 570 + EXTRA)
UI.fitTouchPanel(oddsPanel, 640, 570, scroll)
refresh = function()
	for _, key in Config.Order do
		local pass, card, product = Config.Passes[key], cards[key], info[key]
		card.Button.Text = if state.Owned[key] then "ADQUIRIDO" elseif pass.Id <= 0 then "EM BREVE" elseif not state.Ready then "VERIFICANDO..." elseif prompting then "AGUARDE..." elseif product and product.IsForSale == false then "INDISPONÍVEL" elseif product and product.PriceInRobux then `{product.PriceInRobux} ROBUX` else "VER PREÇO"
		card.Button.Active = pass.Id > 0 and not state.Owned[key] and state.Ready and not prompting and not (product and product.IsForSale == false)
		card.Button.BackgroundColor3 = if card.Button.Active then C.Accent else C.PanelLight
	end
	cards.VIP.Description.Text = if state.Restricted then "Servidor reservado e 5 créditos de clã por dia para escolha garantida. Bônus de sorte indisponível para esta conta." else Config.Passes.VIP.Description
	daily.Text = if state.DailyClaimed then "RECEBIDO HOJE" elseif state.Restricted then "5 CRÉDITOS DIÁRIOS" else "5 GIROS DIÁRIOS"
	daily.Active = state.Owned.VIP == true and not state.DailyClaimed
	daily.BackgroundColor3 = if daily.Active then C.Accent else C.PanelLight
	-- Abre o painel do servidor VIP (VIPPanel.client): ir/voltar, convites, listas e controles do dono
	server.Text = "SERVIDOR VIP"
	server.Active = true
	server.BackgroundColor3 = C.Accent
	status.Text = if state.Owned.VIP then "Giros renovam à meia-noite de Brasília. Dias ausentes não acumulam." else "Adquira VIP para liberar o servidor e o benefício diário."
end
local function show(visible)
	panel.Visible=visible;shade.Visible=visible;oddsPanel.Visible=false
	if visible then Remotes.GamepassAction:FireServer("State");refresh() end
end
open.Event:Connect(function() show(not shade.Visible) end)
close.Activated:Connect(function() show(false) end)
shade.Activated:Connect(function() show(false) end)
back.Activated:Connect(function() oddsPanel.Visible=false;panel.Visible=true end)
details.Activated:Connect(function() oddsText.Text=Odds.Text(state.Restricted,state.Owned.VIP);panel.Visible=false;oddsPanel.Visible=true end)
daily.Activated:Connect(function() if daily.Active then Remotes.GamepassAction:FireServer("Daily") end end)
server.Activated:Connect(function()
	local vipGui = playerGui:FindFirstChild("VIPPanel")
	local vipToggle = vipGui and vipGui:FindFirstChild("Toggle")
	if vipToggle then
		show(false)
		vipToggle:Fire()
	elseif server.Active then
		Remotes.GamepassAction:FireServer(if state.Reserved then "PublicServer" else "VIPServer")
	end
end)
recheck.Activated:Connect(function() Remotes.GamepassAction:FireServer("Refresh") end)
Remotes.GamepassState.OnClientEvent:Connect(function(data) if type(data)=="table" and type(data.Owned)=="table" then state=data;refresh();if oddsPanel.Visible then oddsText.Text=Odds.Text(state.Restricted,state.Owned.VIP) end end end)
Marketplace.PromptGamePassPurchaseFinished:Connect(function() prompting=false;refresh() end) -- UI only; the server grants ownership.
UserInput.InputBegan:Connect(function(input, processed) if not processed and input.KeyCode==Enum.KeyCode.Escape then show(false) end end)
refresh()
Remotes.GamepassAction:FireServer("State")
