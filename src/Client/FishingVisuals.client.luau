local Players=game:GetService("Players")
local RS=game:GetService("ReplicatedStorage")
local RunService=game:GetService("RunService")
local TweenService=game:GetService("TweenService")
local Debris=game:GetService("Debris")
local Remotes=require(RS.Remotes)
local Data=require(RS.FishingData)
local WorldPropAssets=require(RS:WaitForChild("WorldPropAssets"))
local active={}
local folder=Instance.new("Folder"); folder.Name="LocalFishingVisuals"; folder.Parent=workspace
local function part(name,size,color)
 local p=Instance.new("Part"); p.Name=name; p.Size=size; p.Color=color; p.Anchored=true
 p.CanCollide=false; p.CanTouch=false; p.CanQuery=false; p.CastShadow=false; p.Material=Enum.Material.SmoothPlastic; p.Parent=folder; return p
end
local function splash(point,color)
 for i=1,2 do
  local ring=part("Ripple",Vector3.new(.04,1,1),color or Color3.fromRGB(196,230,223)); ring.Shape=Enum.PartType.Cylinder
  ring.CFrame=CFrame.new(point+Vector3.new(0,.1+i*.015,0))*CFrame.Angles(0,0,math.pi/2); ring.Transparency=.35
  TweenService:Create(ring,TweenInfo.new(.5+i*.25),{Size=Vector3.new(.025,4+i*2,4+i*2),Transparency=1}):Play(); Debris:AddItem(ring,1.1)
 end
end
local function clear(userId)
 local state=active[userId]; active[userId]=nil
 if state then state.Bobber:Destroy(); state.Line:Destroy(); if state.TipOwned then state.Tip:Destroy() end end
end
Remotes.FishingFX.OnClientEvent:Connect(function(kind,data)
 if kind=="Cast" then
  clear(data.UserId)
  local owner=Players:GetPlayerByUserId(data.UserId); local character=owner and owner.Character
  local held=character and character:FindFirstChildOfClass("Tool"); local handle=held and held:FindFirstChild("Handle")
  if not handle then return end
  local tip=handle:FindFirstChild("Tip"); local owned=false
  if not tip then tip=Instance.new("Attachment"); tip.Name="LocalFishingTip"; tip.Position=Vector3.new(0,2,0); tip.Parent=handle; owned=true end
  local bobber=WorldPropAssets.Clone("FishingBobber")
  if not bobber then if owned then tip:Destroy() end; return end
  bobber.Parent=folder
  local bobberRoot=bobber.PrimaryPart
  local a=Instance.new("Attachment"); a.Parent=bobberRoot
  local line=Instance.new("Beam"); line.Attachment0=tip; line.Attachment1=a; line.Width0=.025; line.Width1=.015
  line.Color=ColorSequence.new(Color3.fromRGB(220,226,206)); line.Transparency=NumberSequence.new(.15); line.Segments=12; line.FaceCamera=true; line.Parent=bobberRoot
  active[data.UserId]={Id=data.Id,Point=data.Point,Started=os.clock(),From=tip.WorldPosition,Bobber=bobber,Line=line,Tip=tip,TipOwned=owned,Phase="Cast",Ripple=0,Character=character}
  bobber:PivotTo(CFrame.new(tip.WorldPosition))
  return
 end
 local state=active[data.UserId]; if not state or state.Id~=data.Id then return end
 if kind=="Bite" or kind=="Hook" then state.Phase=kind; splash(state.Point)
 elseif kind=="Catch" then
  splash(state.Point,Color3.fromRGB(246,225,160))
  local library=RS:FindFirstChild("VFX"); library=library and library:FindFirstChild("WorldActivities")
  local template=library and library:FindFirstChild("FishVisual")
  if not template then clear(data.UserId);return end
  local fish=template:Clone()
  fish.Color=Data.Fish[data.Fish].Color; fish.Anchored=true; fish.CanCollide=false; fish.CanTouch=false; fish.CanQuery=false; fish.Parent=folder
  local from=state.Point; local to=state.Character:GetPivot().Position+Vector3.new(0,2,0); local start=os.clock()
  local connection
  connection=RunService.RenderStepped:Connect(function()
   local t=math.clamp((os.clock()-start)/.85,0,1)
   if not fish.Parent then connection:Disconnect(); return end
   fish.CFrame=CFrame.new(from:Lerp(to,t)+Vector3.new(0,math.sin(t*math.pi)*6,0))*CFrame.Angles(t*5,0,math.sin(t*9)*.4)
   if t>=1 then connection:Disconnect(); fish:Destroy() end
  end)
  Debris:AddItem(fish,2); clear(data.UserId)
 elseif kind=="End" then clear(data.UserId) end
end)
RunService.RenderStepped:Connect(function()
 local now=os.clock()
 for userId,state in active do
  local age=now-state.Started
  if age>48 or not state.Tip:IsDescendantOf(workspace) or not state.Character.Parent then clear(userId); continue end
  if age<.7 then
   local t=age/.7; state.Bobber:PivotTo(CFrame.new(state.From:Lerp(state.Point,t)+Vector3.new(0,math.sin(t*math.pi)*8,0)))
  else
   if state.Phase=="Cast" then state.Phase="Waiting"; splash(state.Point) end
   local bob=math.sin(now*3)*.1
   if state.Phase=="Bite" then bob=-.4+math.sin(now*18)*.13 elseif state.Phase=="Hook" then bob=math.sin(now*13)*.2 end
   state.Bobber:PivotTo(CFrame.new(state.Point+Vector3.new(0,bob,0)))
   if now-state.Ripple>1.6 then state.Ripple=now; splash(state.Point) end
  end
  state.Line.CurveSize0=if state.Phase=="Hook" then .15 else .9
 end
end)
Players.PlayerRemoving:Connect(function(player) clear(player.UserId) end)
