-- Client presents server snapshots; fish rolls, tension and rewards stay on the server.
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local CAS = game:GetService("ContextActionService")
local UIS = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local player = Players.LocalPlayer
local Remotes = require(RS.Remotes)
local Data = require(RS.FishingData)
local UI = require(RS.UITheme)
local C = UI.Colors
local gui = UI.screen("Fishing", 65, player:WaitForChild("PlayerGui"))
-- Painel compacto (2026-10-05, pedido do usuário: ocupava o meio da tela). Pescando, fica pequeno em cima da linha de
-- habilidades da HUD; a cesta (menu) abre no centro. A cesta abre pelo botão redondo 釣 do grupo de menus da HUD
-- (HUB_GUI manda FishingAction "Bag"), não tem mais botão próprio na tela.
local ACTIVE_SIZE, MENU_SIZE = Vector2.new(320, 236), Vector2.new(440, 478)
local panel = UI.new("Frame", {Name="FishingPanel", Parent=gui, AnchorPoint=Vector2.new(.5,1), Position=UDim2.new(.5,0,1,-84),
	Size=UDim2.fromOffset(ACTIVE_SIZE.X,ACTIVE_SIZE.Y), BackgroundColor3=C.Panel, BackgroundTransparency=.08, BorderSizePixel=0, Visible=false})
UI.corner(panel, UDim.new(0,12)); UI.stroke(panel, C.White, 1, .86)
local scale = UI.new("UIScale", {Parent=panel})
local title = UI.label({Parent=panel,Position=UDim2.fromOffset(16,10),Size=UDim2.new(1,-60,0,24),Text="KURO RIVER",Font=Enum.Font.BuilderSansExtraBold,TextSize=18})
local close = UI.new("TextButton", {Parent=panel,AnchorPoint=Vector2.new(1,0),Position=UDim2.new(1,-10,0,10),Size=UDim2.fromOffset(26,26),
	BackgroundColor3=C.PanelLight,BackgroundTransparency=.3,AutoButtonColor=false,Font=UI.Fonts.Title,TextSize=16,TextColor3=C.TextDim,Text="×"})
UI.corner(close, UDim.new(.5,0))
local hint = UI.label({Parent=panel,Position=UDim2.fromOffset(16,36),Size=UDim2.new(1,-32,0,34),TextWrapped=true,TextSize=13,TextColor3=C.TextDim,
	Font=Enum.Font.BuilderSansMedium,TextYAlignment=Enum.TextYAlignment.Top})
local body = UI.new("Frame",{Parent=panel,Position=UDim2.fromOffset(16,74),Size=UDim2.new(1,-32,0,112),BackgroundTransparency=1})
local actionButton = UI.button({Parent=panel,Position=UDim2.new(0,16,1,-44),Size=UDim2.new(1,-32,0,32),Text="CAST",TextSize=14,
	Font=Enum.Font.BuilderSansExtraBold}, C.Blue)
-- Pescando: pequeno, embaixo no centro (em cima da HUD); cesta: no centro da tela
local function layout(menuMode)
	local size = if menuMode then MENU_SIZE else ACTIVE_SIZE
	panel.Size = UDim2.fromOffset(size.X, size.Y)
	panel.AnchorPoint = if menuMode then Vector2.new(.5,.5) else Vector2.new(.5,1)
	panel.Position = if menuMode then UDim2.fromScale(.5,.5) else UDim2.new(.5,0,1,-84)
	body.Size = UDim2.new(1,-32,0,if menuMode then 343 else 112)
end
local phase, sessionId, spotId, cached, charging, holding, chargeStart = "Closed", nil, nil, nil, false, false, 0
local progressFill, tensionFill, tensionText, chargeFill
local pointer
local function send(kind,id,value) Remotes.FishingAction:FireServer(kind,id,value) end
local function label(parent,y,text,size,color)
 return UI.label({Parent=parent,Position=UDim2.fromOffset(0,y),Size=UDim2.new(1,0,0,25),Text=text,TextSize=size or 14,TextColor3=color or C.Text})
end
local function bar(y,color)
 local bg=UI.new("Frame",{Parent=body,Position=UDim2.fromOffset(0,y),Size=UDim2.new(1,0,0,10),BackgroundColor3=C.PanelLight,BorderSizePixel=0})
 UI.corner(bg,UDim.new(0,3))
 local fill=UI.new("Frame",{Parent=bg,Size=UDim2.fromScale(0,1),BackgroundColor3=color,BorderSizePixel=0})
 UI.corner(fill,UDim.new(0,3)); return fill
end
local function release()
 if holding then holding=false; if sessionId then send("Reel",sessionId,false) end end
 if charging then
  charging=false
  if phase=="Ready" then send("Start",spotId,math.clamp((os.clock()-chargeStart)/1.1,0,1)); actionButton.Text="CASTING..." end
 end
 pointer=nil
end
local function hide()
 charging=false; release(); send("Cancel")
 phase="Closed"; panel.Visible=false; CAS:UnbindAction("KuroFishingInput")
end
local function press()
 if player:GetAttribute("MenuOpen") then return end
 if phase=="Ready" then charging=true; chargeStart=os.clock(); actionButton.Text="RELEASE TO CAST"
 elseif phase=="Bite" then send("Hook",sessionId)
 elseif phase=="Reeling" and not holding then holding=true; send("Reel",sessionId,true)
 end
end
local function bind()
 CAS:BindActionAtPriority("KuroFishingInput",function(_,state)
  if phase=="Closed" or phase=="Menu" then return Enum.ContextActionResult.Pass end
  if state==Enum.UserInputState.Begin then press() elseif state==Enum.UserInputState.End or state==Enum.UserInputState.Cancel then release() end
  return Enum.ContextActionResult.Sink
 end,false,3000,Enum.KeyCode.Space,Enum.KeyCode.ButtonR2)
end
local function menu(data)
 local d=data.Data; cached=d
 layout(true); title.Text="FISHING BASKET"
 hint.Text=string.format("%s  •  %d catches  •  basket %d/%d\nSell at Daichi's stall. Cook with Nori at the shelter.",Data.Rods[d.RodTier].Name,d.Catches,Data.BagCount(d),Data.BagLimit)
 for i,id in Data.Order do
  local fish=Data.Fish[id]
  label(body,(i-1)*32,string.format("%s  ×%d  |  %s  |  %.2f kg",fish.Name,d.Counts[id] or 0,fish.Rarity,d.Records[id] or 0),13,fish.Color)
 end
 local function button(y,text,callback,enabled)
  local b=UI.button({Parent=body,Position=UDim2.fromOffset(0,y),Size=UDim2.new(1,0,0,32),Text=text,TextSize=12},if enabled then C.PanelLight else C.Background)
  b.Active=enabled; b.AutoButtonColor=enabled; b.TextTransparency=if enabled then 0 else .5
  b.Activated:Connect(function() if enabled then callback() end end)
 end
 if not d.HasRod then button(198,"GET A FREE ROD FROM DAICHI",function() send("ClaimRod") end,data.CanTrade)
 else
  local nextRod=Data.Rods[d.RodTier+1]
  button(198,if nextRod then string.format("UPGRADE ROD  •  %d Gold / %d catches",nextRod.Price,nextRod.Catches) else "ROD AT MAX LEVEL",function() send("Upgrade") end,data.CanTrade and nextRod~=nil)
 end
 button(238,string.format("COOK SOUP  •  2 carp + 1 trout  |  soups: %d/20",d.Meals or 0),function() send("Cook") end,data.CanCook)
 button(278,"EAT SOUP  •  heals 25% health out of combat",function() send("Eat") end,(d.Meals or 0)>0)
 label(body,314,"Eels: at night. Fish schools and better rods favor rare fish.",12,C.TextDim)
 actionButton.Text=string.format("SELL ALL  •  %d Gold",data.Value or Data.SaleValue(d))
 actionButton.Active=data.CanTrade==true; actionButton.TextTransparency=if data.CanTrade then 0 else .5
end
Remotes.FishingState.OnClientEvent:Connect(function(data)
 if type(data)~="table" or not data.Phase then return end
 if player:GetAttribute("MenuOpen") then send("Cancel"); return end
 -- Closing the UI must not reopen it when the cancel acknowledgement arrives.
 if phase=="Closed" and data.Phase=="Ended" then return end
 if data.Phase=="Reeling" and phase=="Reeling" and sessionId==data.Id then
  if progressFill then progressFill.Size=UDim2.fromScale(data.Progress,1); tensionFill.Size=UDim2.fromScale(data.Tension,1)
   tensionFill.BackgroundColor3=if data.Tension>.85 then C.Accent elseif data.Tension<.12 then C.Gold else C.Green
   tensionText.Text=if data.Tension>.8 then "EASE OFF — high tension!" elseif data.Tension<.15 then "REEL IN — slack line!" else "Alternate between reeling and easing off"
  end
  return
 end
 charging=false; release(); phase=data.Phase; sessionId=data.Id or sessionId; spotId=data.SpotId or spotId
 if data.Data then cached=data.Data end
 body:ClearAllChildren(); progressFill=nil; tensionFill=nil; chargeFill=nil
 panel.Visible=true; layout(false)
 actionButton.Active=true; actionButton.TextTransparency=0; title.Text="KURO RIVER"; bind()
 if phase=="Menu" then menu(data)
 elseif phase=="Ready" then
  hint.Text=if data.Hotspot then "Active school! Better chance of uncommon and rare fish." else "Hold SPACE, RT or the button below and release to cast."
  label(body,4,"CAST POWER",13,C.TextDim); chargeFill=bar(32,C.Blue)
  label(body,56,"E at the pier: fish  •  walk away: cancel",13,C.TextDim)
  actionButton.Text="HOLD TO CAST"
 elseif phase=="Casting" or phase=="Waiting" then
  hint.Text=if phase=="Casting" then "The line is heading for the water..." else "Watch the bobber. Hook it as soon as it sinks!"
  label(body,30,"The current hides more than it seems.",13,C.TextDim); actionButton.Text="WAITING..."
 elseif phase=="Bite" then
  hint.Text="BITE! Press SPACE, RT or the button to hook it."
  label(body,24,"HOOK IT NOW!",24,C.Gold); actionButton.Text="HOOK!"
 elseif phase=="Reeling" then
  hint.Text="Hold to reel in. Release to ease off. Keep the tension away from both ends."
  label(body,0,"CATCH",12,C.TextDim); progressFill=bar(26,C.Blue)
  tensionText=label(body,46,"Alternate between reeling and easing off",13,C.Gold); tensionFill=bar(74,C.Green)
  progressFill.Size=UDim2.fromScale(data.Progress or .12,1); tensionFill.Size=UDim2.fromScale(data.Tension or .4,1)
  actionButton.Text="HOLD TO REEL IN"
 elseif phase=="Caught" then
  local fish=Data.Fish[data.Fish]; title.Text="NICE CATCH!"
  hint.Text=fish.Name.."  •  "..fish.Rarity
  label(body,10,string.format("%.2f kg",data.Kg),26,fish.Color)
  label(body,50,string.format("Basket %d/%d  •  +10 XP",Data.BagCount(data.Data),Data.BagLimit),14,C.TextDim)
  label(body,78,"Fish stored. Sell or cook it whenever you want.",13,C.TextDim)
  actionButton.Text="FISH AGAIN"
 elseif phase=="Ended" then hint.Text=data.Reason; actionButton.Text="TRY AGAIN"
 end
end)
actionButton.InputBegan:Connect(function(input)
 if input.UserInputType==Enum.UserInputType.MouseButton1 or input.UserInputType==Enum.UserInputType.Touch then pointer=input; press() end
end)
UIS.InputEnded:Connect(function(input)
 if input==pointer or input.UserInputType==Enum.UserInputType.MouseButton1 then release() end
end)
actionButton.Activated:Connect(function()
 if phase=="Menu" and actionButton.Active then send("Sell")
 elseif phase=="Caught" or phase=="Ended" then send("Reopen",spotId) end
end)
close.Activated:Connect(hide)
UIS.WindowFocusReleased:Connect(function() charging=false; release() end)
player.CharacterAdded:Connect(hide)
player:GetAttributeChangedSignal("MenuOpen"):Connect(function() if player:GetAttribute("MenuOpen") then hide() end end)
RunService.RenderStepped:Connect(function()
 if not panel.Visible then return end
 local camera=workspace.CurrentCamera
 if camera then scale.Scale=math.min(1,(camera.ViewportSize.X-24)/panel.Size.X.Offset,(camera.ViewportSize.Y-50)/panel.Size.Y.Offset) end
 if charging and chargeFill then chargeFill.Size=UDim2.fromScale(math.clamp((os.clock()-chargeStart)/1.1,0,1),1) end
end)
