local Players=game:GetService("Players")
local RS=game:GetService("ReplicatedStorage")
local TweenService=game:GetService("TweenService")
local player=Players.LocalPlayer
local Remotes=require(RS.Remotes)
local UI=require(RS.UITheme)
local gui=UI.screen("RegionalActivities",45,player:WaitForChild("PlayerGui"))
local panel=UI.panel({Parent=gui,AnchorPoint=Vector2.new(.5,0),Position=UDim2.fromScale(.5,.09),Size=UDim2.fromOffset(390,116),Visible=false})
local scale=UI.new("UIScale",{Parent=panel})
local title=UI.label({Parent=panel,Position=UDim2.fromOffset(12,8),Size=UDim2.new(1,-24,0,24),TextSize=17,Font=UI.Fonts.Title,TextColor3=UI.Colors.Gold})
local text=UI.label({Parent=panel,Position=UDim2.fromOffset(12,35),Size=UDim2.new(1,-24,0,70),TextWrapped=true,TextSize=13})
local snapshot
Remotes.WorldActivityState.OnClientEvent:Connect(function(data)
 if data.Action=="Collected" then
  local world=workspace:FindFirstChild("WorldActivities"); local nodes=world and world:FindFirstChild("ActivityNodes")
  local node=nodes and nodes:FindFirstChild(data.Node)
  if node then
   local h=Instance.new("Highlight"); h.Adornee=node; h.FillColor=UI.Colors.Gold; h.Parent=node
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
   text.Text=string.format("%s  •  %d/%d  •  %d:%02d\n%s\n%s",snapshot.Region,snapshot.Progress,snapshot.Goal,math.floor(seconds/60),seconds%60,snapshot.Description,
    if snapshot.Carrying then "Carregando provisões: leve ao ponto de entrega." else string.format("Sua contribuição: %d  •  faça 2 ações para receber",snapshot.Contribution))
   local camera=workspace.CurrentCamera; if camera then scale.Scale=math.min(1,(camera.ViewportSize.X-24)/390) end
  end
  task.wait(.5)
 end
end)
task.delay(3,function() Remotes.WorldActivityState:FireServer() end)
