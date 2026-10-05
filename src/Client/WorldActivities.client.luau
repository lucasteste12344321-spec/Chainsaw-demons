local Players=game:GetService("Players")
local RS=game:GetService("ReplicatedStorage")
local TweenService=game:GetService("TweenService")
local player=Players.LocalPlayer
local Remotes=require(RS.Remotes)
local UI=require(RS.UITheme)
local gui=UI.screen("RegionalActivities",45,player:WaitForChild("PlayerGui"))
-- Cartão compacto embaixo da bússola (2026-10-05, pedido do usuário: o painel ocupava o meio da tela)
local WIDTH=300
local panel=UI.new("Frame",{Parent=gui,AnchorPoint=Vector2.new(.5,0),Position=UDim2.new(.5,0,0,58),Size=UDim2.fromOffset(WIDTH,0),
 AutomaticSize=Enum.AutomaticSize.Y,BackgroundColor3=UI.Colors.Black,BackgroundTransparency=.4,BorderSizePixel=0,Visible=false})
UI.corner(panel,UDim.new(0,10)); UI.padding(panel,7,12,8,12); UI.list(panel,2)
local scale=UI.new("UIScale",{Parent=panel})
local title=UI.label({Parent=panel,Size=UDim2.new(1,0,0,18),TextSize=14,Font=Enum.Font.BuilderSansExtraBold,TextColor3=UI.Colors.Gold,
 TextTruncate=Enum.TextTruncate.AtEnd,LayoutOrder=1})
local text=UI.label({Parent=panel,Size=UDim2.new(1,0,0,0),AutomaticSize=Enum.AutomaticSize.Y,TextWrapped=true,TextSize=12,
 Font=Enum.Font.BuilderSansMedium,TextColor3=UI.Colors.TextDim,RichText=true,LayoutOrder=2})
local snapshot
Remotes.WorldActivityState.OnClientEvent:Connect(function(data)
 if data.Action=="Collected" then
  local world=workspace:FindFirstChild("WorldActivities"); local nodes=world and world:FindFirstChild("ActivityNodes")
  local node=nodes and nodes:FindFirstChild(data.Node)
  if node then
   local h=Instance.new("Highlight"); h.Adornee=node:FindFirstChild("ItemVisual") or node; h.FillColor=UI.Colors.Gold; h.Parent=node
   TweenService:Create(h,TweenInfo.new(.8),{FillTransparency=1,OutlineTransparency=1}):Play()
   game:GetService("Debris"):AddItem(h,1)
  end
  return
 end
 snapshot=data
end)
task.spawn(function()
 while gui.Parent do
  local root=player.Character and player.Character:FindFirstChild("HumanoidRootPart")
  local near=snapshot and root and typeof(snapshot.Position)=="Vector3" and (root.Position-snapshot.Position).Magnitude<850
  panel.Visible=near==true and not player:GetAttribute("MenuOpen") and snapshot.Status=="Active"
  if panel.Visible then
   title.Text=snapshot.Name
   local seconds=math.max(0,snapshot.EndsAt-os.time())
   -- Uma linha de status em destaque e a explicação menor
   text.Text=string.format('<font color="#%s"><b>%s  •  %d/%d  •  %d:%02d</b></font>\n%s\n%s',UI.Colors.Text:ToHex(),UI.escape(snapshot.Region),snapshot.Progress,snapshot.Goal,
    math.floor(seconds/60),seconds%60,UI.escape(snapshot.Description),
    if snapshot.Carrying then "Carregando provisões: leve ao ponto de entrega." else string.format("Sua contribuição: %d  •  faça 2 ações para receber",snapshot.Contribution))
   local camera=workspace.CurrentCamera; if camera then scale.Scale=math.min(1,(camera.ViewportSize.X-24)/WIDTH) end
  end
  task.wait(.5)
 end
end)
task.delay(3,function() Remotes.WorldActivityState:FireServer() end)
