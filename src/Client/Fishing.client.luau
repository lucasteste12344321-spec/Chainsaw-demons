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
local panel = UI.panel({Name="FishingPanel", Parent=gui, AnchorPoint=Vector2.new(.5,1), Position=UDim2.fromScale(.5,.96), Size=UDim2.fromOffset(430,330), Visible=false})
local scale = UI.new("UIScale", {Parent=panel})
local title = UI.label({Parent=panel,Position=UDim2.fromOffset(18,12),Size=UDim2.new(1,-76,0,32),Text="RIO KURO",Font=UI.Fonts.Display,TextSize=24})
local close = UI.button({Parent=panel,Position=UDim2.new(1,-48,0,12),Size=UDim2.fromOffset(32,30),Text="X"})
local hint = UI.label({Parent=panel,Position=UDim2.fromOffset(18,50),Size=UDim2.new(1,-36,0,57),TextWrapped=true,TextSize=15})
local body = UI.new("Frame",{Parent=panel,Position=UDim2.fromOffset(18,110),Size=UDim2.new(1,-36,0,145),BackgroundTransparency=1})
local actionButton = UI.button({Parent=panel,Position=UDim2.new(0,18,1,-62),Size=UDim2.new(1,-36,0,44),Text="LANÇAR"}, C.Blue)
local basketButton = UI.button({Name="FishingBasket",Parent=gui,AnchorPoint=Vector2.new(1,1),Position=UDim2.new(1,-16,1,-180),Size=UDim2.fromOffset(100,32),Text="PESCARIA",TextSize=12}, C.PanelLight)
local phase, sessionId, spotId, cached, charging, holding, chargeStart = "Closed", nil, nil, nil, false, false, 0
local progressFill, tensionFill, tensionText, chargeFill
local pointer
local function send(kind,id,value) Remotes.FishingAction:FireServer(kind,id,value) end
local function label(parent,y,text,size,color)
 return UI.label({Parent=parent,Position=UDim2.fromOffset(0,y),Size=UDim2.new(1,0,0,25),Text=text,TextSize=size or 14,TextColor3=color or C.Text})
end
local function bar(y,color)
 local bg=UI.new("Frame",{Parent=body,Position=UDim2.fromOffset(0,y),Size=UDim2.new(1,0,0,16),BackgroundColor3=C.PanelLight,BorderSizePixel=0})
 UI.corner(bg,UDim.new(0,3))
 local fill=UI.new("Frame",{Parent=bg,Size=UDim2.fromScale(0,1),BackgroundColor3=color,BorderSizePixel=0})
 UI.corner(fill,UDim.new(0,3)); return fill
end
local function release()
 if holding then holding=false; if sessionId then send("Reel",sessionId,false) end end
 if charging then
  charging=false
  if phase=="Ready" then send("Start",spotId,math.clamp((os.clock()-chargeStart)/1.1,0,1)); actionButton.Text="LANÇANDO..." end
 end
 pointer=nil
end
local function hide()
 charging=false; release(); send("Cancel")
 phase="Closed"; panel.Visible=false; CAS:UnbindAction("KuroFishingInput")
end
local function press()
 if player:GetAttribute("MenuOpen") then return end
 if phase=="Ready" then charging=true; chargeStart=os.clock(); actionButton.Text="SOLTE PARA LANÇAR"
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
 panel.Size=UDim2.fromOffset(480,530); title.Text="CESTA DE PESCA"
 hint.Text=string.format("%s  •  %d capturas  •  cesta %d/%d\nVenda na banca de Daichi. Cozinhe com Nori no abrigo.",Data.Rods[d.RodTier].Name,d.Catches,Data.BagCount(d),Data.BagLimit)
 body.Size=UDim2.new(1,-36,0,343)
 for i,id in Data.Order do
  local fish=Data.Fish[id]
  label(body,(i-1)*32,string.format("%s  ×%d  |  %s  |  %.2f kg",fish.Name,d.Counts[id] or 0,fish.Rarity,d.Records[id] or 0),13,fish.Color)
 end
 local function button(y,text,callback,enabled)
  local b=UI.button({Parent=body,Position=UDim2.fromOffset(0,y),Size=UDim2.new(1,0,0,34),Text=text,TextSize=13},if enabled then C.PanelLight else C.Background)
  b.Active=enabled; b.AutoButtonColor=enabled; b.TextTransparency=if enabled then 0 else .5
  b.Activated:Connect(function() if enabled then callback() end end)
 end
 if not d.HasRod then button(198,"PEGAR VARA GRATUITA COM DAICHI",function() send("ClaimRod") end,data.CanTrade)
 else
  local nextRod=Data.Rods[d.RodTier+1]
  button(198,if nextRod then string.format("MELHORAR VARA  •  %d Gold / %d capturas",nextRod.Price,nextRod.Catches) else "VARA NO NÍVEL MÁXIMO",function() send("Upgrade") end,data.CanTrade and nextRod~=nil)
 end
 button(238,string.format("COZINHAR SOPA  •  2 carpas + 1 truta  |  sopas: %d/20",d.Meals or 0),function() send("Cook") end,data.CanCook)
 button(278,"TOMAR SOPA  •  recupera 25% de vida fora de combate",function() send("Eat") end,(d.Meals or 0)>0)
 label(body,314,"Enguia: à noite. Cardumes e varas melhores favorecem raros.",12,C.TextDim)
 actionButton.Text=string.format("VENDER TODOS  •  %d Gold",data.Value or Data.SaleValue(d))
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
   tensionText.Text=if data.Tension>.8 then "SOLTE — tensão alta!" elseif data.Tension<.15 then "RECOLHA — linha frouxa!" else "Alterne entre recolher e aliviar"
  end
  return
 end
 charging=false; release(); phase=data.Phase; sessionId=data.Id or sessionId; spotId=data.SpotId or spotId
 if data.Data then cached=data.Data end
 body:ClearAllChildren(); progressFill=nil; tensionFill=nil; chargeFill=nil
 panel.Visible=true; panel.Size=UDim2.fromOffset(430,330); body.Size=UDim2.new(1,-36,0,145)
 actionButton.Active=true; actionButton.TextTransparency=0; title.Text="RIO KURO"; bind()
 if phase=="Menu" then menu(data)
 elseif phase=="Ready" then
  hint.Text=if data.Hotspot then "Cardume ativo! Maior chance de peixes incomuns e raros." else "Segure ESPAÇO, RT ou o botão abaixo e solte para lançar."
  label(body,8,"FORÇA DO LANÇAMENTO",13,C.TextDim); chargeFill=bar(40,C.Blue)
  label(body,78,"E no píer: pescar  •  caminhar: cancelar",13,C.TextDim)
  actionButton.Text="SEGURE PARA LANÇAR"
 elseif phase=="Casting" or phase=="Waiting" then
  hint.Text=if phase=="Casting" then "A linha está indo para a água..." else "Observe a boia. Fisgue assim que ela afundar!"
  label(body,44,"A correnteza esconde mais do que parece.",14,C.TextDim); actionButton.Text="AGUARDANDO..."
 elseif phase=="Bite" then
  hint.Text="MORDEU! Aperte ESPAÇO, RT ou o botão para fisgar."
  label(body,24,"FISGUE AGORA!",28,C.Gold); actionButton.Text="FISGAR!"
 elseif phase=="Reeling" then
  hint.Text="Segure para recolher. Solte para aliviar. Mantenha a tensão longe das duas extremidades."
  label(body,0,"CAPTURA",12,C.TextDim); progressFill=bar(28,C.Blue)
  tensionText=label(body,58,"Alterne entre recolher e aliviar",13,C.Gold); tensionFill=bar(92,C.Green)
  progressFill.Size=UDim2.fromScale(data.Progress or .12,1); tensionFill.Size=UDim2.fromScale(data.Tension or .4,1)
  actionButton.Text="SEGURE PARA RECOLHER"
 elseif phase=="Caught" then
  local fish=Data.Fish[data.Fish]; title.Text="BOA CAPTURA!"
  hint.Text=fish.Name.."  •  "..fish.Rarity
  label(body,14,string.format("%.2f kg",data.Kg),32,fish.Color)
  label(body,64,string.format("Cesta %d/%d  •  +10 XP",Data.BagCount(data.Data),Data.BagLimit),15,C.TextDim)
  label(body,96,"Peixe guardado. Venda ou cozinhe quando quiser.",13,C.TextDim)
  actionButton.Text="PESCAR NOVAMENTE"
 elseif phase=="Ended" then hint.Text=data.Reason; actionButton.Text="TENTAR NOVAMENTE"
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
basketButton.Activated:Connect(function() if not player:GetAttribute("MenuOpen") then send("Bag") end end)
UIS.WindowFocusReleased:Connect(function() charging=false; release() end)
player.CharacterAdded:Connect(hide)
player:GetAttributeChangedSignal("MenuOpen"):Connect(function() basketButton.Visible=not player:GetAttribute("MenuOpen"); if player:GetAttribute("MenuOpen") then hide() end end)
RunService.RenderStepped:Connect(function()
 if not panel.Visible then return end
 local camera=workspace.CurrentCamera
 if camera then scale.Scale=math.min(1,(camera.ViewportSize.X-24)/panel.Size.X.Offset,(camera.ViewportSize.Y-50)/panel.Size.Y.Offset) end
 if charging and chargeFill then chargeFill.Size=UDim2.fromScale(math.clamp((os.clock()-chargeStart)/1.1,0,1),1) end
end)
